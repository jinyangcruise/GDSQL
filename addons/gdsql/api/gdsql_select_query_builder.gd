class_name GDSQLSelectQueryBuilder
extends RefCounted

var _built: bool = false
var _database_name: StringName
var _source: GDSQLQuerySource
var _projections: Array[GDSQLSelectProjection] = []
var _joins: Array[GDSQLJoinSpec] = []
var _predicate: GDSQLQueryExpression
var _grouping: Array[GDSQLQueryExpression] = []
var _having: GDSQLQueryExpression
var _ordering: Array[GDSQLOrderClause] = []
var _limit: int = -1
var _offset: int = 0
var _distinct: bool = false


func _init(
		database_name: StringName = &"",
		table_name: StringName = &"",
) -> void:
	_database_name = database_name
	if table_name != &"":
		_source = GDSQLTableReference.new(table_name, _database_name)


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
		_projections.append(
			GDSQLSelectProjection.new(GDSQLColumnExpression.new(column_name)),
		)
	return self


func column(
		column_name: StringName,
		alias: StringName = &"",
) -> GDSQLSelectQueryBuilder:
	return project(GDSQLColumnExpression.new(column_name), alias)


func project(
		expression: GDSQLQueryExpression,
		alias: StringName = &"",
) -> GDSQLSelectQueryBuilder:
	_ensure_mutable()
	_projections.append(GDSQLSelectProjection.new(expression, alias))
	return self


func join(join_spec: GDSQLJoinSpec) -> GDSQLSelectQueryBuilder:
	_ensure_mutable()
	_joins.append(join_spec)
	return self


func join_table(
		table_name: StringName,
		condition: GDSQLQueryExpression,
		alias: StringName = &"",
		type: GDSQLJoinSpec.JoinType = GDSQLJoinSpec.JoinType.INNER,
) -> GDSQLSelectQueryBuilder:
	return join(
		GDSQLJoinSpec.new(
			type,
			GDSQLTableReference.new(table_name, _database_name, alias),
			condition,
		),
	)


func inner_join(
		table_name: StringName,
		condition: GDSQLQueryExpression,
		alias: StringName = &"",
) -> GDSQLSelectQueryBuilder:
	return join_table(table_name, condition, alias, GDSQLJoinSpec.JoinType.INNER)


func left_join(
		table_name: StringName,
		condition: GDSQLQueryExpression,
		alias: StringName = &"",
) -> GDSQLSelectQueryBuilder:
	return join_table(table_name, condition, alias, GDSQLJoinSpec.JoinType.LEFT)


func group_by(expression: GDSQLQueryExpression) -> GDSQLSelectQueryBuilder:
	_ensure_mutable()
	_grouping.append(expression)
	return self


func group_by_column(
		column_name: StringName,
		table_alias: StringName = &"",
) -> GDSQLSelectQueryBuilder:
	return group_by(GDSQLColumnExpression.new(column_name, table_alias))


func having(expression: GDSQLQueryExpression) -> GDSQLSelectQueryBuilder:
	_ensure_mutable()
	_having = expression
	return self


func aggregate(
		function_name: StringName,
		arguments: Array[GDSQLQueryExpression] = [],
		alias: StringName = &"",
) -> GDSQLSelectQueryBuilder:
	return project(GDSQLFunctionExpression.new(function_name, arguments, true), alias)


func count(
		expression: GDSQLQueryExpression = null,
		alias: StringName = &"",
) -> GDSQLSelectQueryBuilder:
	var arguments: Array[GDSQLQueryExpression] = []
	if expression != null:
		arguments.append(expression)
	return aggregate(&"count", arguments, alias)


func sum(
		expression: GDSQLQueryExpression,
		alias: StringName = &"",
) -> GDSQLSelectQueryBuilder:
	return aggregate(&"sum", [expression], alias)


func average(
		expression: GDSQLQueryExpression,
		alias: StringName = &"",
) -> GDSQLSelectQueryBuilder:
	return aggregate(&"avg", [expression], alias)


func minimum(
		expression: GDSQLQueryExpression,
		alias: StringName = &"",
) -> GDSQLSelectQueryBuilder:
	return aggregate(&"min", [expression], alias)


func maximum(
		expression: GDSQLQueryExpression,
		alias: StringName = &"",
) -> GDSQLSelectQueryBuilder:
	return aggregate(&"max", [expression], alias)


func order_by(clause: GDSQLOrderClause) -> GDSQLSelectQueryBuilder:
	_ensure_mutable()
	_ordering.append(clause)
	return self


func order_by_column(
		column_name: StringName,
		direction: GDSQLOrderClause.SortDirection = GDSQLOrderClause.SortDirection.ASCENDING,
) -> GDSQLSelectQueryBuilder:
	return order_by(
		GDSQLOrderClause.new(GDSQLColumnExpression.new(column_name), direction),
	)


func distinct() -> GDSQLSelectQueryBuilder:
	_ensure_mutable()
	_distinct = true
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
	spec.joins = _joins.duplicate()
	spec.predicate = _predicate
	spec.grouping = _grouping.duplicate()
	spec.having = _having
	spec.ordering = _ordering.duplicate()
	spec.limit = _limit
	spec.offset = _offset
	spec.distinct = _distinct
	return spec


func _ensure_mutable() -> void:
	assert(not _built, "Select query builder cannot be modified after build().")
