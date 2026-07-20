class_name GDSQLDefaultQueryPlanner
extends GDSQLQueryPlanner

var _storage_capabilities: GDSQLStorageCapabilities


func _init(storage_capabilities: GDSQLStorageCapabilities = null) -> void:
	_storage_capabilities = storage_capabilities \
	if storage_capabilities != null \
	else GDSQLStorageCapabilities.new()


func create_plan(query: GDSQLBoundQuery) -> GDSQLQueryPlanningResult:
	var result := GDSQLQueryPlanningResult.new()
	if query == null:
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_PLANNING_OPERATION_UNSUPPORTED",
				"Cannot plan a null bound query.",
			),
		)
		return result
	if query.root_operation is GDSQLBoundInsertQuery:
		return _plan_insert(query.root_operation as GDSQLBoundInsertQuery)
	if query.root_operation is GDSQLBoundSelectQuery:
		return _plan_select(query.root_operation as GDSQLBoundSelectQuery, query.output_schema)
	if query.root_operation is GDSQLBoundUpdateQuery:
		return _plan_update(query.root_operation as GDSQLBoundUpdateQuery)
	if query.root_operation is GDSQLBoundDeleteQuery:
		return _plan_delete(query.root_operation as GDSQLBoundDeleteQuery)
	result.add_diagnostic(
		GDSQLQueryDiagnostic.new(
			&"GDSQL_PLANNING_OPERATION_UNSUPPORTED",
			"The bound query operation is not implemented by the planner.",
		),
	)
	return result


func _plan_insert(bound_insert: GDSQLBoundInsertQuery) -> GDSQLQueryPlanningResult:
	var result := GDSQLQueryPlanningResult.new()
	var insert_plan := GDSQLInsertPlan.new()
	insert_plan.target = bound_insert.target
	insert_plan.rows = bound_insert.rows.duplicate()
	result.plan = GDSQLQueryPlan.new(insert_plan)
	result.value = result.plan
	return result


func _plan_update(bound_update: GDSQLBoundUpdateQuery) -> GDSQLQueryPlanningResult:
	var result := GDSQLQueryPlanningResult.new()
	var update_plan := GDSQLUpdatePlan.new()
	update_plan.target = bound_update.target
	update_plan.assignments = bound_update.assignments.duplicate()
	update_plan.predicate = bound_update.predicate
	result.plan = GDSQLQueryPlan.new(update_plan)
	result.value = result.plan
	return result


func _plan_delete(bound_delete: GDSQLBoundDeleteQuery) -> GDSQLQueryPlanningResult:
	var result := GDSQLQueryPlanningResult.new()
	var delete_plan := GDSQLDeletePlan.new()
	delete_plan.target = bound_delete.target
	delete_plan.predicate = bound_delete.predicate
	result.plan = GDSQLQueryPlan.new(delete_plan)
	result.value = result.plan
	return result


func _plan_select(bound_select: GDSQLBoundSelectQuery, output_schema: GDSQLResultSchema) -> GDSQLQueryPlanningResult:
	var result := GDSQLQueryPlanningResult.new()
	var current: GDSQLPlanNode
	var source_schema := GDSQLResultSchema.new()
	for column in bound_select.source.table.columns:
		source_schema.columns.append(column)
	for join in bound_select.joins:
		for column in join.source.table.columns:
			source_schema.columns.append(column)
	if bound_select.joins.is_empty():
		current = _get_lookup_plan(bound_select, source_schema)
	if current == null:
		current = _scan_source(bound_select.source, source_schema)
		for join in bound_select.joins:
			var join_plan := GDSQLNestedLoopJoinPlan.new()
			join_plan.left = current
			join_plan.right = _scan_source(join.source, source_schema)
			join_plan.type = join.type
			join_plan.condition = join.condition
			join_plan.right_source = join.source
			join_plan.output_schema = source_schema
			current = join_plan
	if bound_select.predicate != null:
		var filter := GDSQLFilterPlan.new()
		filter.input = current
		filter.predicate = bound_select.predicate
		filter.output_schema = source_schema
		current = filter
	var aggregates: Array[GDSQLFunctionExpression] = []
	for selected in bound_select.projections:
		_collect_aggregates(selected.expression, aggregates)
	_collect_aggregates(bound_select.having, aggregates)
	for clause in bound_select.ordering:
		_collect_aggregates(clause.expression, aggregates)
	if not bound_select.grouping.is_empty() or not aggregates.is_empty():
		var aggregate := GDSQLAggregatePlan.new()
		aggregate.input = current
		aggregate.grouping = bound_select.grouping.duplicate()
		aggregate.aggregates = aggregates
		aggregate.output_schema = source_schema
		current = aggregate
		if bound_select.having != null:
			var having_filter := GDSQLFilterPlan.new()
			having_filter.input = current
			having_filter.predicate = bound_select.having
			having_filter.output_schema = source_schema
			current = having_filter
	if not bound_select.ordering.is_empty():
		var sort := GDSQLSortPlan.new()
		sort.input = current
		sort.ordering = bound_select.ordering.duplicate()
		sort.output_schema = source_schema
		current = sort
	if not bound_select.projections.is_empty():
		var projection := GDSQLProjectionPlan.new()
		projection.input = current
		projection.projections = bound_select.projections.duplicate()
		projection.output_schema = output_schema
		current = projection
	if bound_select.distinct:
		var distinct := GDSQLDistinctPlan.new()
		distinct.input = current
		distinct.output_schema = output_schema
		current = distinct
	if bound_select.limit >= 0 or bound_select.offset > 0:
		var limit := GDSQLLimitPlan.new()
		limit.input = current
		limit.limit = bound_select.limit
		limit.offset = bound_select.offset
		limit.output_schema = output_schema
		current = limit
	result.plan = GDSQLQueryPlan.new(current)
	result.value = result.plan
	return result


func _scan_source(
		source: GDSQLBoundTableSource,
		output_schema: GDSQLResultSchema,
) -> GDSQLTableScanPlan:
	var scan := GDSQLTableScanPlan.new()
	scan.table = source.table
	scan.alias = source.alias
	scan.output_schema = output_schema
	return scan


func _get_primary_key_lookup(bound_select: GDSQLBoundSelectQuery) -> GDSQLQueryExpression:
	if not bound_select.predicate is GDSQLComparisonExpression:
		return null
	var comparison := bound_select.predicate as GDSQLComparisonExpression
	if comparison.operator != GDSQLComparisonExpression.ComparisonOperator.EQUAL:
		return null
	if _is_primary_key_column(comparison.left, bound_select.source.table) and comparison.right is GDSQLLiteralExpression:
		return comparison.right
	if _is_primary_key_column(comparison.right, bound_select.source.table) and comparison.left is GDSQLLiteralExpression:
		return comparison.left
	return null


func _get_lookup_plan(
		bound_select: GDSQLBoundSelectQuery,
		output_schema: GDSQLResultSchema,
) -> GDSQLPlanNode:
	var primary_key_expression := _get_primary_key_lookup(bound_select)
	if primary_key_expression != null:
		var primary_lookup := GDSQLPrimaryKeyLookupPlan.new()
		primary_lookup.table = bound_select.source.table
		primary_lookup.alias = bound_select.source.alias
		primary_lookup.key = primary_key_expression
		primary_lookup.output_schema = output_schema
		return primary_lookup
	if _storage_capabilities.supports_exact_index_lookup():
		var exact_match := _find_index_comparison(
			bound_select.predicate,
			bound_select.source.table,
			true,
		)
		if not exact_match.is_empty():
			var index_lookup := GDSQLIndexLookupPlan.new()
			index_lookup.table = bound_select.source.table
			index_lookup.alias = bound_select.source.alias
			index_lookup.index = exact_match["index"]
			index_lookup.values = [exact_match["literal"]]
			index_lookup.output_schema = output_schema
			return index_lookup
	if _storage_capabilities.supports_range_index_lookup():
		var range_match := _find_index_comparison(
			bound_select.predicate,
			bound_select.source.table,
			false,
		)
		if not range_match.is_empty():
			var range_lookup := GDSQLRangeLookupPlan.new()
			range_lookup.table = bound_select.source.table
			range_lookup.alias = bound_select.source.alias
			range_lookup.index = range_match["index"]
			range_lookup.output_schema = output_schema
			_apply_range_bound(
				range_lookup,
				range_match["operator"],
				range_match["literal"],
			)
			return range_lookup
	return null


func _find_index_comparison(
		expression: GDSQLQueryExpression,
		table: GDSQLTableDefinition,
		exact: bool,
) -> Dictionary:
	if expression is GDSQLLogicalExpression:
		var logical := expression as GDSQLLogicalExpression
		if logical.operator != GDSQLLogicalExpression.LogicalOperator.AND:
			return { }
		var left_match := _find_index_comparison(logical.left, table, exact)
		return left_match \
		if not left_match.is_empty() \
		else _find_index_comparison(logical.right, table, exact)
	if not expression is GDSQLComparisonExpression:
		return { }
	var comparison := expression as GDSQLComparisonExpression
	if exact and comparison.operator != GDSQLComparisonExpression.ComparisonOperator.EQUAL:
		return { }
	if not exact and comparison.operator not in [
		GDSQLComparisonExpression.ComparisonOperator.GREATER_THAN,
		GDSQLComparisonExpression.ComparisonOperator.GREATER_THAN_OR_EQUAL,
		GDSQLComparisonExpression.ComparisonOperator.LESS_THAN,
		GDSQLComparisonExpression.ComparisonOperator.LESS_THAN_OR_EQUAL,
	]:
		return { }
	var column: GDSQLBoundColumnExpression
	var literal: GDSQLLiteralExpression
	var operator := comparison.operator
	if comparison.left is GDSQLBoundColumnExpression \
			and comparison.right is GDSQLLiteralExpression:
		column = comparison.left
		literal = comparison.right
	elif comparison.right is GDSQLBoundColumnExpression \
			and comparison.left is GDSQLLiteralExpression:
		column = comparison.right
		literal = comparison.left
		operator = _reverse_comparison(operator)
	else:
		return { }
	for index in table.indexes:
		if index.columns.size() == 1 \
				and index.columns[0] == column.column_id.column_name:
			return {
				"index": index,
				"literal": literal,
				"operator": operator,
			}
	return { }


func _apply_range_bound(
		plan: GDSQLRangeLookupPlan,
		operator: GDSQLComparisonExpression.ComparisonOperator,
		literal: GDSQLLiteralExpression,
) -> void:
	if operator == GDSQLComparisonExpression.ComparisonOperator.GREATER_THAN \
			or operator == GDSQLComparisonExpression.ComparisonOperator.GREATER_THAN_OR_EQUAL:
		plan.lower_bound = literal
		plan.include_lower = operator == \
				GDSQLComparisonExpression.ComparisonOperator.GREATER_THAN_OR_EQUAL
	else:
		plan.upper_bound = literal
		plan.include_upper = operator == \
				GDSQLComparisonExpression.ComparisonOperator.LESS_THAN_OR_EQUAL


func _reverse_comparison(
		operator: GDSQLComparisonExpression.ComparisonOperator,
) -> GDSQLComparisonExpression.ComparisonOperator:
	match operator:
		GDSQLComparisonExpression.ComparisonOperator.GREATER_THAN:
			return GDSQLComparisonExpression.ComparisonOperator.LESS_THAN
		GDSQLComparisonExpression.ComparisonOperator.GREATER_THAN_OR_EQUAL:
			return GDSQLComparisonExpression.ComparisonOperator.LESS_THAN_OR_EQUAL
		GDSQLComparisonExpression.ComparisonOperator.LESS_THAN:
			return GDSQLComparisonExpression.ComparisonOperator.GREATER_THAN
		GDSQLComparisonExpression.ComparisonOperator.LESS_THAN_OR_EQUAL:
			return GDSQLComparisonExpression.ComparisonOperator.GREATER_THAN_OR_EQUAL
	return operator


func _is_primary_key_column(expression: GDSQLQueryExpression, table: GDSQLTableDefinition) -> bool:
	return expression is GDSQLBoundColumnExpression \
			and (expression as GDSQLBoundColumnExpression).column_id.column_name == table.primary_key


func _collect_aggregates(
		expression: GDSQLQueryExpression,
		aggregates: Array[GDSQLFunctionExpression],
) -> void:
	if expression == null:
		return
	if expression is GDSQLFunctionExpression:
		var function := expression as GDSQLFunctionExpression
		if function.aggregate:
			if not aggregates.has(function):
				aggregates.append(function)
			return
		for argument in function.arguments:
			_collect_aggregates(argument, aggregates)
		return
	if expression is GDSQLComparisonExpression:
		var comparison := expression as GDSQLComparisonExpression
		_collect_aggregates(comparison.left, aggregates)
		_collect_aggregates(comparison.right, aggregates)
	elif expression is GDSQLLogicalExpression:
		var logical := expression as GDSQLLogicalExpression
		_collect_aggregates(logical.left, aggregates)
		_collect_aggregates(logical.right, aggregates)
	elif expression is GDSQLArithmeticExpression:
		var arithmetic := expression as GDSQLArithmeticExpression
		_collect_aggregates(arithmetic.left, aggregates)
		_collect_aggregates(arithmetic.right, aggregates)
	elif expression is GDSQLNullCheckExpression:
		_collect_aggregates(
			(expression as GDSQLNullCheckExpression).operand,
			aggregates,
		)
