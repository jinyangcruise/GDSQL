@tool
extends MarginContainer
## Selects one setup profile, then presents only that profile's progress.

const SETTINGS_PATH := "res://.gdsql/settings.cfg"
const DEFAULT_BASE_ROOT := "res://content/base"
const RUNTIME_AUTOLOAD_SETTING := "autoload/GDSQLRuntime"
const RUNTIME_NODE_PATH := "res://addons/gdsql/runtime/gdsql_runtime_node.tscn"

var _action_hub: GDSQLEditorActionHub
var _workbench: GDSQLWorkbench
var _profile_store := GDSQLConfigFileSetupProfileStore.new()
var _profile := GDSQLSetupProfile.Kind.UNSELECTED
var _pending_profile := GDSQLSetupProfile.Kind.UNSELECTED
var _setup_report: GDSQLSetupReport
var _managed_base_inspection: GDSQLDatabaseInspection

@onready var _create_database_button: GDSQLEditorActionButton = %CreateDatabase
@onready var _refresh_button: GDSQLEditorActionButton = %RefreshDatabases
@onready var _managed_refresh_button: GDSQLEditorActionButton = %ManagedRefresh
@onready var _save_slots_button: GDSQLEditorActionButton = %ManageSaveSlots
@onready var _managed_content_button: GDSQLEditorActionButton = %OpenManagedContent
@onready var _database_list: ItemList = %DatabaseList
@onready var _open_database: Button = %OpenDatabase
@onready var _next_action_button: Button = %NextAction
@onready var _profile_confirmation: ConfirmationDialog = %ProfileConfirmation
@onready var _reset_confirmation: ConfirmationDialog = %ResetProfileConfirmation


func _ready() -> void:
	%ChooseDirect.pressed.connect(_request_profile.bind(GDSQLSetupProfile.Kind.DIRECT))
	%ChooseManaged.pressed.connect(_request_profile.bind(GDSQLSetupProfile.Kind.MANAGED))
	%ChangeProfile.pressed.connect(_reset_confirmation.popup_centered.bind(Vector2i(570, 220)))
	_profile_confirmation.confirmed.connect(_confirm_profile)
	_reset_confirmation.confirmed.connect(_clear_profile)
	_database_list.item_selected.connect(_on_database_selected)
	_database_list.item_activated.connect(_open_database_at)
	_open_database.pressed.connect(_open_selected_database)
	_next_action_button.pressed.connect(_run_next_action)
	if not _is_scene_preview():
		refresh_status()


func configure(action_hub: GDSQLEditorActionHub, workbench: GDSQLWorkbench) -> void:
	_action_hub = action_hub
	_workbench = workbench
	_create_database_button.configure_action(action_hub, GDSQLEditorActionIds.CREATE_DATABASE)
	_refresh_button.configure_action(action_hub, GDSQLEditorActionIds.REFRESH_DATABASES)
	_managed_refresh_button.configure_action(action_hub, GDSQLEditorActionIds.REFRESH_DATABASES)
	_save_slots_button.configure_action(action_hub, GDSQLEditorActionIds.SHOW_SAVE_SLOTS)
	_managed_content_button.configure_action(
		action_hub,
		GDSQLEditorActionIds.SHOW_MANAGED_CONTENT,
	)
	refresh_status()


func refresh_status() -> void:
	if not is_node_ready() or _is_scene_preview():
		return
	var loaded_profile := _profile_store.load_profile()
	_profile = (
		loaded_profile.get_value() as GDSQLSetupProfile.Kind
		if loaded_profile.is_successful()
		else GDSQLSetupProfile.Kind.UNSELECTED
	)
	%ProfileChoice.visible = _profile == GDSQLSetupProfile.Kind.UNSELECTED
	%SelectedSetup.visible = _profile != GDSQLSetupProfile.Kind.UNSELECTED
	if _profile == GDSQLSetupProfile.Kind.UNSELECTED:
		%Title.text = "Choose your content profile"
		%Summary.text = (
			loaded_profile.diagnostics.entries[0].message
			if not loaded_profile.is_successful()
			else "Choose the workflow that matches how this project will ship and extend content."
		)
		return
	var registrations := _registrations()
	var inspections := _inspections()
	var counts := _project_counts(inspections)
	%Title.text = (
		"Direct content setup"
		if _profile == GDSQLSetupProfile.Kind.DIRECT
		else "Managed content setup"
	)
	%ActiveProfile.text = (
		"DIRECT CONTENT"
		if _profile == GDSQLSetupProfile.Kind.DIRECT
		else "MANAGED CONTENT"
	)
	%ProfileDetail.text = (
		"Project-authored definitions are consumed directly from res://data."
		if _profile == GDSQLSetupProfile.Kind.DIRECT
		else "Immutable packages build one effective runtime content database."
	)
	%Summary.text = "%d database(s) · %d table(s) · %d stored row(s)" % [
		registrations.size(),
		counts.x,
		counts.y,
	]
	%DirectActions.visible = _profile == GDSQLSetupProfile.Kind.DIRECT
	%ManagedActions.visible = _profile == GDSQLSetupProfile.Kind.MANAGED
	_setup_report = (
		_build_direct_report(inspections)
		if _profile == GDSQLSetupProfile.Kind.DIRECT
		else _build_managed_report()
	)
	_render_checklist(_setup_report)
	_populate_databases(registrations, inspections)
	_refresh_next_action(_setup_report.get_next_incomplete())


func _build_direct_report(
		inspections: Array[GDSQLDatabaseInspection],
) -> GDSQLDirectSetupReport:
	return GDSQLDirectSetupInspector.inspect_editor(
		_workbench.snapshot if _workbench != null else GDSQLDatabaseRegistrySnapshot.new(),
		inspections,
		_count_model_scripts(),
		_is_runtime_adapter_configured(),
	)


func _build_managed_report() -> GDSQLManagedSetupReport:
	var source: GDSQLContentPackageSource
	var loaded := GDSQLConfigFileContentPackageManifestStore.new().load_manifest(
		_managed_base_root(),
	)
	if loaded.is_successful():
		source = GDSQLContentPackageSource.new(_managed_base_root(), loaded.get_value())
	_managed_base_inspection = _inspect_managed_base(source)
	var cached := GDSQLConfigFileContentCacheStore.new().load_manifest()
	return GDSQLManagedSetupInspector.inspect_editor(
		source,
		_managed_base_inspection,
		cached.get_value() as GDSQLContentCacheManifest,
		_workbench.snapshot if _workbench != null else GDSQLDatabaseRegistrySnapshot.new(),
		_count_model_scripts(),
		_is_runtime_adapter_configured(),
	)


func _inspect_managed_base(
		source: GDSQLContentPackageSource,
) -> GDSQLDatabaseInspection:
	if source == null:
		return null
	var inspected := GDSQLConfigFileDatabaseExplorer.new().inspect_root(source.get_data_root())
	if not inspected.is_successful():
		return null
	for value in inspected.get_value():
		var inspection := value as GDSQLDatabaseInspection
		if inspection.registration.database_name == &"content":
			return inspection
	return null


func _render_checklist(report: GDSQLSetupReport) -> void:
	var rows: Array[Control] = [
		%Step1, %Step2, %Step3, %Step4, %Step5, %Step6, %Step7,
	]
	var statuses: Array[Label] = [
		%Step1Status, %Step2Status, %Step3Status, %Step4Status,
		%Step5Status, %Step6Status, %Step7Status,
	]
	var labels: Array[Label] = [
		%Step1Label, %Step2Label, %Step3Label, %Step4Label,
		%Step5Label, %Step6Label, %Step7Label,
	]
	var details: Array[Label] = [
		%Step1Detail, %Step2Detail, %Step3Detail, %Step4Detail,
		%Step5Detail, %Step6Detail, %Step7Detail,
	]
	var next_check := report.get_next_incomplete()
	for index in rows.size():
		var has_check := index < report.checks.size()
		rows[index].visible = has_check
		if not has_check:
			continue
		var check := report.checks[index]
		labels[index].text = check.label
		_set_step_state(
			statuses[index],
			details[index],
			check.complete,
			check == next_check,
			check.detail,
		)


func _populate_databases(
		registrations: Array[GDSQLDatabaseRegistration],
		inspections: Array[GDSQLDatabaseInspection],
) -> void:
	_database_list.clear()
	for registration in registrations:
		var inspection := _inspection_for(registration.name, inspections)
		var tables := inspection.tables.size() if inspection != null else 0
		var rows := 0
		if inspection != null:
			for table in inspection.tables:
				rows += table.row_count
		var index := _database_list.add_item(
			"%s  —  %d table(s), %d row(s)\n%s" % [
				registration.database_name, tables, rows, registration.data_root,
			],
		)
		_database_list.set_item_metadata(index, registration.name)
	%NoDatabases.visible = registrations.is_empty()
	_database_list.visible = not registrations.is_empty()
	if not registrations.is_empty():
		_database_list.select(0)
	_open_database.disabled = registrations.is_empty()


func _refresh_next_action(check: GDSQLSetupCheck) -> void:
	if check == null:
		%NextStep.text = "This profile's setup checklist is complete."
		_next_action_button.hide()
		return
	%NextStep.text = "Next: %s" % check.detail
	_next_action_button.visible = check.next_action != GDSQLSetupCheck.ACTION_NONE
	match check.next_action:
		GDSQLSetupCheck.ACTION_CREATE_DATABASE:
			_next_action_button.text = "Create Content"
		GDSQLSetupCheck.ACTION_OPEN_CONTENT_DATABASE, GDSQLSetupCheck.ACTION_OPEN_BASE_DATABASE:
			_next_action_button.text = "Open Database"
		GDSQLSetupCheck.ACTION_OPEN_CONTENT_TABLE, GDSQLSetupCheck.ACTION_OPEN_BASE_TABLE:
			_next_action_button.text = "Open Table"
		GDSQLSetupCheck.ACTION_OPEN_MANAGED_CONTENT:
			_next_action_button.text = "Open Managed Setup"
		GDSQLSetupCheck.ACTION_MANAGE_SAVE_SLOTS:
			_next_action_button.text = "Manage Saves"
		GDSQLSetupCheck.ACTION_INSTALL_RUNTIME:
			_next_action_button.text = "Install Runtime"


func _run_next_action() -> void:
	if _action_hub == null or _setup_report == null:
		return
	var check := _setup_report.get_next_incomplete()
	if check == null:
		return
	match check.next_action:
		GDSQLSetupCheck.ACTION_CREATE_DATABASE:
			_action_hub.invoke(GDSQLEditorActionIds.CREATE_DATABASE, [], true)
		GDSQLSetupCheck.ACTION_OPEN_CONTENT_DATABASE:
			_open_direct_database()
		GDSQLSetupCheck.ACTION_OPEN_CONTENT_TABLE:
			_open_direct_table()
		GDSQLSetupCheck.ACTION_OPEN_MANAGED_CONTENT:
			_action_hub.invoke(GDSQLEditorActionIds.SHOW_MANAGED_CONTENT, [], true)
		GDSQLSetupCheck.ACTION_OPEN_BASE_DATABASE:
			_open_managed_database()
		GDSQLSetupCheck.ACTION_OPEN_BASE_TABLE:
			_open_managed_table()
		GDSQLSetupCheck.ACTION_MANAGE_SAVE_SLOTS:
			_action_hub.invoke(GDSQLEditorActionIds.SHOW_SAVE_SLOTS, [], true)
		GDSQLSetupCheck.ACTION_INSTALL_RUNTIME:
			_action_hub.invoke(GDSQLEditorActionIds.INSTALL_RUNTIME_ADAPTER)
			refresh_status()


func _request_profile(profile: GDSQLSetupProfile.Kind) -> void:
	_pending_profile = profile
	var managed := profile == GDSQLSetupProfile.Kind.MANAGED
	_profile_confirmation.title = "Choose %s Content" % ("Managed" if managed else "Direct")
	_profile_confirmation.ok_button_text = "Choose Profile"
	_profile_confirmation.dialog_text = (
		("Managed content uses immutable packages and a generated effective-content database."
		if managed else "Direct content reads project-authored definitions from res://data.")
		+ "\n\nGDSQL will not move or rewrite existing databases. Changing profiles later "
		+ "requires an explicit content migration."
	)
	_profile_confirmation.popup_centered(Vector2i(590, 230))


func _confirm_profile() -> void:
	var saved := _profile_store.save_profile(_pending_profile)
	if saved.is_successful():
		refresh_status()
	else:
		%Summary.text = saved.diagnostics.entries[0].message


func _clear_profile() -> void:
	var cleared := _profile_store.clear_profile()
	if cleared.is_successful():
		refresh_status()
	else:
		%Summary.text = cleared.diagnostics.entries[0].message


func _open_direct_database() -> void:
	var registration := _role_registration(GDSQLDatabaseRegistry.CONTENT_ROLE)
	if registration == null:
		_action_hub.invoke(GDSQLEditorActionIds.CREATE_DATABASE, [], true)
	else:
		_open_registration(registration.name)


func _open_direct_table() -> void:
	_open_first_table(_role_inspection(GDSQLDatabaseRegistry.CONTENT_ROLE))


func _open_managed_database() -> void:
	if _managed_base_inspection == null:
		_action_hub.invoke(GDSQLEditorActionIds.SHOW_MANAGED_CONTENT, [], true)
		return
	var registration := _registration_for_database(
		_managed_base_inspection.registration.database_name,
		_managed_base_inspection.registration.data_root,
	)
	if registration == null:
		_action_hub.invoke(GDSQLEditorActionIds.SHOW_MANAGED_CONTENT, [], true)
	else:
		_open_registration(registration.name)


func _open_managed_table() -> void:
	_open_first_table(_managed_base_inspection)


func _open_first_table(inspection: GDSQLDatabaseInspection) -> void:
	if inspection == null or inspection.tables.is_empty():
		if _profile == GDSQLSetupProfile.Kind.MANAGED:
			_open_managed_database()
		else:
			_open_direct_database()
		return
	var registration := _registration_for_database(
		inspection.registration.database_name,
		inspection.registration.data_root,
	)
	if registration == null:
		if _profile == GDSQLSetupProfile.Kind.MANAGED:
			_action_hub.invoke(GDSQLEditorActionIds.SHOW_MANAGED_CONTENT, [], true)
		return
	var table := inspection.tables[0]
	for candidate in inspection.tables:
		if candidate.schema_exists and candidate.storage_exists:
			table = candidate
			break
	_action_hub.invoke(
		GDSQLEditorActionIds.SELECT_TABLE,
		[registration.name, table.name],
		true,
	)


func _set_step_state(
		status: Label,
		detail: Label,
		complete: bool,
		is_next: bool,
		message: String,
) -> void:
	status.text = "✓" if complete else ("→" if is_next else "○")
	status.modulate = Color(0.42, 0.82, 0.55) if complete else Color(0.65, 0.7, 0.78)
	detail.text = message
	detail.modulate = Color.WHITE if complete or is_next else Color(0.7, 0.72, 0.76)


func _registrations() -> Array[GDSQLDatabaseRegistration]:
	var registrations: Array[GDSQLDatabaseRegistration] = []
	if _workbench != null:
		registrations = _workbench.get_registrations()
	registrations.sort_custom(
		func(left: GDSQLDatabaseRegistration, right: GDSQLDatabaseRegistration) -> bool:
			return String(left.database_name).naturalnocasecmp_to(String(right.database_name)) < 0,
	)
	return registrations


func _inspections() -> Array[GDSQLDatabaseInspection]:
	var inspections: Array[GDSQLDatabaseInspection] = []
	if _workbench != null:
		inspections = _workbench.get_inspections()
	return inspections


func _project_counts(inspections: Array[GDSQLDatabaseInspection]) -> Vector2i:
	var counts := Vector2i.ZERO
	for inspection in inspections:
		counts.x += inspection.tables.size()
		for table in inspection.tables:
			counts.y += table.row_count
	return counts


func _inspection_for(
		registration_name: StringName,
		inspections: Array[GDSQLDatabaseInspection],
) -> GDSQLDatabaseInspection:
	for inspection in inspections:
		if inspection.registration != null and inspection.registration.name == registration_name:
			return inspection
	return null


func _role_registration(role: StringName) -> GDSQLDatabaseRegistration:
	if _workbench == null:
		return null
	var selected := &""
	for binding in _workbench.snapshot.role_bindings:
		if binding.role == role:
			selected = binding.registration_name
	return _workbench.get_registration(selected)


func _role_inspection(role: StringName) -> GDSQLDatabaseInspection:
	var registration := _role_registration(role)
	return _workbench.get_inspection(registration.name) if registration != null else null


func _registration_for_database(
		database_name: StringName,
		data_root: String,
) -> GDSQLDatabaseRegistration:
	for registration in _registrations():
		if registration.database_name == database_name and registration.data_root == data_root:
			return registration
	return null


func _open_registration(registration_name: StringName) -> void:
	_action_hub.invoke(GDSQLEditorActionIds.OPEN_REGISTRATION, [registration_name], true)


func _managed_base_root() -> String:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	return String(config.get_value("managed_content", "base_package_root", DEFAULT_BASE_ROOT))


func _is_runtime_adapter_configured() -> bool:
	var configured_path := String(ProjectSettings.get_setting(RUNTIME_AUTOLOAD_SETTING, ""))
	return configured_path.trim_prefix("*") == RUNTIME_NODE_PATH


func _count_model_scripts() -> int:
	var root := GDSQLModelSourceGenerator.DEFAULT_ROOT
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		root = String(config.get_value("models", "root", root))
	var directory := DirAccess.open(root)
	if directory == null:
		return 0
	var count := 0
	for file_name in directory.get_files():
		if file_name.get_extension() == "gd":
			count += 1
	return count


func _on_database_selected(_index: int) -> void:
	_open_database.disabled = false


func _open_selected_database() -> void:
	var selected := _database_list.get_selected_items()
	if not selected.is_empty():
		_open_database_at(selected[0])


func _open_database_at(index: int) -> void:
	if _action_hub == null or index < 0 or index >= _database_list.item_count:
		return
	_open_registration(_database_list.get_item_metadata(index))


func _is_scene_preview() -> bool:
	if not Engine.is_editor_hint():
		return false
	var edited_scene_root := EditorInterface.get_edited_scene_root()
	return edited_scene_root == self \
			or (edited_scene_root != null and edited_scene_root.is_ancestor_of(self))
