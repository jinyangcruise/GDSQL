class_name GDSQLQueryFunctionCatalog
extends RefCounted

const FunctionDefinition = preload("res://addons/gdsql/query/model/gdsql_query_function_definition.gd")

var _definitions: Dictionary = { }


func register_function(definition: FunctionDefinition) -> void:
	_definitions[_normalize(definition.name)] = definition


func resolve(name: StringName) -> FunctionDefinition:
	return _definitions.get(_normalize(name))


func contains(name: StringName) -> bool:
	return _definitions.has(_normalize(name))


func _normalize(name: StringName) -> StringName:
	return StringName(String(name).to_lower())
