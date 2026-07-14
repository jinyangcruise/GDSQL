class_name GDSQLTableAlteration
extends RefCounted

enum Kind {
	ADD_COLUMN,
	RENAME_COLUMN,
	DROP_COLUMN,
}

var kind: Kind
var column: GDSQLColumnDefinition
var column_name: StringName
var new_column_name: StringName


static func add_column(column_definition: GDSQLColumnDefinition) -> GDSQLTableAlteration:
	var alteration := GDSQLTableAlteration.new()
	alteration.kind = Kind.ADD_COLUMN
	alteration.column = column_definition
	return alteration


static func rename_column(
		current_name: StringName,
		new_name: StringName,
) -> GDSQLTableAlteration:
	var alteration := GDSQLTableAlteration.new()
	alteration.kind = Kind.RENAME_COLUMN
	alteration.column_name = current_name
	alteration.new_column_name = new_name
	return alteration


static func drop_column(column_to_drop: StringName) -> GDSQLTableAlteration:
	var alteration := GDSQLTableAlteration.new()
	alteration.kind = Kind.DROP_COLUMN
	alteration.column_name = column_to_drop
	return alteration
