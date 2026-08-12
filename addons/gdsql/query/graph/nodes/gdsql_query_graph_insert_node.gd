class_name GDSQLQueryGraphInsertNode
extends RefCounted
## Frontend-owned description of one single-row INSERT operation.

var database_name: StringName
var table_name: StringName
var columns: Array[StringName] = []
var values: Array[Variant] = []


func _init(
		database: StringName = &"",
		table: StringName = &"",
) -> void:
	database_name = database
	table_name = table
