class_name GDSQLTableDefinition
extends RefCounted

var database_name: StringName
var name: StringName
var columns: Array[GDSQLColumnDefinition] = []
var primary_key: StringName
var indexes: Array[GDSQLIndexDefinition] = []
var foreign_keys: Array[GDSQLForeignKeyDefinition] = []


func _init(
		_name: StringName = &"",
		_primary_key: StringName = &"",
) -> void:
	name = _name
	primary_key = _primary_key


func add_column(column: GDSQLColumnDefinition) -> GDSQLTableDefinition:
	columns.append(column)
	return self


func add_index(index: GDSQLIndexDefinition) -> GDSQLTableDefinition:
	indexes.append(index)
	return self


func add_foreign_key(foreign_key: GDSQLForeignKeyDefinition) -> GDSQLTableDefinition:
	foreign_keys.append(foreign_key)
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


func get_index(index_name: StringName) -> GDSQLIndexDefinition:
	for index in indexes:
		if index.name == index_name:
			return index
	return null


func has_unique_key(column_name: StringName) -> bool:
	var column := get_column(column_name)
	if column != null and column.unique:
		return true
	for index in indexes:
		if index.unique and index.columns == [column_name]:
			return true
	return false


func get_foreign_key(foreign_key_name: StringName) -> GDSQLForeignKeyDefinition:
	for foreign_key in foreign_keys:
		if foreign_key.name == foreign_key_name:
			return foreign_key
	return null


func get_foreign_keys_for_column(
		column_name: StringName,
) -> Array[GDSQLForeignKeyDefinition]:
	var matches: Array[GDSQLForeignKeyDefinition] = []
	for foreign_key in foreign_keys:
		if foreign_key.references_local_column(column_name):
			matches.append(foreign_key)
	return matches
