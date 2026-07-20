class_name GDSQLDatabaseRegistration
extends RefCounted
## Describes one durable database registration shared by runtime and editor code.

var name: StringName
var database_name: StringName
var data_root: String
var storage_backend_id: StringName


func _init(
		registration_name: StringName = &"",
		logical_database_name: StringName = &"",
		root: String = "",
		backend_id: StringName = GDSQLStorageBackendIds.CONFIG_FILE,
) -> void:
	name = registration_name
	database_name = logical_database_name
	data_root = root
	storage_backend_id = backend_id
