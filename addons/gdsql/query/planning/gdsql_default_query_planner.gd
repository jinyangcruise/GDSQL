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


func _plan_select(bound_select: GDSQLBoundSelectQuery, output_schema: GDSQLResultSchema) -> GDSQLQueryPlanningResult:
	var result := GDSQLQueryPlanningResult.new()
	var current: GDSQLPlanNode
	var primary_key_expression := _get_primary_key_lookup(bound_select)
	if primary_key_expression != null:
		var lookup := GDSQLPrimaryKeyLookupPlan.new()
		lookup.table = bound_select.source
		lookup.key = primary_key_expression
		lookup.output_schema = output_schema
		current = lookup
	else:
		var scan := GDSQLTableScanPlan.new()
		scan.table = bound_select.source
		scan.output_schema = output_schema
		current = scan
		if bound_select.predicate != null:
			var filter := GDSQLFilterPlan.new()
			filter.input = current
			filter.predicate = bound_select.predicate
			filter.output_schema = output_schema
			current = filter
	if not bound_select.projections.is_empty():
		var projection := GDSQLProjectionPlan.new()
		projection.input = current
		projection.projections = bound_select.projections.duplicate()
		projection.output_schema = output_schema
		current = projection
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


func _get_primary_key_lookup(bound_select: GDSQLBoundSelectQuery) -> GDSQLQueryExpression:
	if not bound_select.predicate is GDSQLComparisonExpression:
		return null
	var comparison := bound_select.predicate as GDSQLComparisonExpression
	if comparison.operator != GDSQLComparisonExpression.ComparisonOperator.EQUAL:
		return null
	if _is_primary_key_column(comparison.left, bound_select.source) and comparison.right is GDSQLLiteralExpression:
		return comparison.right
	if _is_primary_key_column(comparison.right, bound_select.source) and comparison.left is GDSQLLiteralExpression:
		return comparison.left
	return null


func _is_primary_key_column(expression: GDSQLQueryExpression, table: GDSQLTableDefinition) -> bool:
	return expression is GDSQLBoundColumnExpression \
			and (expression as GDSQLBoundColumnExpression).column_id.column_name == table.primary_key
