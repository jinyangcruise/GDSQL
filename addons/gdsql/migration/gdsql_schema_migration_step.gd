class_name GDSQLSchemaMigrationStep
extends RefCounted
## One ordered table lifecycle operation inside a forward schema migration.

enum Kind {
	ALTER_TABLE,
	CREATE_TABLE,
	RENAME_TABLE,
	DROP_TABLE,
}

var kind := Kind.ALTER_TABLE
var table_name: StringName
var alterations: Array[GDSQLTableAlteration] = []
var table_definition: GDSQLTableDefinition
var new_table_name: StringName


func _init(
		target_table: StringName = &"",
		requested_alterations: Array[GDSQLTableAlteration] = [],
) -> void:
	table_name = target_table
	alterations = requested_alterations.duplicate()


static func create_table(table: GDSQLTableDefinition) -> GDSQLSchemaMigrationStep:
	var step := GDSQLSchemaMigrationStep.new()
	step.kind = Kind.CREATE_TABLE
	step.table_definition = table
	step.table_name = table.name if table != null else &""
	return step


static func rename_table(
		current_name: StringName,
		new_name: StringName,
) -> GDSQLSchemaMigrationStep:
	var step := GDSQLSchemaMigrationStep.new()
	step.kind = Kind.RENAME_TABLE
	step.table_name = current_name
	step.new_table_name = new_name
	return step


static func drop_table(table_to_drop: StringName) -> GDSQLSchemaMigrationStep:
	var step := GDSQLSchemaMigrationStep.new()
	step.kind = Kind.DROP_TABLE
	step.table_name = table_to_drop
	return step


func is_valid() -> bool:
	if table_name == &"" or not String(table_name).is_valid_identifier():
		return false
	match kind:
		Kind.ALTER_TABLE:
			if alterations.is_empty() \
					or table_definition != null \
					or new_table_name != &"":
				return false
			for alteration in alterations:
				if alteration == null or not alteration.is_valid():
					return false
		Kind.CREATE_TABLE:
			if table_definition == null \
					or table_definition.name != table_name \
					or table_definition.primary_key == &"" \
					or table_definition.columns.is_empty() \
					or new_table_name != &"" \
					or not alterations.is_empty():
				return false
		Kind.RENAME_TABLE:
			if new_table_name == &"" \
					or not String(new_table_name).is_valid_identifier() \
					or new_table_name == table_name \
					or table_definition != null \
					or not alterations.is_empty():
				return false
		Kind.DROP_TABLE:
			if new_table_name != &"" \
					or table_definition != null \
					or not alterations.is_empty():
				return false
		_:
			return false
	return true


func is_destructive() -> bool:
	if kind == Kind.DROP_TABLE:
		return true
	if kind != Kind.ALTER_TABLE:
		return false
	for alteration in alterations:
		if alteration != null and alteration.is_destructive():
			return true
	return false
