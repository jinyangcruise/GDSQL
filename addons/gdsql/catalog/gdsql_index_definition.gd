class_name GDSQLIndexDefinition
extends RefCounted

var name: StringName
var columns: Array[StringName] = []
var unique: bool = false


func _init(
		_name: StringName = &"",
		_columns: Array[StringName] = [],
		_unique: bool = false,
) -> void:
	name = _name
	columns = _columns.duplicate()
	unique = _unique


func get_columns() -> Array[StringName]:
	return columns.duplicate()


func is_unique() -> bool:
	return unique
