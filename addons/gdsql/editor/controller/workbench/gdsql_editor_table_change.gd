class_name GDSQLEditorTableChange
extends RefCounted
## Typed editor intent for one existing-table alteration or new table.

var table_name: StringName
var alterations: Array[GDSQLTableAlteration] = []
var table_definition: GDSQLTableDefinition


func _init(
		target_table: StringName = &"",
		requested_alterations: Array[GDSQLTableAlteration] = [],
) -> void:
	table_name = target_table
	alterations = requested_alterations.duplicate()


static func create_table(table: GDSQLTableDefinition) -> GDSQLEditorTableChange:
	var change := GDSQLEditorTableChange.new()
	change.table_definition = table
	change.table_name = table.name if table != null else &""
	return change


func is_valid() -> bool:
	if table_definition != null:
		return alterations.is_empty() and table_definition.name == table_name
	return table_name != &"" and not alterations.is_empty()


func is_create_table() -> bool:
	return table_definition != null


func to_migration_step() -> GDSQLSchemaMigrationStep:
	if table_definition != null:
		return GDSQLSchemaMigrationStep.create_table(table_definition)
	return GDSQLSchemaMigrationStep.new(table_name, alterations)
