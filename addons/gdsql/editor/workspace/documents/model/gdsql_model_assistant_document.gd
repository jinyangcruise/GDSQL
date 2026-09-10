@tool
extends MarginContainer
## Previews and safely writes a generated schema base plus a user-owned model.

signal close_requested
signal scripts_generated(generated_path: String, user_path: String)

const SETTINGS_PATH := "res://.gdsql/settings.cfg"
const SETTINGS_SECTION := "models"
const SETTINGS_ROOT_KEY := "root"

var _table: GDSQLTableDefinition
var _source: GDSQLModelSource
var _generator := GDSQLModelSourceGenerator.new()
var _compatibility_inspector := GDSQLModelCompatibilityInspector.new()

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
	_custom_role.text_changed.connect(_on_text_changed)
	_role.item_selected.connect(_on_role_selected)
	%Generate.pressed.connect(_request_generation)
	%Close.pressed.connect(close_requested.emit)
	%OverwriteConfirmation.confirmed.connect(_write_sources)


func configure(
		_registration_name: StringName,
		table: GDSQLTableDefinition,
		database_role: StringName = GDSQLDatabaseRegistry.CONTENT_ROLE,
) -> void:
	_table = table
	%Title.text = "Model binding · %s" % table.name
	%TableValue.text = _table_identity(table)
	_model_class.text = _suggest_class_name(String(table.name))
	_model_root.text = _load_model_root()
	_select_role(database_role)
	_refresh_preview()


func refresh_table(table: GDSQLTableDefinition) -> void:
	if table == null:
		return
	_table = table
	%Title.text = "Model binding · %s" % table.name
	%TableValue.text = _table_identity(table)
	_refresh_preview()


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
	_refresh_preview()


func _on_text_changed(_value: String) -> void:
	_refresh_preview()


func _selected_role() -> StringName:
	if _role.selected == 3:
		return StringName(_custom_role.text.strip_edges())
	return StringName(_role.get_item_metadata(_role.selected))


func _refresh_preview() -> void:
	if _table == null or not is_node_ready():
		return
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
	)
	%CompatibilityStatus.text = "COMPATIBLE" if report.is_compatible() else "NEEDS UPDATE"
	%CompatibilityStatus.modulate = (
			Color(0.42, 0.82, 0.55) if report.is_compatible() else Color(1.0, 0.55, 0.42)
	)
	var lines: Array[String] = []
	for diagnostic in report.diagnostics.entries:
		lines.append("• %s" % diagnostic.message)
	if report.relationship_summaries.is_empty():
		lines.append("No relationships declared.")
	else:
		lines.append("Relationships resolve through their target model roles:")
		for summary in report.relationship_summaries:
			lines.append("• %s" % summary)
	%CompatibilityDetails.text = "\n".join(lines)


func _set_compatibility_unavailable(message: String) -> void:
	%CompatibilityStatus.text = "NOT INSPECTED"
	%CompatibilityStatus.modulate = Color(0.62, 0.67, 0.74)
	%CompatibilityDetails.text = message


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
	var settings_error := _save_model_root(_model_root.text)
	EditorInterface.get_resource_filesystem().scan()
	var message := (
			"Generated the schema base and created the user model."
			if user_created
			else "Regenerated the schema base. The user model was preserved."
	)
	if settings_error != OK:
		message += " The models-folder setting could not be saved (error %d)." \
				% settings_error
	%Status.text = message
	scripts_generated.emit(_source.generated_path, _source.user_path)
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


func _save_model_root(root: String) -> Error:
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(SETTINGS_PATH.get_base_dir()),
	)
	if directory_error != OK:
		return directory_error
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value(SETTINGS_SECTION, SETTINGS_ROOT_KEY, root.strip_edges())
	return config.save(SETTINGS_PATH)


func _first_diagnostic(result: GDSQLOperationResult, fallback: String) -> String:
	if result != null and not result.diagnostics.entries.is_empty():
		return result.diagnostics.entries[0].message
	return fallback
