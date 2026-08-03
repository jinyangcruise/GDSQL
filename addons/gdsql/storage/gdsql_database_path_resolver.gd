class_name GDSQLDatabasePathResolver
extends RefCounted

var data_root: String


func _init(_data_root: String = "res://data") -> void:
	data_root = _data_root.trim_suffix("/")


func resolve_catalog_path(database: StringName = &"") -> String:
	if database == &"":
		return data_root.path_join("databases.cfg")
	return resolve_database_path(database).path_join("schema")


func resolve_database_path(database: StringName) -> String:
	assert(is_valid_name(database), "Invalid database name: %s" % database)
	return data_root.path_join(String(database))


func resolve_schema_path(database: StringName, table: StringName) -> String:
	assert(is_valid_name(table), "Invalid table name: %s" % table)
	return resolve_database_path(database).path_join("schema").path_join(String(table) + ".cfg")


func resolve_table_path(database: StringName = &"", table: StringName = &"") -> String:
	assert(is_valid_name(table), "Invalid table name: %s" % table)
	return resolve_database_path(database).path_join("tables").path_join(String(table) + ".cfg")


func is_valid_name(value: StringName) -> bool:
	return value != &"" and String(value).is_valid_identifier()
