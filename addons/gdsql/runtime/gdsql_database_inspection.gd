class_name GDSQLDatabaseInspection
extends RefCounted
## Lightweight description of one discovered logical database.

var registration: GDSQLDatabaseRegistration
var catalog_exists: bool
var tables: Array[GDSQLTableInspection] = []


func _init(
		database_registration: GDSQLDatabaseRegistration = null,
		has_catalog: bool = false,
) -> void:
	registration = database_registration
	catalog_exists = has_catalog


func get_table(table_name: StringName) -> GDSQLTableInspection:
	for table in tables:
		if table.name == table_name:
			return table
	return null
