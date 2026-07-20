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
	var session := _get_session(context)
	var owns_session := context.session == null
	var inserted_rows: Array[GDSQLRowRecord] = []
	var statement_timestamp := _current_timestamp()
	for source_row in insert_plan.rows:
		var row := source_row.duplicate_record()
		_apply_insert_generated_values(
			insert_plan.target,
			row,
			statement_timestamp,
		)
		var stage_result := context.storage.stage_insert(insert_plan.target, row, session)
		result.diagnostics.merge(stage_result.diagnostics)
		if not stage_result.is_successful():
			if owns_session:
				context.transactions.rollback(session)
			return result
		inserted_rows.append(row)
	if owns_session:
		var commit_result := context.transactions.commit(session)
		result.diagnostics.merge(commit_result.diagnostics)
		if not commit_result.is_successful():
			context.transactions.rollback(session)
			return result
	result.rows.rows = inserted_rows
	result.statistics = { "affected_rows": inserted_rows.size() }
	result.value = result.rows
	return result


func _execute_update(
		update_plan: GDSQLUpdatePlan,
		context: GDSQLExecutionContext,
		result: GDSQLQueryExecutionResult,
) -> GDSQLQueryExecutionResult:
	var session := _get_session(context)
	var owns_session := context.session == null
	var snapshot := context.storage.read_table(update_plan.target, session)
	var updated_rows: Array[GDSQLRowRecord] = []
	var statement_timestamp := _current_timestamp()
	for source_row in snapshot.rows:
		if update_plan.predicate != null \
				and not _is_true(context.expression_evaluator.evaluate(update_plan.predicate, source_row)):
			continue
		var updated_row := source_row.duplicate_record()
		for assignment in update_plan.assignments:
			updated_row.set_value(
				assignment.column,
				context.expression_evaluator.evaluate(assignment.expression, source_row),
			)
		_apply_update_generated_values(
			update_plan.target,
			updated_row,
			statement_timestamp,
		)
		var key: Variant = source_row.get_value(update_plan.target.primary_key)
		var stage_result := context.storage.stage_update(update_plan.target, key, updated_row, session)
		result.diagnostics.merge(stage_result.diagnostics)
		if not stage_result.is_successful():
			if owns_session:
				context.transactions.rollback(session)
			return result
		updated_rows.append(updated_row)
	if owns_session:
		var commit_result := context.transactions.commit(session)
		result.diagnostics.merge(commit_result.diagnostics)
		if not commit_result.is_successful():
			context.transactions.rollback(session)
			return result
	result.rows.rows = updated_rows
	result.statistics = { "affected_rows": updated_rows.size() }
	result.value = result.rows
	return result


func _apply_insert_generated_values(
		table: GDSQLTableDefinition,
		row: GDSQLRowRecord,
		statement_timestamp: int,
) -> void:
	for column in table.columns:
		if column.generation == GDSQLColumnDefinition.Generation.CREATED_AT \
				or column.generation == GDSQLColumnDefinition.Generation.UPDATED_AT:
			row.set_value(column.name, statement_timestamp)


func _apply_update_generated_values(
		table: GDSQLTableDefinition,
		row: GDSQLRowRecord,
		statement_timestamp: int,
) -> void:
	for column in table.columns:
		if column.generation == GDSQLColumnDefinition.Generation.UPDATED_AT:
			row.set_value(column.name, statement_timestamp)


func _current_timestamp() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


func _execute_delete(
		delete_plan: GDSQLDeletePlan,
		context: GDSQLExecutionContext,
		result: GDSQLQueryExecutionResult,
) -> GDSQLQueryExecutionResult:
	var session := _get_session(context)
	var owns_session := context.session == null
	var snapshot := context.storage.read_table(delete_plan.target, session)
	var deleted_rows: Array[GDSQLRowRecord] = []
	for row in snapshot.rows:
		if delete_plan.predicate != null \
				and not _is_true(context.expression_evaluator.evaluate(delete_plan.predicate, row)):
			continue
		var key: Variant = row.get_value(delete_plan.target.primary_key)
		var stage_result := context.storage.stage_delete(delete_plan.target, key, session)
		result.diagnostics.merge(stage_result.diagnostics)
		if not stage_result.is_successful():
			if owns_session:
				context.transactions.rollback(session)
			return result
		deleted_rows.append(row.duplicate_record())
	if owns_session:
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
		var snapshot := context.storage.read_table(scan.table, _get_session(context))
		var rows := GDSQLRowSet.new()
		rows.schema = node.output_schema
		var table_id := _table_id(scan.table)
		for stored_row in snapshot.rows:
			var row := stored_row.duplicate_record()
			row.set_source_values(
				table_id,
				stored_row.values,
				scan.alias if scan.alias != &"" else scan.table.name,
			)
			rows.rows.append(row)
		return rows
	if node is GDSQLPrimaryKeyLookupPlan:
		var lookup := node as GDSQLPrimaryKeyLookupPlan
		var rows := GDSQLRowSet.new()
		rows.schema = node.output_schema
		var key: Variant = context.expression_evaluator.evaluate(lookup.key, null)
		var row := context.storage.find_by_primary_key(lookup.table, key, _get_session(context))
		if row != null:
			var qualified_row := row.duplicate_record()
			qualified_row.set_source_values(
				_table_id(lookup.table),
				row.values,
				lookup.alias if lookup.alias != &"" else lookup.table.name,
			)
			rows.rows.append(qualified_row)
		return rows
	if node is GDSQLIndexLookupPlan:
		var lookup := node as GDSQLIndexLookupPlan
		var values: Array[Variant] = []
		for expression in lookup.values:
			values.append(context.expression_evaluator.evaluate(expression, null))
		return _qualify_lookup_rows(
			context.storage.find_by_index(
				lookup.table,
				lookup.index,
				values,
				_get_session(context),
			),
			lookup.table,
			lookup.alias,
			node.output_schema,
		)
	if node is GDSQLRangeLookupPlan:
		var lookup := node as GDSQLRangeLookupPlan
		var lower_bound: Variant = null \
		if lookup.lower_bound == null \
		else context.expression_evaluator.evaluate(lookup.lower_bound, null)
		var upper_bound: Variant = null \
		if lookup.upper_bound == null \
		else context.expression_evaluator.evaluate(lookup.upper_bound, null)
		return _qualify_lookup_rows(
			context.storage.find_by_index_range(
				lookup.table,
				lookup.index,
				lower_bound,
				upper_bound,
				lookup.include_lower,
				lookup.include_upper,
				_get_session(context),
			),
			lookup.table,
			lookup.alias,
			node.output_schema,
		)
	if node is GDSQLNestedLoopJoinPlan:
		return _execute_nested_loop_join(
			node as GDSQLNestedLoopJoinPlan,
			context,
			result,
		)
	if node is GDSQLAggregatePlan:
		return _execute_aggregate(
			node as GDSQLAggregatePlan,
			context,
			result,
		)
	if node is GDSQLFilterPlan:
		var filter := node as GDSQLFilterPlan
		var input := _execute_select_node(filter.input, context, result)
		var rows := GDSQLRowSet.new()
		rows.schema = node.output_schema
		for row in input.rows:
			if _is_true(context.expression_evaluator.evaluate(filter.predicate, row)):
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


func _get_session(context: GDSQLExecutionContext) -> GDSQLStorageSession:
	return context.session \
	if context.session != null \
	else context.transactions.begin()


func _qualify_lookup_rows(
		stored_rows: Array[GDSQLRowRecord],
		table: GDSQLTableDefinition,
		alias: StringName,
		output_schema: GDSQLResultSchema,
) -> GDSQLRowSet:
	var rows := GDSQLRowSet.new()
	rows.schema = output_schema
	for stored_row in stored_rows:
		var row := stored_row.duplicate_record()
		row.set_source_values(
			_table_id(table),
			stored_row.values,
			alias if alias != &"" else table.name,
		)
		rows.rows.append(row)
	return rows


func _execute_aggregate(
		aggregate: GDSQLAggregatePlan,
		context: GDSQLExecutionContext,
		result: GDSQLQueryExecutionResult,
) -> GDSQLRowSet:
	var input := _execute_select_node(aggregate.input, context, result)
	var rows := GDSQLRowSet.new()
	rows.schema = aggregate.output_schema
	var groups: Dictionary = { }
	if input.rows.is_empty() and aggregate.grouping.is_empty():
		groups["global"] = []
	for source_row in input.rows:
		var grouping_values: Array = []
		for expression in aggregate.grouping:
			grouping_values.append(
				context.expression_evaluator.evaluate(expression, source_row),
			)
		var group_key := "global" \
		if aggregate.grouping.is_empty() \
		else var_to_str(grouping_values)
		if not groups.has(group_key):
			groups[group_key] = []
		(groups[group_key] as Array).append(source_row)
	for group_key in groups:
		var source_rows: Array = groups[group_key]
		var aggregate_row := GDSQLRowRecord.new()
		if not source_rows.is_empty():
			aggregate_row = (source_rows[0] as GDSQLRowRecord).duplicate_record()
		for expression in aggregate.aggregates:
			aggregate_row.set_aggregate_value(
				expression,
				_evaluate_aggregate_function(
					expression,
					source_rows,
					context.expression_evaluator,
					context.function_registry,
					result,
				),
			)
		rows.rows.append(aggregate_row)
	return rows


func _evaluate_aggregate_function(
		expression: GDSQLFunctionExpression,
		source_rows: Array,
		evaluator: GDSQLExpressionEvaluator,
		function_registry: GDSQLQueryFunctionRegistry,
		result: GDSQLQueryExecutionResult,
) -> Variant:
	var function := function_registry.resolve_aggregate(expression.name)
	if function.is_valid():
		var values: Array = []
		if not expression.arguments.is_empty():
			for row in source_rows:
				values.append(evaluator.evaluate(expression.arguments[0], row))
		return function.call(values, source_rows.size())
	result.add_diagnostic(
		GDSQLQueryDiagnostic.new(
			&"GDSQL_EXECUTION_AGGREGATE_UNSUPPORTED",
			"Aggregate function '%s' is not implemented by the executor." % expression.name,
		),
	)
	return null


func _execute_nested_loop_join(
		join: GDSQLNestedLoopJoinPlan,
		context: GDSQLExecutionContext,
		result: GDSQLQueryExecutionResult,
) -> GDSQLRowSet:
	var left_rows := _execute_select_node(join.left, context, result)
	var right_rows := _execute_select_node(join.right, context, result)
	var rows := GDSQLRowSet.new()
	rows.schema = join.output_schema
	for left_row in left_rows.rows:
		var matched := false
		for right_row in right_rows.rows:
			var combined := _combine_rows(left_row, right_row)
			if _is_true(context.expression_evaluator.evaluate(join.condition, combined)):
				rows.rows.append(combined)
				matched = true
		if not matched and join.type == GDSQLJoinSpec.JoinType.LEFT:
			rows.rows.append(_combine_rows(left_row, _null_row(join.right_source)))
	return rows


func _combine_rows(left: GDSQLRowRecord, right: GDSQLRowRecord) -> GDSQLRowRecord:
	var combined := left.duplicate_record()
	for column in right.values:
		if not combined.values.has(column):
			combined.values[column] = right.values[column]
	combined.merge_source_values(right)
	return combined


func _null_row(source: GDSQLBoundTableSource) -> GDSQLRowRecord:
	var values: Dictionary = { }
	for column in source.table.columns:
		values[column.name] = null
	var row := GDSQLRowRecord.new(values)
	row.set_source_values(
		_table_id(source.table),
		values,
		source.get_qualifier(),
	)
	return row


func _table_id(table: GDSQLTableDefinition) -> GDSQLTableId:
	return GDSQLTableId.new(table.database_name, table.name)


func _is_true(value: Variant) -> bool:
	return value is bool and value


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
