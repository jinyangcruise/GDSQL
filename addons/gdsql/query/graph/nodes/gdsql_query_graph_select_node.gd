class_name GDSQLQueryGraphSelectNode
extends RefCounted
## Frontend-owned description of one SELECT source in a query graph.

var database_name: StringName
var table_name: StringName
var projections: Array[StringName] = []
var predicate: GDSQLQueryExpression
var include_all_columns := true


func _init(
		database: StringName = &"",
		table: StringName = &"",
) -> void:
	database_name = database
	table_name = table
