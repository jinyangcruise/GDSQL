class_name GDSQLQueryFunctionDefinition
extends RefCounted

var name: StringName
var minimum_arguments: int
var maximum_arguments: int
var return_type: Variant.Type
var aggregate: bool


func _init(
		_name: StringName = &"",
		_minimum_arguments: int = 0,
		_maximum_arguments: int = -1,
		_return_type: Variant.Type = TYPE_NIL,
		_aggregate: bool = false,
) -> void:
	name = _name
	minimum_arguments = _minimum_arguments
	maximum_arguments = _maximum_arguments
	return_type = _return_type
	aggregate = _aggregate


func accepts_argument_count(count: int) -> bool:
	return count >= minimum_arguments and (maximum_arguments < 0 or count <= maximum_arguments)
