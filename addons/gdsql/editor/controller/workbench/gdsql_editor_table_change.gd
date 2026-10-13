class_name GDSQLEditorTableChange
extends RefCounted
## Typed editor intent for one table alteration, creation, rename, or drop.

var table_name: StringName
var alterations: Array[GDSQLTableAlteration] = []
var table_definition: GDSQLTableDefinition
var new_table_name: StringName
var drop_requested: bool


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


static func rename_table(
		current_name: StringName,
		new_name: StringName,
) -> GDSQLEditorTableChange:
	var change := GDSQLEditorTableChange.new()
	change.table_name = current_name
	change.new_table_name = new_name
	return change


static func drop_table(table_to_drop: StringName) -> GDSQLEditorTableChange:
	var change := GDSQLEditorTableChange.new()
	change.table_name = table_to_drop
	change.drop_requested = true
	return change


func is_valid() -> bool:
	if table_definition != null:
		return alterations.is_empty() \
				and new_table_name == &"" \
				and not drop_requested \
				and table_definition.name == table_name
	if drop_requested:
		return table_name != &"" \
				and new_table_name == &"" \
				and alterations.is_empty()
	if new_table_name != &"":
		return table_name != &"" \
				and new_table_name != table_name \
				and String(new_table_name).is_valid_identifier() \
				and alterations.is_empty()
	return table_name != &"" and not alterations.is_empty()


func is_create_table() -> bool:
	return table_definition != null


func is_rename_table() -> bool:
	return new_table_name != &""


func is_drop_table() -> bool:
	return drop_requested


func to_migration_step() -> GDSQLSchemaMigrationStep:
	if table_definition != null:
		return GDSQLSchemaMigrationStep.create_table(table_definition)
	if drop_requested:
		return GDSQLSchemaMigrationStep.drop_table(table_name)
	if new_table_name != &"":
		return GDSQLSchemaMigrationStep.rename_table(table_name, new_table_name)
	return GDSQLSchemaMigrationStep.new(table_name, alterations)
