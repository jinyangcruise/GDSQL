class_name GDSQLTableDefinition
extends RefCounted

var database_name: StringName
var name: StringName
var columns: Array[GDSQLColumnDefinition] = []
var primary_key: StringName
var indexes: Array[GDSQLIndexDefinition] = []


func _init(
		name: StringName = &"",
		primary_key: StringName = &"",
) -> void:
	self.name = name
	self.primary_key = primary_key


func add_column(column: GDSQLColumnDefinition) -> GDSQLTableDefinition:
	columns.append(column)
	return self


func add_timestamps(
		created_at_name: StringName = &"created_at",
		updated_at_name: StringName = &"updated_at",
) -> GDSQLTableDefinition:
	add_column(GDSQLColumnDefinition.created_at(created_at_name))
	add_column(GDSQLColumnDefinition.updated_at(updated_at_name))
	return self


func get_column(column_name: StringName) -> GDSQLColumnDefinition:
	for column in columns:
		if column.name == column_name:
			return column
	return null


func has_column(column_name: StringName) -> bool:
	return get_column(column_name) != null


func get_primary_key() -> GDSQLColumnDefinition:
	return get_column(primary_key)
