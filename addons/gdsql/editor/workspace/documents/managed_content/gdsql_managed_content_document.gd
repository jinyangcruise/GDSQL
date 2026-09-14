@tool
extends MarginContainer
## Configures managed package inputs, builds the cache, and inspects saves.

signal create_base_database_requested

var _action_hub: GDSQLEditorActionHub
var _workbench: GDSQLWorkbench
var _configuration_loaded := false
var _pending_save: GDSQLDatabaseRegistration
var _configuration_store := GDSQLConfigFileManagedContentConfigurationStore.new()

@onready var _base_root: LineEdit = %BasePackageRoot
@onready var _package_roots: TextEdit = %PackageRoots
@onready var _enabled_packages: TextEdit = %EnabledPackages
@onready var _package_tree: Tree = %PackageTree
@onready var _package_preview: VBoxContainer = %PackagePreview
@onready var _record_content: Button = %RecordCurrentSet
@onready var _record_confirmation: ConfirmationDialog = %RecordConfirmation


func _ready() -> void:
	%CreateBaseDatabase.pressed.connect(create_base_database_requested.emit)
	%ValidatePackages.pressed.connect(_validate_packages)
	%BuildCache.pressed.connect(_build_cache)
	%RefreshStatus.pressed.connect(refresh_status)
	_record_content.pressed.connect(_request_record_content)
	_record_confirmation.confirmed.connect(_record_content_confirmed)
	_configure_tree()
	if _is_scene_preview():
		return
	_package_preview.hide()
	_package_tree.show()
	_load_configuration()
	refresh_status()


func configure(action_hub: GDSQLEditorActionHub, workbench: GDSQLWorkbench) -> void:
	_action_hub = action_hub
	_workbench = workbench
	if not _configuration_loaded:
		_load_configuration()
	refresh_status()


func refresh_status() -> void:
	if not is_node_ready() or _is_scene_preview():
		return
	var resolved := _resolve_packages()
	_refresh_cache_and_save()
	if resolved.is_successful():
		%Status.text = "%d package(s) selected in deterministic load order." \
				% resolved.ordered_packages.size()
	else:
		%Status.text = _first_diagnostic(resolved)


func _load_configuration() -> void:
	if not is_node_ready() or _configuration_loaded:
		return
	var loaded := _configuration_store.load_configuration()
	var configuration := loaded.get_value() as GDSQLManagedContentConfiguration
	if configuration == null:
		configuration = GDSQLManagedContentConfiguration.create_default()
		%Status.text = _first_diagnostic(loaded)
	_base_root.text = configuration.base_package_root
	_package_roots.text = "\n".join(configuration.package_container_roots)
	var enabled_ids: Array[String] = []
	for package_id in configuration.enabled_package_ids:
		enabled_ids.append(String(package_id))
	_enabled_packages.text = "\n".join(enabled_ids)
	_configuration_loaded = true


func _save_configuration() -> GDSQLOperationResult:
	return _configuration_store.save_configuration(
		GDSQLManagedContentConfiguration.new(
			_base_root.text.strip_edges(),
			_lines(_package_roots.text),
			_enabled_ids(),
		),
	)


func _resolve_packages() -> GDSQLContentPackageResolutionResult:
	var discovered := GDSQLConfigFileContentPackageDiscovery.new().discover(
		_base_root.text.strip_edges(),
		_lines(_package_roots.text),
	)
	var packages := discovered.get_value() as Array[GDSQLContentPackageSource]
	_populate_packages(packages, _enabled_ids())
	var result := GDSQLContentPackageResolutionResult.new()
	result.diagnostics.merge(discovered.diagnostics)
	if not discovered.is_successful():
		return result
	var resolved := GDSQLContentPackageResolver.new().resolve(packages, _enabled_ids())
	resolved.diagnostics.entries.append_array(result.diagnostics.entries)
	return resolved


func _validate_packages() -> void:
	var resolved := _resolve_packages()
	%Status.text = (
			"Configuration is valid. Load order: %s." % _package_order(resolved)
			if resolved.is_successful()
			else _first_diagnostic(resolved)
	)


func _build_cache() -> void:
	var saved := _save_configuration()
	if not saved.is_successful():
		%Status.text = _first_diagnostic(saved)
		return
	var resolved := _resolve_packages()
	if not resolved.is_successful():
		%Status.text = _first_diagnostic(resolved)
		return
	var manager := GDSQLContentCacheManager.new(
		GDSQLContentOverlayLoader.new(GDSQLConfigFileContentPackageLayerReader.new()),
		GDSQLConfigFileContentPackageFingerprintProvider.new(),
		GDSQLConfigFileContentCacheStore.new(),
	)
	var cached := manager.ensure_cache(resolved.ordered_packages)
	%Status.text = (
			"Effective content cache rebuilt successfully."
			if cached.is_successful() and cached.was_rebuilt()
			else (
					"Effective content cache is already current."
					if cached.is_successful()
					else _first_diagnostic(cached)
			)
	)
	_refresh_cache_and_save()


func _refresh_cache_and_save() -> void:
	var loaded := GDSQLConfigFileContentCacheStore.new().load_manifest()
	var active := loaded.get_value() as GDSQLContentCacheManifest
	%CacheStatus.text = "READY" if active != null else "NOT BUILT"
	%CacheStatus.modulate = (
			Color(0.42, 0.82, 0.55) if active != null else Color(1.0, 0.72, 0.32)
	)
	%CacheDetail.text = (
			"%d package(s) cached as '%s'." % [
				active.packages.size(),
				active.effective_database_name,
			]
			if active != null
			else "Validate the package configuration, then build the disposable cache."
	)
	_refresh_save_compatibility(active)


func _refresh_save_compatibility(active: GDSQLContentCacheManifest) -> void:
	_pending_save = _active_save_registration()
	_record_content.disabled = active == null or _pending_save == null
	if _pending_save == null:
		_set_save_status("NO ACTIVE SAVE", "Create or select a save slot first.", false)
		return
	if active == null:
		_set_save_status("NO ACTIVE CONTENT", "Build the effective cache first.", false)
		return
	var loaded := GDSQLConfigFileSaveContentManifestStore.new(
		_pending_save.data_root,
	).load_manifest()
	if not loaded.is_successful():
		_set_save_status("UNREADABLE", _first_diagnostic(loaded), false)
		return
	var report := GDSQLSaveContentCompatibilityInspector.inspect(
		loaded.get_value() as GDSQLSaveContentManifest,
		active,
	)
	match report.status:
		GDSQLSaveContentCompatibilityReport.Status.EXACT:
			_set_save_status("COMPATIBLE", "The active package set matches this save.", true)
		GDSQLSaveContentCompatibilityReport.Status.UNTRACKED:
			_set_save_status("NOT RECORDED", "Record the current set for this save.", false)
		GDSQLSaveContentCompatibilityReport.Status.MISSING_PACKAGES:
			var missing_ids: Array[String] = []
			for package in report.missing_packages:
				missing_ids.append(String(package.package_id))
			_set_save_status(
				"MISSING PACKAGES",
				"Not active: %s. Re-enable them or apply an explicit game policy." \
						% ", ".join(missing_ids),
				false,
			)
		GDSQLSaveContentCompatibilityReport.Status.CHANGED:
			_set_save_status("REVIEW CHANGES", _first_report_diagnostic(report), false)
		_:
			_set_save_status("UNAVAILABLE", _first_report_diagnostic(report), false)


func _request_record_content() -> void:
	if _pending_save == null:
		return
	_record_confirmation.dialog_text = (
			"Record the current effective-content package set for save '%s'?\n\n"
			+ "This replaces its previous compatibility expectation. Save rows are unchanged."
	) % _pending_save.database_name
	_record_confirmation.popup_centered(Vector2i(560, 210))


func _record_content_confirmed() -> void:
	var loaded := GDSQLConfigFileContentCacheStore.new().load_manifest()
	var active := loaded.get_value() as GDSQLContentCacheManifest
	if _pending_save == null or active == null:
		refresh_status()
		return
	var saved := GDSQLConfigFileSaveContentManifestStore.new(
		_pending_save.data_root,
	).save_manifest(GDSQLSaveContentManifest.from_cache_manifest(active))
	%Status.text = (
			"Recorded the active package set for save '%s'." % _pending_save.database_name
			if saved.is_successful()
			else _first_diagnostic(saved)
	)
	_refresh_cache_and_save()


func _active_save_registration() -> GDSQLDatabaseRegistration:
	if _workbench == null:
		return null
	var selected := &""
	for binding in _workbench.snapshot.role_bindings:
		if binding.role == GDSQLDatabaseRegistry.SAVE_ROLE:
			selected = binding.registration_name
	return _workbench.get_registration(selected)


func _populate_packages(
		packages: Array[GDSQLContentPackageSource],
		enabled_ids: Array[StringName],
) -> void:
	_package_tree.clear()
	var root := _package_tree.create_item()
	for package in packages:
		var item := _package_tree.create_item(root)
		item.set_text(0, String(package.manifest.package_id))
		item.set_text(1, GDSQLContentPackageKind.get_id(package.manifest.kind).to_upper())
		item.set_text(2, package.manifest.version)
		item.set_text(
			3,
			"Base" if package.manifest.kind == GDSQLContentPackageKind.Kind.BASE_GAME \
			else ("Enabled" if package.manifest.package_id in enabled_ids else "Available"),
		)
		item.set_text(4, package.package_root)
	%PackageSummary.text = "%d package(s) discovered" % packages.size()


func _configure_tree() -> void:
	var titles := ["Package", "Kind", "Version", "Selection", "Source"]
	for column in titles.size():
		_package_tree.set_column_title(column, titles[column])
		_package_tree.set_column_expand(column, column in [0, 4])
	_package_tree.set_column_custom_minimum_width(0, 170)
	_package_tree.set_column_custom_minimum_width(1, 80)
	_package_tree.set_column_custom_minimum_width(2, 100)
	_package_tree.set_column_custom_minimum_width(3, 100)
	_package_tree.set_column_custom_minimum_width(4, 260)


func _set_save_status(title: String, detail: String, ready: bool) -> void:
	%SaveStatus.text = title
	%SaveStatus.modulate = Color(0.42, 0.82, 0.55) if ready else Color(1.0, 0.72, 0.32)
	%SaveDetail.text = detail


func _enabled_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for line in _lines(_enabled_packages.text):
		ids.append(StringName(line))
	return ids


func _lines(value: String) -> Array[String]:
	var values: Array[String] = []
	for line in value.split("\n"):
		var trimmed := line.strip_edges()
		if not trimmed.is_empty():
			values.append(trimmed)
	return values


func _package_order(result: GDSQLContentPackageResolutionResult) -> String:
	var ids: Array[String] = []
	for package in result.ordered_packages:
		ids.append(String(package.manifest.package_id))
	return " → ".join(ids)


func _first_diagnostic(result: GDSQLOperationResult) -> String:
	return (
			result.diagnostics.entries[0].message
			if not result.diagnostics.entries.is_empty()
			else "The operation could not be completed."
	)


func _first_report_diagnostic(report: GDSQLSaveContentCompatibilityReport) -> String:
	return (
			report.diagnostics.entries[0].message
			if not report.diagnostics.entries.is_empty()
			else "No compatibility detail is available."
	)


func _is_scene_preview() -> bool:
	if not Engine.is_editor_hint():
		return false
	var edited_scene_root := EditorInterface.get_edited_scene_root()
	return edited_scene_root == self \
			or (edited_scene_root != null and edited_scene_root.is_ancestor_of(self))
