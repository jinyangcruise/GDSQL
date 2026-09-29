@tool
extends MarginContainer
## Previews and safely writes a generated schema base plus a user-owned model.

signal close_requested
signal scripts_generated(generated_path: String, user_path: String)
signal content_reference_registered(registration_name: StringName, table_name: StringName)

const SETTINGS_PATH := "res://.gdsql/settings.cfg"
const SETTINGS_SECTION := "models"
const SETTINGS_ROOT_KEY := "root"
const SETTINGS_BINDING_PREFIX := "model_binding:"
const SETTINGS_CLASS_KEY := "class_name"
const SETTINGS_ROLE_KEY := "role"

var _registration_name: StringName
var _table: GDSQLTableDefinition
var _database: GDSQLDatabaseDefinition
var _inspections: Array[GDSQLDatabaseInspection] = []
var _role_bindings: Array[GDSQLDatabaseRoleBinding] = []
var _source: GDSQLModelSource
var _generator := GDSQLModelSourceGenerator.new()
var _compatibility_inspector := GDSQLModelCompatibilityInspector.new()
var _refresh_after_filesystem_scan := false
var _filesystem_retry_active := false
var _last_reported_script_error := ""

@onready var _model_class: LineEdit = %ModelClass
@onready var _role: OptionButton = %Role
@onready var _custom_role: LineEdit = %CustomRole
@onready var _model_root: LineEdit = %ModelRoot
@onready var _generated_preview: CodeEdit = %GeneratedPreview
@onready var _user_preview: CodeEdit = %UserPreview


func _ready() -> void:
	if _is_scene_preview():
		return
	%ScenePreview.hide()
	_role.set_item_metadata(0, GDSQLDatabaseRegistry.CONTENT_ROLE)
	_role.set_item_metadata(1, GDSQLDatabaseRegistry.SAVE_ROLE)
	_role.set_item_metadata(2, GDSQLDatabaseRegistry.SETTINGS_ROLE)
	_role.set_item_metadata(3, &"")
	_model_class.text_changed.connect(_on_text_changed)
	_model_root.text_changed.connect(_on_text_changed)
	_model_class.focus_exited.connect(_save_preferences_if_valid)
	_model_root.focus_exited.connect(_save_preferences_if_valid)
	_custom_role.text_changed.connect(_on_text_changed)
	_role.item_selected.connect(_on_role_selected)
	%Generate.pressed.connect(_request_generation)
	%OpenUserScript.pressed.connect(_open_user_script)
	%CopyScaffold.pressed.connect(_copy_scaffold)
	%CrossRoleHelper.reference_registered.connect(
		_on_content_reference_registered,
	)
	%Close.pressed.connect(_request_close)
	%OverwriteConfirmation.confirmed.connect(_write_sources)
	var filesystem := EditorInterface.get_resource_filesystem()
	if not filesystem.filesystem_changed.is_connected(_on_filesystem_changed):
		filesystem.filesystem_changed.connect(_on_filesystem_changed)
	if not filesystem.script_classes_updated.is_connected(_on_filesystem_changed):
		filesystem.script_classes_updated.connect(_on_filesystem_changed)


func configure(
		registration_name: StringName,
		table: GDSQLTableDefinition,
		database_role: StringName = GDSQLDatabaseRegistry.CONTENT_ROLE,
		database: GDSQLDatabaseDefinition = null,
		inspections: Array[GDSQLDatabaseInspection] = [],
		role_bindings: Array[GDSQLDatabaseRoleBinding] = [],
) -> void:
	_registration_name = registration_name
	_table = table
	_database = database
	_inspections = inspections.duplicate()
	_role_bindings = role_bindings.duplicate()
	%Title.text = "Model binding · %s" % table.name
	%TableValue.text = _table_identity(table)
	_model_root.text = _load_model_root()
	_select_role(database_role)
	_update_model_class_placeholder()
	_model_class.text = _load_model_class()
	_refresh_preview()
	_refresh_cross_role_helper()


func refresh_table(
		table: GDSQLTableDefinition,
		database: GDSQLDatabaseDefinition = null,
) -> void:
	if table == null:
		return
	_table = table
	_database = database
	%Title.text = "Model binding · %s" % table.name
	%TableValue.text = _table_identity(table)
	_refresh_preview()
	_refresh_cross_role_helper()


func _table_identity(table: GDSQLTableDefinition) -> String:
	if table.database_name == &"":
		return String(table.name)
	return "%s / %s" % [table.database_name, table.name]


func _is_scene_preview() -> bool:
	if not Engine.is_editor_hint():
		return false
	var edited_scene_root := EditorInterface.get_edited_scene_root()
	return edited_scene_root == self \
			or (edited_scene_root != null and edited_scene_root.is_ancestor_of(self))


func _suggest_class_name(table_name: String) -> String:
	var singular := table_name
	if singular.ends_with("ies") and singular.length() > 3:
		singular = singular.left(-3) + "y"
	elif singular.ends_with("oes") and singular.length() > 3:
		singular = singular.left(-2)
	elif singular.ends_with("s") \
			and not singular.ends_with("ss") \
			and not singular.ends_with("us") \
			and not singular.ends_with("is"):
		singular = singular.left(-1)
	return singular.to_pascal_case()


func _select_role(database_role: StringName) -> void:
	var matched := false
	for index in range(3):
		if StringName(_role.get_item_metadata(index)) == database_role:
			_role.select(index)
			matched = true
			break
	if not matched:
		_role.select(3)
		_custom_role.text = String(database_role)
	_on_role_selected(_role.selected)


func _on_role_selected(index: int) -> void:
	%CustomRoleRow.visible = index == 3
	_custom_role.visible = index == 3
	_update_model_class_placeholder()
	_refresh_preview()
	_refresh_cross_role_helper()


func _on_text_changed(_value: String) -> void:
	_refresh_preview()


func _selected_role() -> StringName:
	if _role.selected == 3:
		return StringName(_custom_role.text.strip_edges())
	return StringName(_role.get_item_metadata(_role.selected))


func _update_model_class_placeholder() -> void:
	if _table == null:
		return
	var example := _suggest_class_name(String(_table.name)) + _role_class_suffix()
	_model_class.placeholder_text = "Use a singular class name, e.g. %s" % example


func _role_class_suffix() -> String:
	match _selected_role():
		GDSQLDatabaseRegistry.CONTENT_ROLE:
			return "Content"
		GDSQLDatabaseRegistry.SAVE_ROLE:
			return "Save"
		GDSQLDatabaseRegistry.SETTINGS_ROLE:
			return "Settings"
		_:
			return "Model"


func _refresh_cross_role_helper() -> void:
	if not is_node_ready():
		return
	%CrossRoleHelper.visible = _selected_role() == GDSQLDatabaseRegistry.SAVE_ROLE
	if %CrossRoleHelper.visible:
		%CrossRoleHelper.configure(
			_registration_name,
			_table,
			_inspections,
			_role_bindings,
		)


func _refresh_preview() -> void:
	if _table == null or not is_node_ready():
		return
	_refresh_relationship_help()
	var result := _generator.build(
		_table,
		StringName(_model_class.text.strip_edges()),
		_selected_role(),
		_model_root.text,
	)
	_source = result.get_value() as GDSQLModelSource
	if not result.is_successful() or _source == null:
		_generated_preview.text = ""
		_user_preview.text = ""
		%GeneratedPath.text = "Generated base: —"
		%UserPath.text = "User model: —"
		%Status.text = _first_diagnostic(result, "The model preview is invalid.")
		_set_compatibility_unavailable("Resolve the preview errors before inspecting the model.")
		%Generate.disabled = true
		%OpenUserScript.disabled = true
		return
	%GeneratedPath.text = "Generated base: %s%s" % [
		_source.generated_path,
		" · will be replaced" if FileAccess.file_exists(_source.generated_path) else "",
	]
	var user_exists := FileAccess.file_exists(_source.user_path)
	%UserPath.text = "User model: %s%s" % [
		_source.user_path,
		" · preserved" if user_exists else " · created once",
	]
	_generated_preview.text = _source.generated_source
	_user_preview.text = (
			_read_text(_source.user_path) if user_exists else _source.user_source
	)
	%UserPreviewTitle.text = (
			"User model · existing file preserved"
			if user_exists
			else "User model · created once"
	)
	_refresh_compatibility(user_exists)
	%Status.text = _first_diagnostic(
		result,
		"Preview ready. The table remains the schema source of truth.",
	)
	%Generate.disabled = false
	%OpenUserScript.disabled = not user_exists


func _open_user_script() -> void:
	if _source == null or not FileAccess.file_exists(_source.user_path):
		%Status.text = "Generate the user-owned model before opening its script."
		return
	var script := ResourceLoader.load(
		_source.user_path,
		"Script",
		ResourceLoader.CACHE_MODE_REPLACE,
	) as Script
	if script == null:
		%Status.text = "Godot could not load the user model script. Check the Output panel."
		return
	EditorInterface.edit_script(script)


func _refresh_compatibility(user_exists: bool) -> void:
	if not user_exists:
		_set_compatibility_unavailable(
			"Generate the user-owned model, then compatibility will be checked here.",
		)
		return
	var model_script := ResourceLoader.load(
		_source.user_path,
		"Script",
		ResourceLoader.CACHE_MODE_REPLACE,
	) as Script
	var report := _compatibility_inspector.inspect(
		model_script,
		_table,
		_selected_role(),
		_source.generated_path,
	)
	var script_error := _has_diagnostic(
		report,
		&"GDSQL_MODEL_COMPATIBILITY_SCRIPT_UNAVAILABLE",
	)
	%CompatibilityStatus.text = (
			"COMPATIBLE"
			if report.is_compatible()
			else "SCRIPT ERROR" if script_error else "NEEDS UPDATE"
	)
	%CompatibilityStatus.modulate = (
			Color(0.42, 0.82, 0.55)
			if report.is_compatible()
			else Color(1.0, 0.4, 0.4) if script_error else Color(1.0, 0.68, 0.32)
	)
	_report_script_error(report, script_error)
	var lines: Array[String] = []
	for diagnostic in report.diagnostics.entries:
		lines.append("• %s" % diagnostic.message)
	if script_error:
		lines.append("See Godot Output for the reported script error and source path.")
	%CompatibilityDetails.text = "\n".join(lines)
	%CompatibilityDetails.visible = not lines.is_empty()


func _copy_scaffold() -> void:
	if _source == null:
		return
	DisplayServer.clipboard_set(_source.user_source)
	%Status.text = (
			"Copied a clean user-model scaffold. The existing model file was not changed."
	)


func _on_content_reference_registered(
		registration_name: StringName,
		table_name: StringName,
) -> void:
	content_reference_registered.emit(registration_name, table_name)


func _set_compatibility_unavailable(message: String) -> void:
	%CompatibilityStatus.text = "NOT INSPECTED"
	%CompatibilityStatus.modulate = Color(0.62, 0.67, 0.74)
	%CompatibilityDetails.text = message
	%CompatibilityDetails.show()


func _refresh_relationship_help() -> void:
	%CompatibilityHelp.tooltip_text = "\n".join(_catalog_relationship_lines())


func _catalog_relationship_lines() -> Array[String]:
	var lines: Array[String] = []
	var relationships := GDSQLModelRelationshipInferrer.describe(
		_table,
		_database,
	)
	if relationships.is_empty():
		lines.append("No same-database relationships inferred from foreign keys.")
	else:
		lines.append(
			"Catalog relationships · inferred when both model types are registered; no relationship code is written:",
		)
		lines.append(
			"No relationship code is required for these edges; an empty relationships() method avoids duplicate declarations.",
		)
		for relationship in relationships:
			lines.append("• %s" % relationship)
	lines.append(
		"Many-to-many and cross-role relationships are declared explicitly in relationships().",
	)
	return lines


func _request_generation() -> void:
	if _source == null:
		return
	if FileAccess.file_exists(_source.generated_path):
		%OverwriteConfirmation.dialog_text = (
				"Replace the generated schema base?\n\n%s\n\nThe user model will not be changed."
				% _source.generated_path
		)
		%OverwriteConfirmation.popup_centered(Vector2i(560, 220))
		return
	_write_sources()


func _request_close() -> void:
	_save_preferences_if_valid()
	close_requested.emit()


func _save_preferences_if_valid() -> void:
	if _source == null:
		return
	var settings_error := _save_model_settings()
	if settings_error != OK:
		%Status.text = "The model settings could not be saved (error %d)." \
				% settings_error


func _write_sources() -> void:
	if _source == null:
		return
	var generated_directory := _source.generated_path.get_base_dir()
	var user_directory := _source.user_path.get_base_dir()
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(generated_directory),
	)
	if directory_error == OK:
		directory_error = DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(user_directory),
		)
	if directory_error != OK:
		%Status.text = "Could not create the model directories (error %d)." % directory_error
		return
	var generated_error := _write_text(_source.generated_path, _source.generated_source)
	if generated_error != OK:
		%Status.text = "Could not write the generated model (error %d)." % generated_error
		return
	var user_created := false
	if not FileAccess.file_exists(_source.user_path):
		var user_error := _write_text(_source.user_path, _source.user_source)
		if user_error != OK:
			%Status.text = "Generated the base, but could not create the user model (error %d)." \
					% user_error
			return
		user_created = true
	var settings_error := _save_model_settings()
	var message := (
			"Generated the schema base and created the user model."
			if user_created
			else "Regenerated the schema base. The user model was preserved."
	)
	if settings_error != OK:
		message += " The model settings could not be saved (error %d)." \
				% settings_error
	%Status.text = message
	scripts_generated.emit(_source.generated_path, _source.user_path)
	%OpenUserScript.disabled = false
	_refresh_after_filesystem_scan = true
	%CompatibilityStatus.text = "UPDATING"
	%CompatibilityStatus.modulate = Color(0.62, 0.67, 0.74)
	%CompatibilityDetails.text = "Waiting for Godot to import the generated scripts."
	EditorInterface.get_resource_filesystem().scan()
	_on_filesystem_changed()


func _on_filesystem_changed() -> void:
	if _filesystem_retry_active:
		return
	if _refresh_after_filesystem_scan:
		_filesystem_retry_active = true
		_finish_filesystem_refresh()
		return
	if is_node_ready() and _table != null:
		_refresh_preview()


func _finish_filesystem_refresh() -> void:
	for _attempt in 30:
		await get_tree().create_timer(0.1).timeout
		if not _refresh_after_filesystem_scan:
			break
		var model_script := ResourceLoader.load(
			_source.user_path,
			"Script",
			ResourceLoader.CACHE_MODE_REPLACE,
		) as Script
		if model_script != null:
			_refresh_after_filesystem_scan = false
			break
	_filesystem_retry_active = false
	if _refresh_after_filesystem_scan:
		_refresh_after_filesystem_scan = false
	_refresh_preview()


func _write_text(path: String, content: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(content)
	return OK


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	return "" if file == null else file.get_as_text()


func _load_model_root() -> String:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return GDSQLModelSourceGenerator.DEFAULT_ROOT
	return String(
		config.get_value(
			SETTINGS_SECTION,
			SETTINGS_ROOT_KEY,
			GDSQLModelSourceGenerator.DEFAULT_ROOT,
		),
	)


func _load_model_class() -> String:
	return _load_binding_value(
		_registration_name,
		_table.database_name,
		_table.name,
		SETTINGS_CLASS_KEY,
	)


func _load_binding_value(
		registration_name: StringName,
		database_name: StringName,
		table_name: StringName,
		key: String,
) -> String:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return ""
	return String(
		config.get_value(
			_binding_section(registration_name, database_name, table_name),
			key,
			"",
		),
	)


func _binding_section(
		registration_name: StringName,
		database_name: StringName,
		table_name: StringName,
) -> String:
	return "%s%s:%s:%s" % [
		SETTINGS_BINDING_PREFIX,
		registration_name,
		database_name,
		table_name,
	]


func _save_model_settings() -> Error:
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(SETTINGS_PATH.get_base_dir()),
	)
	if directory_error != OK:
		return directory_error
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value(SETTINGS_SECTION, SETTINGS_ROOT_KEY, _model_root.text.strip_edges())
	var binding_section := _binding_section(
		_registration_name,
		_table.database_name,
		_table.name,
	)
	config.set_value(
		binding_section,
		SETTINGS_CLASS_KEY,
		_model_class.text.strip_edges(),
	)
	config.set_value(binding_section, SETTINGS_ROLE_KEY, _selected_role())
	return config.save(SETTINGS_PATH)


func _first_diagnostic(result: GDSQLOperationResult, fallback: String) -> String:
	if result != null and not result.diagnostics.entries.is_empty():
		return result.diagnostics.entries[0].message
	return fallback


func _has_diagnostic(
		report: GDSQLModelCompatibilityReport,
		code: StringName,
) -> bool:
	for diagnostic in report.diagnostics.entries:
		if diagnostic.code == code:
			return true
	return false


func _report_script_error(
		report: GDSQLModelCompatibilityReport,
		is_script_error: bool,
) -> void:
	if not is_script_error:
		_last_reported_script_error = ""
		return
	var messages: Array[String] = []
	for diagnostic in report.diagnostics.entries:
		if diagnostic.severity == GDSQLQueryDiagnostic.Severity.ERROR:
			messages.append("[%s] %s" % [diagnostic.code, diagnostic.message])
	var error_text := "%s: %s" % [_source.user_path, " ".join(messages)]
	if error_text == _last_reported_script_error:
		return
	_last_reported_script_error = error_text
	push_error("[GDSQL] Model compatibility script error · %s" % error_text)
