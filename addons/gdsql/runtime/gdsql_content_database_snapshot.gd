class_name GDSQLContentDatabaseSnapshot
extends RefCounted
## Immutable-by-convention output of deterministic content composition.

var definition: GDSQLDatabaseDefinition
var tables: Array[GDSQLTableSnapshot] = []


func _init(database_definition: GDSQLDatabaseDefinition = null) -> void:
	definition = database_definition


func get_table_definition(table_name: StringName) -> GDSQLTableDefinition:
	return definition.get_table(table_name) if definition != null else null


func get_table(table_name: StringName) -> GDSQLTableSnapshot:
	if definition == null:
		return null
	for index in definition.tables.size():
		if definition.tables[index].name == table_name:
			return tables[index]
	return null
