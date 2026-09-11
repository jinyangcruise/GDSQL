class_name GDSQLContentPackageLayer
extends RefCounted
## Typed database content decoded from one immutable package source.

var source: GDSQLContentPackageSource
var database_name: StringName
var table_definitions: Array[GDSQLTableDefinition] = []
var operations: Array[GDSQLContentRowOperation] = []


func _init(
		package_source: GDSQLContentPackageSource = null,
		logical_database_name: StringName = &"",
) -> void:
	source = package_source
	database_name = logical_database_name


func get_table(table_name: StringName) -> GDSQLTableDefinition:
	for table in table_definitions:
		if table.name == table_name:
			return table
	return null


func add_upsert(
		table_name: StringName,
		identity: Variant,
		row: GDSQLRowRecord,
) -> void:
	operations.append(GDSQLContentRowOperation.upsert(table_name, identity, row))


func add_removal(table_name: StringName, identity: Variant) -> void:
	operations.append(GDSQLContentRowOperation.remove(table_name, identity))
