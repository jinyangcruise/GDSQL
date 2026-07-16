class_name GDSQLCatalogSnapshot
extends RefCounted

var databases: Array[GDSQLDatabaseDefinition] = []


func get_database(database_name: StringName) -> GDSQLDatabaseDefinition:
	for database in databases:
		if database.name == database_name:
			return database
	return null


func get_table(database_name: StringName, table_name: StringName) -> GDSQLTableDefinition:
	var database := get_database(database_name)
	return database.get_table(table_name) if database != null else null
