class_name GDSQLDeleteQueryBuilder
extends RefCounted

var _built: bool = false
var _database_name: StringName
var _table_name: StringName
var _predicate: GDSQLQueryExpression


func _init(
		database_name: StringName = &"",
		table_name: StringName = &"",
) -> void:
	_database_name = database_name
	_table_name = table_name


func from_table(table_name: StringName) -> GDSQLDeleteQueryBuilder:
	_ensure_mutable()
	_table_name = table_name
	return self


func where(expression: GDSQLQueryExpression) -> GDSQLDeleteQueryBuilder:
	_ensure_mutable()
	_predicate = expression
	return self


func build() -> GDSQLDeleteQuerySpec:
	_ensure_mutable()
	_built = true
	var spec := GDSQLDeleteQuerySpec.new()
	spec.target = GDSQLTableReference.new(_table_name, _database_name)
	spec.predicate = _predicate
	return spec


func _ensure_mutable() -> void:
	assert(not _built, "Delete query builder cannot be modified after build().")
