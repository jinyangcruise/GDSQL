class_name GDSQLQuery
extends RefCounted

var _database_name: StringName


func _init(database_name: StringName = &"") -> void:
	_database_name = database_name


func select() -> GDSQLSelectQueryBuilder:
	return GDSQLSelectQueryBuilder.new(_database_name)


func insert() -> GDSQLInsertQueryBuilder:
	return GDSQLInsertQueryBuilder.new(_database_name)


func update() -> RefCounted:
	return null


func delete() -> RefCounted:
	return null
