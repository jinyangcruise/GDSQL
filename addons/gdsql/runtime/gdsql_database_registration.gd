class_name GDSQLDatabaseRegistration
extends RefCounted
## Describes one durable database registration shared by runtime and editor code.

var name: StringName
var database_name: StringName
var data_root: String
var storage_backend_id: StringName
var migration_stream: StringName


func _init(
		registration_name: StringName = &"",
		logical_database_name: StringName = &"",
		root: String = "",
		backend_id: StringName = GDSQLStorageBackendIds.CONFIG_FILE,
		schema_migration_stream: StringName = &"",
) -> void:
	name = registration_name
	database_name = logical_database_name
	data_root = root
	storage_backend_id = backend_id
	migration_stream = (
		schema_migration_stream
		if schema_migration_stream != &""
		else logical_database_name
	)
