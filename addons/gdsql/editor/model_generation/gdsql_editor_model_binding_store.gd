@tool
class_name GDSQLEditorModelBindingStore
extends RefCounted
## Persists generated-model bindings in project-owned editor settings.

const DEFAULT_PATH := "res://.gdsql/settings.cfg"
const DEFAULT_ROOT := "res://models"
const MODELS_SECTION := "models"
const ROOT_KEY := "root"
const SECTION_PREFIX := "model_binding:"
const CLASS_KEY := "class_name"
const ROLE_KEY := "role"

var _settings_path: String


func _init(settings_path: String = DEFAULT_PATH) -> void:
	_settings_path = settings_path


func save(
		registration_name: StringName,
		database_name: StringName,
		table_name: StringName,
		model_class: StringName,
		role: StringName,
		model_root: String,
) -> Error:
	if registration_name == &"" or database_name == &"" or table_name == &"" \
			or model_class == &"" or role == &"":
		return ERR_INVALID_DATA
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(_settings_path.get_base_dir()),
	)
	if directory_error != OK:
		return directory_error
	var config := ConfigFile.new()
	config.load(_settings_path)
	config.set_value(MODELS_SECTION, ROOT_KEY, model_root)
	var section := _section(registration_name, database_name, table_name)
	config.set_value(section, CLASS_KEY, model_class)
	config.set_value(section, ROLE_KEY, role)
	return config.save(_settings_path)


func load_all() -> Array[Dictionary]:
	var bindings: Array[Dictionary] = []
	var config := ConfigFile.new()
	if config.load(_settings_path) != OK:
		return bindings
	var model_root := String(config.get_value(MODELS_SECTION, ROOT_KEY, DEFAULT_ROOT))
	for section in config.get_sections():
		if not section.begins_with(SECTION_PREFIX):
			continue
		var identity := section.trim_prefix(SECTION_PREFIX).split(":", false, 2)
		if identity.size() != 3:
			continue
		var class_name_value := String(config.get_value(section, CLASS_KEY, ""))
		if class_name_value.is_empty():
			continue
		bindings.append(
			{
				"registration": identity[0],
				"database": identity[1],
				"table": identity[2],
				"class_name": class_name_value,
				"role": String(config.get_value(section, ROLE_KEY, "")),
				"model_root": model_root,
			},
		)
	return bindings


func load_root() -> String:
	var config := ConfigFile.new()
	if config.load(_settings_path) != OK:
		return DEFAULT_ROOT
	return String(config.get_value(MODELS_SECTION, ROOT_KEY, DEFAULT_ROOT))


func load_for_table(
		registration_name: StringName,
		database_name: StringName,
		table_name: StringName,
) -> Dictionary:
	for binding in load_all():
		if StringName(binding["registration"]) == registration_name \
				and StringName(binding["database"]) == database_name \
				and StringName(binding["table"]) == table_name:
			return binding
	return { }


func _section(
		registration_name: StringName,
		database_name: StringName,
		table_name: StringName,
) -> String:
	return "%s%s:%s:%s" % [
		SECTION_PREFIX,
		registration_name,
		database_name,
		table_name,
	]
