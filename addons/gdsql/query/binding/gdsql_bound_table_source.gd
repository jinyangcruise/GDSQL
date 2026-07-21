class_name GDSQLBoundTableSource
extends RefCounted

var table: GDSQLTableDefinition
var alias: StringName
var nullable: bool = false


func _init(
		table: GDSQLTableDefinition = null,
		alias: StringName = &"",
		nullable: bool = false,
) -> void:
	self.table = table
	self.alias = alias
	self.nullable = nullable


func get_qualifier() -> StringName:
	if alias != &"":
		return alias
	return table.name if table != null else &""
