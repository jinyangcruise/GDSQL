class_name GDSQLQueryFunctionDefinition
extends RefCounted

var name: StringName
var minimum_arguments: int
var maximum_arguments: int
var return_type: Variant.Type
var aggregate: bool


func _init(
		name: StringName = &"",
		minimum_arguments: int = 0,
		maximum_arguments: int = -1,
		return_type: Variant.Type = TYPE_NIL,
		aggregate: bool = false,
) -> void:
	self.name = name
	self.minimum_arguments = minimum_arguments
	self.maximum_arguments = maximum_arguments
	self.return_type = return_type
	self.aggregate = aggregate


func accepts_argument_count(count: int) -> bool:
	return count >= minimum_arguments and (maximum_arguments < 0 or count <= maximum_arguments)
