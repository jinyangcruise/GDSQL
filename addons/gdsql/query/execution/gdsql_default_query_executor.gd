class_name GDSQLDefaultQueryExecutor
extends GDSQLQueryExecutor

func execute(plan: GDSQLQueryPlan, context: GDSQLExecutionContext) -> GDSQLQueryExecutionResult:
	var result := GDSQLQueryExecutionResult.new()
	result.rows = GDSQLRowSet.new()
	if plan == null or plan.root == null:
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_EXECUTION_PLAN_UNSUPPORTED",
				"Cannot execute an empty query plan.",
			),
		)
		return result
	if context.cancellation != null and context.cancellation.is_cancelled():
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_EXECUTION_CANCELLED",
				"Query execution was cancelled.",
			),
		)
		return result
	if plan.root is GDSQLInsertPlan:
		return _execute_insert(plan.root as GDSQLInsertPlan, context, result)
	result.rows = _execute_select_node(plan.root, context, result)
	if result.is_successful():
		result.statistics = { "returned_rows": result.rows.rows.size() }
		result.value = result.rows
	return result


func _execute_insert(
		insert_plan: GDSQLInsertPlan,
		context: GDSQLExecutionContext,
		result: GDSQLQueryExecutionResult,
) -> GDSQLQueryExecutionResult:
	var session := context.transactions.begin()
	for row in insert_plan.rows:
		var stage_result := context.storage.stage_insert(insert_plan.target, row, session)
		result.diagnostics.append_array(stage_result.diagnostics)
		if not stage_result.is_successful():
			context.transactions.rollback(session)
			return result
	var commit_result := context.transactions.commit(session)
	result.diagnostics.append_array(commit_result.diagnostics)
	if not commit_result.is_successful():
		context.transactions.rollback(session)
		return result
	result.rows.rows = insert_plan.rows.duplicate()
	result.statistics = { "affected_rows": insert_plan.rows.size() }
	result.value = result.rows
	return result


func _execute_select_node(
		node: GDSQLPlanNode,
		context: GDSQLExecutionContext,
		result: GDSQLQueryExecutionResult,
) -> GDSQLRowSet:
	if node is GDSQLTableScanPlan:
		var scan := node as GDSQLTableScanPlan
		var snapshot := context.storage.read_table(scan.table, context.transactions.begin())
		var rows := GDSQLRowSet.new()
		rows.schema = node.output_schema
		rows.rows = snapshot.rows.duplicate()
		return rows
	if node is GDSQLPrimaryKeyLookupPlan:
		var lookup := node as GDSQLPrimaryKeyLookupPlan
		var rows := GDSQLRowSet.new()
		rows.schema = node.output_schema
		var key: Variant = context.expression_evaluator.evaluate(lookup.key, null)
		var row := context.storage.find_by_primary_key(lookup.table, key, context.transactions.begin())
		if row != null:
			rows.rows.append(row)
		return rows
	if node is GDSQLFilterPlan:
		var filter := node as GDSQLFilterPlan
		var input := _execute_select_node(filter.input, context, result)
		var rows := GDSQLRowSet.new()
		rows.schema = node.output_schema
		for row in input.rows:
			if bool(context.expression_evaluator.evaluate(filter.predicate, row)):
				rows.rows.append(row)
		return rows
	if node is GDSQLProjectionPlan:
		var projection := node as GDSQLProjectionPlan
		var input := _execute_select_node(projection.input, context, result)
		var rows := GDSQLRowSet.new()
		rows.schema = node.output_schema
		for source_row in input.rows:
			var values: Dictionary = { }
			for index in projection.projections.size():
				var expression := projection.projections[index]
				values[_projection_name(expression, index)] = context.expression_evaluator.evaluate(expression, source_row)
			rows.rows.append(GDSQLRowRecord.new(values))
		return rows
	if node is GDSQLLimitPlan:
		var limit := node as GDSQLLimitPlan
		var input := _execute_select_node(limit.input, context, result)
		var rows := GDSQLRowSet.new()
		rows.schema = node.output_schema
		var start := mini(limit.offset, input.rows.size())
		var end := input.rows.size() if limit.limit < 0 else mini(start + limit.limit, input.rows.size())
		for index in range(start, end):
			rows.rows.append(input.rows[index])
		return rows
	result.add_diagnostic(
		GDSQLQueryDiagnostic.new(
			&"GDSQL_EXECUTION_PLAN_UNSUPPORTED",
			"Plan node '%s' is not implemented by the executor." % node.get_class(),
		),
	)
	return GDSQLRowSet.new()


func _projection_name(expression: GDSQLQueryExpression, index: int) -> StringName:
	if expression is GDSQLBoundColumnExpression:
		return (expression as GDSQLBoundColumnExpression).column_id.column_name
	if expression is GDSQLColumnExpression:
		return (expression as GDSQLColumnExpression).column_name
	return StringName("column_%d" % index)
