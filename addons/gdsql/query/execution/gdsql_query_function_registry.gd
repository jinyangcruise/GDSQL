class_name GDSQLQueryFunctionRegistry
extends RefCounted

const FunctionCatalog = preload("res://addons/gdsql/query/model/gdsql_query_function_catalog.gd")
const FunctionDefinition = preload("res://addons/gdsql/query/model/gdsql_query_function_definition.gd")

var catalog: FunctionCatalog
var _functions: Dictionary = { }
var _aggregate_functions: Dictionary = { }


func _init(catalog: FunctionCatalog = null) -> void:
	self.catalog = catalog if catalog != null else FunctionCatalog.new()
	register_function(&"lower", _lower, 1, 1, TYPE_STRING)
	register_function(&"upper", _upper, 1, 1, TYPE_STRING)
	register_function(&"length", _length, 1, 1, TYPE_INT)
	register_function(&"abs", _absolute, 1, 1, TYPE_NIL)
	register_function(&"coalesce", _coalesce, 1, -1, TYPE_NIL)
	register_aggregate_function(&"count", _count, 0, 1, TYPE_INT)
	register_aggregate_function(&"sum", _sum, 1, 1, TYPE_FLOAT)
	register_aggregate_function(&"avg", _average, 1, 1, TYPE_FLOAT)
	register_aggregate_function(&"min", _minimum, 1, 1, TYPE_NIL)
	register_aggregate_function(&"max", _maximum, 1, 1, TYPE_NIL)


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


func register_aggregate_function(
		name: StringName,
		function: Callable,
		minimum_arguments: int,
		maximum_arguments: int,
		return_type: Variant.Type = TYPE_NIL,
) -> void:
	var normalized := _normalize(name)
	_aggregate_functions[normalized] = function
	catalog.register_function(
		FunctionDefinition.new(
			normalized,
			minimum_arguments,
			maximum_arguments,
			return_type,
			true,
		),
	)


func resolve_aggregate(name: StringName) -> Callable:
	return _aggregate_functions.get(_normalize(name), Callable())


func contains(name: StringName) -> bool:
	var normalized := _normalize(name)
	return _functions.has(normalized) or _aggregate_functions.has(normalized)


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


func _count(values: Array, row_count: int) -> int:
	if values.is_empty():
		return row_count
	var count := 0
	for value in values:
		if value != null:
			count += 1
	return count


func _sum(values: Array, _row_count: int) -> Variant:
	var total: Variant = 0
	var has_value := false
	for value in values:
		if value == null:
			continue
		total += value
		has_value = true
	return total if has_value else null


func _average(values: Array, _row_count: int) -> Variant:
	var total: Variant = 0
	var count := 0
	for value in values:
		if value == null:
			continue
		total += value
		count += 1
	return null if count == 0 else float(total) / float(count)


func _minimum(values: Array, _row_count: int) -> Variant:
	return _extreme(values, true)


func _maximum(values: Array, _row_count: int) -> Variant:
	return _extreme(values, false)


func _extreme(values: Array, minimum: bool) -> Variant:
	var selected: Variant = null
	var has_value := false
	for value in values:
		if value == null:
			continue
		if not has_value:
			selected = value
			has_value = true
		elif (minimum and value < selected) or (not minimum and value > selected):
			selected = value
	return selected
