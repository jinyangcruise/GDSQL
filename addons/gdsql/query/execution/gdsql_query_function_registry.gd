class_name GDSQLQueryFunctionRegistry
extends RefCounted

func register_function(name: StringName, function: Callable) -> void:
	pass


func resolve(name: StringName) -> Callable:
	return Callable()
