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
	if plan.root is GDSQLUpdatePlan:
		return _execute_update(plan.root as GDSQLUpdatePlan, context, result)
	if plan.root is GDSQLDeletePlan:
		return _execute_delete(plan.root as GDSQLDeletePlan, context, result)
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
		result.diagnostics.merge(stage_result.diagnostics)
		if not stage_result.is_successful():
			context.transactions.rollback(session)
			return result
	var commit_result := context.transactions.commit(session)
	result.diagnostics.merge(commit_result.diagnostics)
	if not commit_result.is_successful():
		context.transactions.rollback(session)
		return result
	result.rows.rows = insert_plan.rows.duplicate()
	result.statistics = { "affected_rows": insert_plan.rows.size() }
	result.value = result.rows
	return result


func _execute_update(
		update_plan: GDSQLUpdatePlan,
		context: GDSQLExecutionContext,
		result: GDSQLQueryExecutionResult,
) -> GDSQLQueryExecutionResult:
	var session := context.transactions.begin()
	var snapshot := context.storage.read_table(update_plan.target, session)
	var updated_rows: Array[GDSQLRowRecord] = []
	for source_row in snapshot.rows:
		if update_plan.predicate != null and not bool(context.expression_evaluator.evaluate(update_plan.predicate, source_row)):
			continue
		var updated_row := source_row.duplicate_record()
		for assignment in update_plan.assignments:
			updated_row.set_value(
				assignment.column,
				context.expression_evaluator.evaluate(assignment.expression, source_row),
			)
		var key: Variant = source_row.get_value(update_plan.target.primary_key)
		var stage_result := context.storage.stage_update(update_plan.target, key, updated_row, session)
		result.diagnostics.merge(stage_result.diagnostics)
		if not stage_result.is_successful():
			context.transactions.rollback(session)
			return result
		updated_rows.append(updated_row)
	var commit_result := context.transactions.commit(session)
	result.diagnostics.merge(commit_result.diagnostics)
	if not commit_result.is_successful():
		context.transactions.rollback(session)
		return result
	result.rows.rows = updated_rows
	result.statistics = { "affected_rows": updated_rows.size() }
	result.value = result.rows
	return result


func _execute_delete(
		delete_plan: GDSQLDeletePlan,
		context: GDSQLExecutionContext,
		result: GDSQLQueryExecutionResult,
) -> GDSQLQueryExecutionResult:
	var session := context.transactions.begin()
	var snapshot := context.storage.read_table(delete_plan.target, session)
	var deleted_rows: Array[GDSQLRowRecord] = []
	for row in snapshot.rows:
		if delete_plan.predicate != null and not bool(context.expression_evaluator.evaluate(delete_plan.predicate, row)):
			continue
		var key: Variant = row.get_value(delete_plan.target.primary_key)
		var stage_result := context.storage.stage_delete(delete_plan.target, key, session)
		result.diagnostics.merge(stage_result.diagnostics)
		if not stage_result.is_successful():
			context.transactions.rollback(session)
			return result
		deleted_rows.append(row.duplicate_record())
	var commit_result := context.transactions.commit(session)
	result.diagnostics.merge(commit_result.diagnostics)
	if not commit_result.is_successful():
		context.transactions.rollback(session)
		return result
	result.rows.rows = deleted_rows
	result.statistics = { "affected_rows": deleted_rows.size() }
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
				var selected := projection.projections[index]
				values[_projection_name(selected, index)] = context.expression_evaluator.evaluate(
					selected.expression,
					source_row,
				)
			rows.rows.append(GDSQLRowRecord.new(values))
		return rows
	if node is GDSQLDistinctPlan:
		var distinct := node as GDSQLDistinctPlan
		var input := _execute_select_node(distinct.input, context, result)
		var rows := GDSQLRowSet.new()
		rows.schema = node.output_schema
		for candidate in input.rows:
			if not _contains_row(rows.rows, candidate):
				rows.rows.append(candidate)
		return rows
	if node is GDSQLSortPlan:
		var sort := node as GDSQLSortPlan
		var input := _execute_select_node(sort.input, context, result)
		var rows := GDSQLRowSet.new()
		rows.schema = node.output_schema
		rows.rows = input.rows.duplicate()
		rows.rows.sort_custom(
			_compare_rows.bind(sort.ordering, context.expression_evaluator),
		)
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


func _projection_name(projection: GDSQLSelectProjection, index: int) -> StringName:
	if projection.alias != &"":
		return projection.alias
	if projection.expression is GDSQLBoundColumnExpression:
		return (projection.expression as GDSQLBoundColumnExpression).column_id.column_name
	return StringName("column_%d" % index)


func _contains_row(
		rows: Array[GDSQLRowRecord],
		candidate: GDSQLRowRecord,
) -> bool:
	for row in rows:
		if row.values == candidate.values:
			return true
	return false


func _compare_rows(
		left: GDSQLRowRecord,
		right: GDSQLRowRecord,
		ordering: Array[GDSQLOrderClause],
		evaluator: GDSQLExpressionEvaluator,
) -> bool:
	for clause in ordering:
		var comparison := _compare_values(
			evaluator.evaluate(clause.expression, left),
			evaluator.evaluate(clause.expression, right),
		)
		if comparison == 0:
			continue
		if clause.direction == GDSQLOrderClause.SortDirection.DESCENDING:
			return comparison > 0
		return comparison < 0
	return false


func _compare_values(left: Variant, right: Variant) -> int:
	if left == right:
		return 0
	if left == null:
		return -1
	if right == null:
		return 1
	if (typeof(left) == TYPE_INT or typeof(left) == TYPE_FLOAT) \
			and (typeof(right) == TYPE_INT or typeof(right) == TYPE_FLOAT):
		return -1 if left < right else 1
	if typeof(left) == typeof(right):
		match typeof(left):
			TYPE_STRING, TYPE_STRING_NAME:
				return -1 if String(left) < String(right) else 1
			TYPE_BOOL:
				return -1 if not bool(left) else 1
	var left_text := str(left)
	var right_text := str(right)
	if left_text == right_text:
		return 0
	return -1 if left_text < right_text else 1
