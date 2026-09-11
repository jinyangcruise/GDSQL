class_name GDSQLQueryGraphUpdateNode
extends RefCounted
## Frontend-owned description of one UPDATE operation.

var database_name: StringName
var table_name: StringName
var assignments: Array[GDSQLColumnAssignment] = []
var predicate: GDSQLQueryExpression


func _init(
		database: StringName = &"",
		table: StringName = &"",
) -> void:
	database_name = database
	table_name = table
