class_name GDSQLQueryFunctionRegistry
extends RefCounted

const FunctionCatalog = preload("res://addons/gdsql/query/model/gdsql_query_function_catalog.gd")
const FunctionDefinition = preload("res://addons/gdsql/query/model/gdsql_query_function_definition.gd")

var catalog: FunctionCatalog
var _functions: Dictionary = { }


func _init(catalog: FunctionCatalog = null) -> void:
	self.catalog = catalog if catalog != null else FunctionCatalog.new()
	register_function(&"lower", _lower, 1, 1, TYPE_STRING)
	register_function(&"upper", _upper, 1, 1, TYPE_STRING)
	register_function(&"length", _length, 1, 1, TYPE_INT)
	register_function(&"abs", _absolute, 1, 1, TYPE_NIL)
	register_function(&"coalesce", _coalesce, 1, -1, TYPE_NIL)


func register_function(
		name: StringName,
		function: Callable,
		minimum_arguments: int = 0,
		maximum_arguments: int = -1,
		return_type: Variant.Type = TYPE_NIL,
		aggregate: bool = false,
) -> void:
	var normalized := _normalize(name)
	_functions[normalized] = function
	catalog.register_function(
		FunctionDefinition.new(
			normalized,
			minimum_arguments,
			maximum_arguments,
			return_type,
			aggregate,
		),
	)


func resolve(name: StringName) -> Callable:
	return _functions.get(_normalize(name), Callable())


func contains(name: StringName) -> bool:
	return _functions.has(_normalize(name))


func _normalize(name: StringName) -> StringName:
	return StringName(String(name).to_lower())


func _lower(arguments: Array) -> Variant:
	var value: Variant = arguments[0]
	return null if value == null else String(value).to_lower()


func _upper(arguments: Array) -> Variant:
	var value: Variant = arguments[0]
	return null if value == null else String(value).to_upper()


func _length(arguments: Array) -> Variant:
	var value: Variant = arguments[0]
	return null if value == null else String(value).length()


func _absolute(arguments: Array) -> Variant:
	var value: Variant = arguments[0]
	return null if value == null else abs(value)


func _coalesce(arguments: Array) -> Variant:
	for value in arguments:
		if value != null:
			return value
	return null
