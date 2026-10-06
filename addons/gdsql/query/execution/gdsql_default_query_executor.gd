class_name GDSQLDefaultQueryExecutor
extends GDSQLQueryExecutor

const DEFAULT_SCAN_BATCH_SIZE := 256

var _resource_resolver: GDSQLResourceResolver


func _init(resource_resolver: GDSQLResourceResolver = null) -> void:
	_resource_resolver = (
		resource_resolver
		if resource_resolver != null
		else GDSQLGodotResourceResolver.new()
	)


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
	if context.options != null \
			and context.options.defers_resources() \
			and plan.requires_concrete_resources:
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_DEFERRED_RESOURCE_EXPRESSION_UNSUPPORTED",
				"Deferred Resource queries cannot filter, sort, group, aggregate, " \
						+ "join, or derive expressions from Resource columns. Use eager " \
						+ "execution when query evaluation needs a concrete Resource.",
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
		result.statistics["returned_rows"] = result.rows.rows.size()
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
		return _execute_table_scan(
			node as GDSQLTableScanPlan,
			context,
			result,
		)
	if node is GDSQLPrimaryKeyLookupPlan:
		var lookup := node as GDSQLPrimaryKeyLookupPlan
		var rows := GDSQLRowSet.new()
		rows.schema = node.output_schema
		var key: Variant = context.expression_evaluator.evaluate(lookup.key, null)
		var row := context.storage.find_by_primary_key(
			lookup.table,
			key,
			_get_session(context),
			_read_request(lookup.required_columns),
		)
		if row != null:
			var qualified_row := _materialize_row(
				row,
				lookup.table,
				lookup.required_columns,
				context,
				result,
			)
			qualified_row.set_source_values(
				_table_id(lookup.table),
				qualified_row.values,
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
				_read_request(lookup.required_columns),
			),
			lookup.table,
			lookup.alias,
			node.output_schema,
			lookup.required_columns,
			context,
			result,
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
				_read_request(lookup.required_columns),
			),
			lookup.table,
			lookup.alias,
			node.output_schema,
			lookup.required_columns,
			context,
			result,
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


func _execute_table_scan(
	scan: GDSQLTableScanPlan,
	context: GDSQLExecutionContext,
	result: GDSQLQueryExecutionResult,
) -> GDSQLRowSet:
	var rows := GDSQLRowSet.new()
	rows.schema = scan.output_schema
	var session := _get_session(context)
	var request := _read_request(scan.required_columns)
	var skip_remaining := scan.pushed_offset
	var take_remaining := scan.pushed_limit
	if scan.has_pushed_window():
		result.statistics["scan_window_pushed"] = true
	if take_remaining == 0:
		return rows
	if not context.storage.get_capabilities().supports_bounded_reads():
		var snapshot := context.storage.read_table(scan.table, session, request)
		_merge_snapshot_read_statistics(snapshot.rows.size(), result)
		var stored_rows := _window_rows(
			snapshot.rows,
			skip_remaining,
			take_remaining,
		)
		_record_pushed_rows(
			snapshot.rows.size() - stored_rows.size(),
			scan,
			result,
		)
		rows.rows = _qualify_lookup_rows(
			stored_rows,
			scan.table,
			scan.alias,
			scan.output_schema,
			scan.required_columns,
			context,
			result,
		).rows
		return rows
	var cursor: GDSQLStorageReadCursor
	var seen_cursors: Array[GDSQLStorageReadCursor] = []
	while true:
		if context.cancellation != null and context.cancellation.is_cancelled():
			result.add_diagnostic(
				GDSQLQueryDiagnostic.new(
					&"GDSQL_EXECUTION_CANCELLED",
					"Query execution was cancelled during a table scan.",
				),
			)
			return rows
		var requested_size := _scan_batch_size(skip_remaining, take_remaining)
		var batch := context.storage.read_batch(
			scan.table,
			session,
			request.bounded(requested_size, cursor),
		)
		result.diagnostics.merge(batch.diagnostics)
		_merge_storage_read_statistics(batch, result)
		if not batch.is_successful():
			return rows
		var selected_rows: Array[GDSQLRowRecord] = []
		var selected_start := mini(skip_remaining, batch.rows.size())
		skip_remaining -= selected_start
		var selected_count := batch.rows.size() - selected_start
		if take_remaining >= 0:
			selected_count = mini(selected_count, take_remaining)
			take_remaining -= selected_count
		for index in range(selected_start, selected_start + selected_count):
			selected_rows.append(batch.rows[index])
		_record_pushed_rows(
			batch.rows.size() - selected_rows.size(),
			scan,
			result,
		)
		var qualified := _qualify_lookup_rows(
			selected_rows,
			scan.table,
			scan.alias,
			scan.output_schema,
			scan.required_columns,
			context,
			result,
		)
		rows.rows.append_array(qualified.rows)
		if take_remaining == 0:
			return rows
		if not batch.has_more():
			return rows
		var next_cursor := batch.get_next_cursor()
		for seen_cursor in seen_cursors:
			if seen_cursor.is_equivalent_to(next_cursor):
				result.add_diagnostic(
					GDSQLQueryDiagnostic.new(
						&"GDSQL_STORAGE_CURSOR_DID_NOT_ADVANCE",
						"Storage repeated a continuation during a bounded scan.",
					),
				)
				return rows
		seen_cursors.append(next_cursor)
		cursor = next_cursor
	return rows


func _scan_batch_size(skip_remaining: int, take_remaining: int) -> int:
	if take_remaining < 0:
		return DEFAULT_SCAN_BATCH_SIZE
	return mini(DEFAULT_SCAN_BATCH_SIZE, skip_remaining + take_remaining)


func _window_rows(
	stored_rows: Array[GDSQLRowRecord],
	offset: int,
	limit: int,
) -> Array[GDSQLRowRecord]:
	var rows: Array[GDSQLRowRecord] = []
	var start := mini(offset, stored_rows.size())
	var end := (
		stored_rows.size()
		if limit < 0
		else mini(start + limit, stored_rows.size())
	)
	for index in range(start, end):
		rows.append(stored_rows[index])
	return rows


func _record_pushed_rows(
	count: int,
	scan: GDSQLTableScanPlan,
	result: GDSQLQueryExecutionResult,
) -> void:
	if count <= 0 or not scan.has_pushed_window():
		return
	result.statistics["scan_rows_pruned"] = int(
		result.statistics.get("scan_rows_pruned", 0),
	) + count


func _merge_snapshot_read_statistics(
	row_count: int,
	result: GDSQLQueryExecutionResult,
) -> void:
	result.statistics["storage_snapshot_fallbacks"] = int(
		result.statistics.get("storage_snapshot_fallbacks", 0),
	) + 1
	result.statistics["storage_rows_scanned"] = int(
		result.statistics.get("storage_rows_scanned", 0),
	) + row_count
	result.statistics["storage_rows_returned"] = int(
		result.statistics.get("storage_rows_returned", 0),
	) + row_count
	result.statistics["storage_physical_read_bounded"] = false
	_merge_optional_storage_measurement("storage_bytes_read", -1, result)
	_merge_optional_storage_measurement("storage_pages_read", -1, result)


func _merge_storage_read_statistics(
	batch: GDSQLStorageReadBatch,
	result: GDSQLQueryExecutionResult,
) -> void:
	result.statistics["storage_batches"] = int(
		result.statistics.get("storage_batches", 0),
	) + 1
	result.statistics["storage_rows_scanned"] = int(
		result.statistics.get("storage_rows_scanned", 0),
	) + batch.statistics.rows_scanned
	result.statistics["storage_rows_returned"] = int(
		result.statistics.get("storage_rows_returned", 0),
	) + batch.statistics.rows_returned
	result.statistics["storage_physical_read_bounded"] = bool(
		result.statistics.get("storage_physical_read_bounded", true),
	) and batch.statistics.physical_read_bounded
	_merge_optional_storage_measurement(
		"storage_bytes_read",
		batch.statistics.bytes_read,
		result,
	)
	_merge_optional_storage_measurement(
		"storage_pages_read",
		batch.statistics.pages_read,
		result,
	)


func _merge_optional_storage_measurement(
	key: String,
	value: int,
	result: GDSQLQueryExecutionResult,
) -> void:
	var current := int(result.statistics.get(key, 0))
	result.statistics[key] = -1 if current < 0 or value < 0 else current + value


func _get_session(context: GDSQLExecutionContext) -> GDSQLStorageSession:
	return context.session \
	if context.session != null \
	else context.transactions.begin()


func _qualify_lookup_rows(
		stored_rows: Array[GDSQLRowRecord],
		table: GDSQLTableDefinition,
	alias: StringName,
	output_schema: GDSQLResultSchema,
	required_columns: Array[StringName],
	context: GDSQLExecutionContext,
	result: GDSQLQueryExecutionResult,
) -> GDSQLRowSet:
	var rows := GDSQLRowSet.new()
	rows.schema = output_schema
	for stored_row in stored_rows:
		var row := _materialize_row(
			stored_row,
			table,
			required_columns,
			context,
			result,
		)
		row.set_source_values(
			_table_id(table),
			row.values,
			alias if alias != &"" else table.name,
		)
		rows.rows.append(row)
	return rows


func _read_request(required_columns: Array[StringName]) -> GDSQLStorageReadRequest:
	return GDSQLStorageReadRequest.for_columns(required_columns, true)


func _materialize_row(
	stored_row: GDSQLRowRecord,
	table: GDSQLTableDefinition,
	required_columns: Array[StringName],
	context: GDSQLExecutionContext,
	result: GDSQLQueryExecutionResult,
) -> GDSQLRowRecord:
	var row := stored_row.duplicate_record()
	for column_name in required_columns:
		var value: Variant = row.get_value(column_name)
		if not value is GDSQLResourceReference:
			continue
		var reference := value as GDSQLResourceReference
		if context.options != null and context.options.defers_resources():
			row.set_value(column_name, reference.create_handle(_resource_resolver))
			result.statistics["resource_handles_created"] = int(
				result.statistics.get("resource_handles_created", 0),
			) + 1
			continue
		var resolution := _resource_resolver.resolve(reference)
		if not resolution.is_successful():
			_add_resource_diagnostics(
				resolution,
				table,
				row,
				column_name,
				result,
			)
			row.set_value(column_name, null)
			continue
		var resource := resolution.get_value() as Resource
		var column := table.get_column(column_name)
		if resource == null or column == null or not column.accepts_value(resource):
			result.add_diagnostic(
				GDSQLQueryDiagnostic.new(
					&"GDSQL_RESOURCE_REFERENCE_TYPE_MISMATCH",
					"Referenced Resource for %s.%s row '%s' column '%s' does not match %s." % [
						table.database_name,
						table.name,
						row.get_value(table.primary_key),
						column_name,
						column.expected_type_name() if column != null else "the declared type",
					],
					GDSQLQueryDiagnostic.Severity.ERROR,
					null,
					reference,
				),
			)
			row.set_value(column_name, null)
			continue
		row.set_value(column_name, resource)
		result.statistics["resources_materialized"] = int(
			result.statistics.get("resources_materialized", 0),
		) + 1
	return row


func _add_resource_diagnostics(
	resolution: GDSQLOperationResult,
	table: GDSQLTableDefinition,
	row: GDSQLRowRecord,
	column_name: StringName,
	result: GDSQLQueryExecutionResult,
) -> void:
	for entry in resolution.diagnostics.entries:
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				entry.code,
				"%s.%s row '%s' column '%s': %s" % [
					table.database_name,
					table.name,
					row.get_value(table.primary_key),
					column_name,
					entry.message,
				],
				entry.severity,
				null,
				entry.related_object,
			),
		)


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
