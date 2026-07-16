class_name GDSQLDatabaseDefinition
extends RefCounted

var name: StringName
var tables: Array[GDSQLTableDefinition] = []


func get_table(table_name: StringName) -> GDSQLTableDefinition:
	for table in tables:
		if table.name == table_name:
			return table
	return null
