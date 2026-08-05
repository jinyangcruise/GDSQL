class_name GDSQLBoundTableSource
extends RefCounted

var table: GDSQLTableDefinition
var alias: StringName
var nullable: bool = false


func _init(
		_table: GDSQLTableDefinition = null,
		_alias: StringName = &"",
		_nullable: bool = false,
) -> void:
	table = _table
	alias = _alias
	nullable = _nullable


func get_qualifier() -> StringName:
	if alias != &"":
		return alias
	return table.name if table != null else &""
