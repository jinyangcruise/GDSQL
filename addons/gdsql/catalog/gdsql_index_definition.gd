class_name GDSQLIndexDefinition
extends RefCounted

var name: StringName
var columns: Array[StringName] = []
var unique: bool = false


func _init(
		name: StringName = &"",
		columns: Array[StringName] = [],
		unique: bool = false,
) -> void:
	self.name = name
	self.columns = columns.duplicate()
	self.unique = unique


func get_columns() -> Array[StringName]:
	return columns.duplicate()


func is_unique() -> bool:
	return unique
