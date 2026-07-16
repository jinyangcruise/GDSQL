class_name GDSQLCatalogService
extends RefCounted

func get_database(database_name: StringName) -> GDSQLDatabaseDefinition:
	return null


func get_table(database_name: StringName, table_name: StringName) -> GDSQLTableDefinition:
	return null


func has_table(database_name: StringName, table_name: StringName) -> bool:
	return false


func create_snapshot() -> GDSQLCatalogSnapshot:
	return null
