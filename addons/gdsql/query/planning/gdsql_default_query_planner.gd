class_name GDSQLDefaultQueryPlanner
extends GDSQLQueryPlanner

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
	var primary_key_expression: GDSQLQueryExpression
	if bound_select.joins.is_empty():
		primary_key_expression = _get_primary_key_lookup(bound_select)
	if primary_key_expression != null:
		var lookup := GDSQLPrimaryKeyLookupPlan.new()
		lookup.table = bound_select.source.table
		lookup.key = primary_key_expression
		lookup.output_schema = source_schema
		current = lookup
	else:
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


func _is_primary_key_column(expression: GDSQLQueryExpression, table: GDSQLTableDefinition) -> bool:
	return expression is GDSQLBoundColumnExpression \
			and (expression as GDSQLBoundColumnExpression).column_id.column_name == table.primary_key
