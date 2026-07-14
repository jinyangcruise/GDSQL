class_name GDSQLSelectQueryBuilder
extends RefCounted

var _built: bool = false
var _database_name: StringName
var _source: GDSQLQuerySource
var _projections: Array[GDSQLQueryExpression] = []
var _predicate: GDSQLQueryExpression
var _ordering: Array[GDSQLOrderClause] = []
var _limit: int = -1
var _offset: int = 0


func _init(database_name: StringName = &"") -> void:
	_database_name = database_name


func from_table(table_name: StringName, alias: StringName = &"") -> GDSQLSelectQueryBuilder:
	_ensure_mutable()
	_source = GDSQLTableReference.new(table_name, _database_name, alias)
	return self


func where(expression: GDSQLQueryExpression) -> GDSQLSelectQueryBuilder:
	_ensure_mutable()
	_predicate = expression
	return self


func columns(column_names: Array[StringName]) -> GDSQLSelectQueryBuilder:
	_ensure_mutable()
	_projections.clear()
	for column_name in column_names:
		_projections.append(GDSQLColumnExpression.new(column_name))
	return self


func join(join_spec: GDSQLJoinSpec) -> GDSQLSelectQueryBuilder:
	_ensure_mutable()
	return self


func order_by(clause: GDSQLOrderClause) -> GDSQLSelectQueryBuilder:
	_ensure_mutable()
	_ordering.append(clause)
	return self


func limit(value: int) -> GDSQLSelectQueryBuilder:
	_ensure_mutable()
	_limit = value
	return self


func offset(value: int) -> GDSQLSelectQueryBuilder:
	_ensure_mutable()
	_offset = value
	return self


func build() -> GDSQLSelectQuerySpec:
	_ensure_mutable()
	_built = true
	var spec := GDSQLSelectQuerySpec.new()
	spec.source = _source
	spec.projections = _projections.duplicate()
	spec.predicate = _predicate
	spec.ordering = _ordering.duplicate()
	spec.limit = _limit
	spec.offset = _offset
	return spec


func _ensure_mutable() -> void:
	assert(not _built, "Select query builder cannot be modified after build().")
