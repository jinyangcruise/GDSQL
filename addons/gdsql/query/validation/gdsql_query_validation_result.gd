class_name GDSQLQueryValidationResult
extends GDSQLOperationResult

var bound_query: GDSQLBoundQuery


func is_valid() -> bool:
	return is_successful() and bound_query != null


func get_bound_query() -> GDSQLBoundQuery:
	return bound_query
