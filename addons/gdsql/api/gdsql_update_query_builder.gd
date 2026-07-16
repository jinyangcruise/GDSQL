class_name GDSQLUpdateQueryBuilder
extends RefCounted

var _built: bool = false
var _database_name: StringName
var _table_name: StringName
var _assignments: Array[GDSQLColumnAssignment] = []
var _predicate: GDSQLQueryExpression


func _init(
		database_name: StringName = &"",
		table_name: StringName = &"",
) -> void:
	_database_name = database_name
	_table_name = table_name


func table(table_name: StringName) -> GDSQLUpdateQueryBuilder:
	_ensure_mutable()
	_table_name = table_name
	return self


func set_value(column_name: StringName, value: Variant) -> GDSQLUpdateQueryBuilder:
	return set_expression(column_name, GDSQLLiteralExpression.new(value))


func set_expression(
		column_name: StringName,
		expression: GDSQLQueryExpression,
) -> GDSQLUpdateQueryBuilder:
	_ensure_mutable()
	_assignments.append(GDSQLColumnAssignment.new(column_name, expression))
	return self


func where(expression: GDSQLQueryExpression) -> GDSQLUpdateQueryBuilder:
	_ensure_mutable()
	_predicate = expression
	return self


func build() -> GDSQLUpdateQuerySpec:
	_ensure_mutable()
	_built = true
	var spec := GDSQLUpdateQuerySpec.new()
	spec.target = GDSQLTableReference.new(_table_name, _database_name)
	spec.assignments = _assignments.duplicate()
	spec.predicate = _predicate
	return spec


func _ensure_mutable() -> void:
	assert(not _built, "Update query builder cannot be modified after build().")
