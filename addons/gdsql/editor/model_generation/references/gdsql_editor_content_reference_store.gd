@tool
class_name GDSQLEditorContentReferenceStore
extends RefCounted
## Persists editor-only cross-role picker metadata in project tool settings.

const DEFAULT_PATH := "res://.gdsql/settings.cfg"
const SECTION_PREFIX := "content_reference:"
const RELATIONSHIP_KEY := "relationship_name"
const TARGET_REGISTRATION_KEY := "target_registration"
const TARGET_DATABASE_KEY := "target_database"
const TARGET_TABLE_KEY := "target_table"
const TARGET_COLUMN_KEY := "target_column"
const TARGET_MODEL_CLASS_KEY := "target_model_class"

var _settings_path: String


func _init(settings_path: String = DEFAULT_PATH) -> void:
	_settings_path = settings_path


func save(reference: GDSQLEditorContentReference) -> Error:
	if reference == null or not reference.is_valid():
		return ERR_INVALID_DATA
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(_settings_path.get_base_dir()),
	)
	if directory_error != OK:
		return directory_error
	var config := ConfigFile.new()
	config.load(_settings_path)
	var section := _section_for(reference)
	config.set_value(section, RELATIONSHIP_KEY, reference.relationship_name)
	config.set_value(section, TARGET_REGISTRATION_KEY, reference.target_registration_name)
	config.set_value(section, TARGET_DATABASE_KEY, reference.target_database_name)
	config.set_value(section, TARGET_TABLE_KEY, reference.target_table_name)
	config.set_value(section, TARGET_COLUMN_KEY, reference.target_column_name)
	config.set_value(section, TARGET_MODEL_CLASS_KEY, reference.target_model_class)
	return config.save(_settings_path)


func remove(reference: GDSQLEditorContentReference) -> Error:
	if reference == null or not reference.is_valid():
		return ERR_INVALID_DATA
	var config := ConfigFile.new()
	var load_error := config.load(_settings_path)
	if load_error != OK:
		return load_error
	var section := _section_for(reference)
	if not config.has_section(section):
		return ERR_DOES_NOT_EXIST
	config.erase_section(section)
	return config.save(_settings_path)


func load_for_table(
		source_registration: StringName,
		source_database: StringName,
		source_table: StringName,
) -> Array[GDSQLEditorContentReference]:
	var references: Array[GDSQLEditorContentReference] = []
	var config := ConfigFile.new()
	if config.load(_settings_path) != OK:
		return references
	var prefix := "%s%s:%s:%s:" % [
		SECTION_PREFIX,
		source_registration,
		source_database,
		source_table,
	]
	for section in config.get_sections():
		if not section.begins_with(prefix):
			continue
		var source_column := StringName(section.trim_prefix(prefix))
		var reference := GDSQLEditorContentReference.new(
			StringName(config.get_value(section, RELATIONSHIP_KEY, "")),
			source_registration,
			source_database,
			source_table,
			source_column,
			StringName(config.get_value(section, TARGET_REGISTRATION_KEY, "")),
			StringName(config.get_value(section, TARGET_DATABASE_KEY, "")),
			StringName(config.get_value(section, TARGET_TABLE_KEY, "")),
			StringName(config.get_value(section, TARGET_COLUMN_KEY, "")),
			StringName(config.get_value(section, TARGET_MODEL_CLASS_KEY, "")),
		)
		if reference.is_valid():
			references.append(reference)
	return references


func _section_for(reference: GDSQLEditorContentReference) -> String:
	return "%s%s:%s:%s:%s" % [
		SECTION_PREFIX,
		reference.source_registration_name,
		reference.source_database_name,
		reference.source_table_name,
		reference.source_column_name,
	]
