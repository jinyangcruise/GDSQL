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


func resolve_migration_ledger_path(database: StringName) -> String:
	return resolve_database_path(database).path_join("migrations.cfg")


func resolve_migration_recovery_root(database: StringName) -> String:
	return data_root.path_join(".gdsql_migration_recovery").path_join(String(database))


func resolve_catalog_transaction_root(database: StringName = &"") -> String:
	var root := data_root.path_join(".gdsql_catalog_transactions")
	return root if database == &"" else root.path_join(String(database))


func resolve_table_data_transaction_root(database: StringName) -> String:
	assert(is_valid_name(database), "Invalid database name: %s" % database)
	return data_root.path_join(".gdsql_storage_transactions").path_join(String(database))


func resolve_migration_backup_path(
		database: StringName,
		migration_id: String,
) -> String:
	assert(
		not migration_id.is_empty() and migration_id.get_file() == migration_id \
				and migration_id not in [".", ".."],
		"Invalid migration backup identifier: %s" % migration_id,
	)
	return resolve_migration_recovery_root(database).path_join(migration_id)


func is_valid_name(value: StringName) -> bool:
	return value != &"" and String(value).is_valid_identifier()
