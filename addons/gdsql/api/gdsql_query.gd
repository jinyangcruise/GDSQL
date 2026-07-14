class_name GDSQLQuery
extends RefCounted

var _database_name: StringName
var _table_name: StringName


func _init(database_name: StringName = &"") -> void:
	_database_name = database_name


func table(table_name: StringName) -> GDSQLQuery:
	_table_name = table_name
	return self


func select() -> GDSQLSelectQueryBuilder:
	return GDSQLSelectQueryBuilder.new(_database_name, _table_name)


func insert() -> GDSQLInsertQueryBuilder:
	return GDSQLInsertQueryBuilder.new(_database_name, _table_name)


func update() -> GDSQLUpdateQueryBuilder:
	return GDSQLUpdateQueryBuilder.new(_database_name, _table_name)


func delete() -> GDSQLDeleteQueryBuilder:
	return GDSQLDeleteQueryBuilder.new(_database_name, _table_name)
