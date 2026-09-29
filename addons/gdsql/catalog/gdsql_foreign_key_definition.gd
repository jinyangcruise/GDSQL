class_name GDSQLForeignKeyDefinition
extends RefCounted
## Describes one same-database, single-column foreign-key constraint.
##
## Runtime-role references remain a separate model/runtime concept because they
## can resolve to different physical databases and cannot share one transaction.

enum Action {
	RESTRICT,
}

const SUPPORTED_COLUMN_TYPES: Array[Variant.Type] = [
	TYPE_INT,
	TYPE_STRING,
	TYPE_STRING_NAME,
]

var name: StringName
var column: StringName
var referenced_table: StringName
var referenced_column: StringName
var on_delete: Action
var on_update: Action


static func supports_column_type(data_type: Variant.Type) -> bool:
	return SUPPORTED_COLUMN_TYPES.has(data_type)


func _init(
		constraint_name: StringName = &"",
		local_column: StringName = &"",
		target_table: StringName = &"",
		target_column: StringName = &"",
		delete_action: Action = Action.RESTRICT,
		update_action: Action = Action.RESTRICT,
) -> void:
	name = constraint_name
	column = local_column
	referenced_table = target_table
	referenced_column = target_column
	on_delete = delete_action
	on_update = update_action


func references_local_column(column_name: StringName) -> bool:
	return column == column_name


func references_target(table_name: StringName, column_name: StringName) -> bool:
	return referenced_table == table_name and referenced_column == column_name


func is_equivalent_to(other: GDSQLForeignKeyDefinition) -> bool:
	return other != null \
			and name == other.name \
			and column == other.column \
			and referenced_table == other.referenced_table \
			and referenced_column == other.referenced_column \
			and on_delete == other.on_delete \
			and on_update == other.on_update
