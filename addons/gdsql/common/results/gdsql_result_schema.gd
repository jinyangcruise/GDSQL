class_name GDSQLResultSchema
extends RefCounted

var columns: Array[GDSQLColumnDefinition] = []


func get_columns() -> Array[GDSQLColumnDefinition]:
	return columns.duplicate()


func get_column(column_name: StringName) -> GDSQLColumnDefinition:
	for column in columns:
		if column.name == column_name:
			return column
	return null
