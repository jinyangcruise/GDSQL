class_name GDSQLDefaultQueryValidator
extends GDSQLQueryValidator

var catalog: GDSQLCatalogService


func _init(p_catalog: GDSQLCatalogService = null) -> void:
	catalog = p_catalog


func validate(query: GDSQLQuerySpec) -> GDSQLQueryValidationResult:
	if query is GDSQLInsertQuerySpec:
		return _validate_insert(query as GDSQLInsertQuerySpec)
	if query is GDSQLSelectQuerySpec:
		return _validate_select(query as GDSQLSelectQuerySpec)
	if query is GDSQLUpdateQuerySpec:
		return _validate_update(query as GDSQLUpdateQuerySpec)
	if query is GDSQLDeleteQuerySpec:
		return _validate_delete(query as GDSQLDeleteQuerySpec)
	return _error(&"GDSQL_VALIDATION_OPERATION_UNSUPPORTED", "Missing implementation")


func _validate_select(query: GDSQLSelectQuerySpec) -> GDSQLQueryValidationResult:
	if not query.source is GDSQLTableReference:
		return _error(&"GDSQL_VALIDATION_SELECT_SOURCE_REQUIRED", "Select query requires one table source.")
	var source := query.source as GDSQLTableReference
	var table := catalog.get_table(source.database_name, source.table_name)
	if table == null:
		return _error(
			&"GDSQL_VALIDATION_UNKNOWN_TABLE",
			"Unknown table '%s.%s'." % [source.database_name, source.table_name],
		)
	if query.limit < -1 or query.offset < 0:
		return _error(&"GDSQL_VALIDATION_INVALID_LIMIT", "Limit must be -1 or greater and offset cannot be negative.")
	if not query.joins.is_empty() or not query.grouping.is_empty() or query.having != null or not query.ordering.is_empty():
		return _error(
			&"GDSQL_VALIDATION_SELECT_FEATURE_UNSUPPORTED",
			"Joins, grouping, having, and ordering are not implemented in the minimal select slice.",
		)
	var result := GDSQLQueryValidationResult.new()
	var bound_select := GDSQLBoundSelectQuery.new()
	bound_select.source = table
	bound_select.limit = query.limit
	bound_select.offset = query.offset
	for projection in query.projections:
		var bound_projection := _bind_expression(projection, table, source.alias, result)
		if bound_projection == null:
			return result
		bound_select.projections.append(bound_projection)
	if query.predicate != null:
		bound_select.predicate = _bind_expression(query.predicate, table, source.alias, result)
		if bound_select.predicate == null:
			return result
	var bound_query := GDSQLBoundQuery.new()
	bound_query.source_query = query
	bound_query.root_operation = bound_select
	bound_query.referenced_tables.append(table)
	bound_query.output_schema = GDSQLResultSchema.new()
	if bound_select.projections.is_empty():
		bound_query.output_schema.columns = table.columns.duplicate()
	else:
		for projection in bound_select.projections:
			if projection is GDSQLBoundColumnExpression:
				bound_query.output_schema.columns.append(table.get_column((projection as GDSQLBoundColumnExpression).column_id.column_name))
	result.bound_query = bound_query
	result.value = bound_query
	return result


func _bind_expression(
		expression: GDSQLQueryExpression,
		table: GDSQLTableDefinition,
		source_alias: StringName,
		result: GDSQLQueryValidationResult,
) -> GDSQLQueryExpression:
	if expression is GDSQLLiteralExpression:
		return expression
	if expression is GDSQLColumnExpression:
		var column_expression := expression as GDSQLColumnExpression
		if column_expression.table_alias != &"" and column_expression.table_alias != source_alias and column_expression.table_alias != table.name:
			result.add_diagnostic(
				GDSQLQueryDiagnostic.new(
					&"GDSQL_VALIDATION_UNKNOWN_ALIAS",
					"Unknown table alias '%s'." % column_expression.table_alias,
				),
			)
			return null
		var column := table.get_column(column_expression.column_name)
		if column == null:
			result.add_diagnostic(
				GDSQLQueryDiagnostic.new(
					&"GDSQL_VALIDATION_UNKNOWN_COLUMN",
					"Unknown column '%s' in table '%s'." % [column_expression.column_name, table.name],
				),
			)
			return null
		var table_id := GDSQLTableId.new(table.database_name, table.name)
		var bound_column := GDSQLBoundColumnExpression.new()
		bound_column.table_id = table_id
		bound_column.column_id = GDSQLColumnId.new(table_id, column.name)
		bound_column.data_type = column.data_type
		return bound_column
	if expression is GDSQLComparisonExpression:
		var comparison := expression as GDSQLComparisonExpression
		var left := _bind_expression(comparison.left, table, source_alias, result)
		var right := _bind_expression(comparison.right, table, source_alias, result)
		if left == null or right == null:
			return null
		return GDSQLComparisonExpression.new(left, comparison.operator, right)
	if expression is GDSQLLogicalExpression:
		var logical := expression as GDSQLLogicalExpression
		var left := _bind_expression(logical.left, table, source_alias, result)
		var right: GDSQLQueryExpression
		if logical.right != null:
			right = _bind_expression(logical.right, table, source_alias, result)
		if left == null or (logical.right != null and right == null):
			return null
		return GDSQLLogicalExpression.new(left, logical.operator, right)
	result.add_diagnostic(
		GDSQLQueryDiagnostic.new(
			&"GDSQL_VALIDATION_EXPRESSION_UNSUPPORTED",
			"Expression type '%s' is not implemented in the minimal select slice." % expression.get_class(),
		),
	)
	return null


func _validate_insert(query: GDSQLInsertQuerySpec) -> GDSQLQueryValidationResult:
	if query.target == null:
		return _error(&"GDSQL_VALIDATION_INSERT_TARGET_REQUIRED", "Insert query requires a target table.")
	var table := catalog.get_table(query.target.database_name, query.target.table_name)
	if table == null:
		return _error(
			&"GDSQL_VALIDATION_UNKNOWN_TABLE",
			"Unknown table '%s.%s'." % [query.target.database_name, query.target.table_name],
		)
	if query.columns.is_empty() or query.rows.is_empty():
		return _error(&"GDSQL_VALIDATION_INSERT_VALUES_REQUIRED", "Insert query requires at least one column and row.")
	var seen_columns: Dictionary = { }
	for column_name in query.columns:
		if seen_columns.has(column_name):
			return _error(&"GDSQL_VALIDATION_DUPLICATE_COLUMN", "Column '%s' appears more than once." % column_name)
		seen_columns[column_name] = true
		if not table.has_column(column_name):
			return _error(&"GDSQL_VALIDATION_UNKNOWN_COLUMN", "Unknown column '%s' in table '%s'." % [column_name, table.name])
	for column in table.columns:
		if not column.nullable and column.default_value == null and not column.auto_increment and not seen_columns.has(column.name):
			return _error(&"GDSQL_VALIDATION_REQUIRED_COLUMN", "Required column '%s' is missing." % column.name)
	var bound_operation := GDSQLBoundInsertQuery.new()
	bound_operation.target = table
	for source_row in query.rows:
		if source_row.values.size() != query.columns.size():
			return _error(&"GDSQL_VALIDATION_VALUE_COUNT", "Insert value count does not match the column count.")
		var values: Dictionary = { }
		for index in query.columns.size():
			var column_name := query.columns[index]
			var column := table.get_column(column_name)
			var value: Variant = source_row.values[index]
			if not _is_compatible(value, column):
				return _error(
					&"GDSQL_VALIDATION_TYPE_MISMATCH",
					"Column '%s' expects Variant type %s, received %s." % [column_name, column.data_type, typeof(value)],
				)
			values[column_name] = value
		for column in table.columns:
			if not values.has(column.name) and column.default_value != null:
				values[column.name] = column.default_value
		bound_operation.rows.append(GDSQLRowRecord.new(values))
	var bound_query := GDSQLBoundQuery.new()
	bound_query.source_query = query
	bound_query.root_operation = bound_operation
	bound_query.referenced_tables = [table]
	var result := GDSQLQueryValidationResult.new()
	result.bound_query = bound_query
	result.value = bound_query
	return result


func _validate_update(query: GDSQLUpdateQuerySpec) -> GDSQLQueryValidationResult:
	if query.target == null:
		return _error(&"GDSQL_VALIDATION_UPDATE_TARGET_REQUIRED", "Update query requires a target table.")
	var table := catalog.get_table(query.target.database_name, query.target.table_name)
	if table == null:
		return _error(
			&"GDSQL_VALIDATION_UNKNOWN_TABLE",
			"Unknown table '%s.%s'." % [query.target.database_name, query.target.table_name],
		)
	if query.assignments.is_empty():
		return _error(&"GDSQL_VALIDATION_UPDATE_ASSIGNMENTS_REQUIRED", "Update query requires at least one assignment.")
	var result := GDSQLQueryValidationResult.new()
	var bound_operation := GDSQLBoundUpdateQuery.new()
	bound_operation.target = table
	var seen_columns: Dictionary = { }
	for assignment in query.assignments:
		if assignment == null or assignment.column == &"" or assignment.expression == null:
			return _error(&"GDSQL_VALIDATION_INVALID_ASSIGNMENT", "Update assignments require a column and expression.")
		if seen_columns.has(assignment.column):
			return _error(&"GDSQL_VALIDATION_DUPLICATE_COLUMN", "Column '%s' is assigned more than once." % assignment.column)
		seen_columns[assignment.column] = true
		var column := table.get_column(assignment.column)
		if column == null:
			return _error(&"GDSQL_VALIDATION_UNKNOWN_COLUMN", "Unknown column '%s' in table '%s'." % [assignment.column, table.name])
		if assignment.column == table.primary_key:
			return _error(&"GDSQL_VALIDATION_PRIMARY_KEY_UPDATE_FORBIDDEN", "Updating the primary key is not supported.")
		var bound_expression := _bind_expression(assignment.expression, table, &"", result)
		if bound_expression == null:
			return result
		if not _is_assignment_compatible(bound_expression, column):
			return _error(
				&"GDSQL_VALIDATION_TYPE_MISMATCH",
				"Assignment for column '%s' has an incompatible type." % assignment.column,
			)
		bound_operation.assignments.append(GDSQLColumnAssignment.new(assignment.column, bound_expression))
	if query.predicate != null:
		bound_operation.predicate = _bind_expression(query.predicate, table, &"", result)
		if bound_operation.predicate == null:
			return result
	return _bound_mutation_result(query, bound_operation, table)


func _validate_delete(query: GDSQLDeleteQuerySpec) -> GDSQLQueryValidationResult:
	if query.target == null:
		return _error(&"GDSQL_VALIDATION_DELETE_TARGET_REQUIRED", "Delete query requires a target table.")
	var table := catalog.get_table(query.target.database_name, query.target.table_name)
	if table == null:
		return _error(
			&"GDSQL_VALIDATION_UNKNOWN_TABLE",
			"Unknown table '%s.%s'." % [query.target.database_name, query.target.table_name],
		)
	var result := GDSQLQueryValidationResult.new()
	var bound_operation := GDSQLBoundDeleteQuery.new()
	bound_operation.target = table
	if query.predicate != null:
		bound_operation.predicate = _bind_expression(query.predicate, table, &"", result)
		if bound_operation.predicate == null:
			return result
	return _bound_mutation_result(query, bound_operation, table)


func _bound_mutation_result(
		query: GDSQLQuerySpec,
		operation: GDSQLBoundQueryOperation,
		table: GDSQLTableDefinition,
) -> GDSQLQueryValidationResult:
	var bound_query := GDSQLBoundQuery.new()
	bound_query.source_query = query
	bound_query.root_operation = operation
	bound_query.referenced_tables = [table]
	var result := GDSQLQueryValidationResult.new()
	result.bound_query = bound_query
	result.value = bound_query
	return result


func _is_assignment_compatible(
		expression: GDSQLQueryExpression,
		column: GDSQLColumnDefinition,
) -> bool:
	if expression is GDSQLLiteralExpression:
		return _is_compatible((expression as GDSQLLiteralExpression).value, column)
	var expression_type := TYPE_NIL
	if expression is GDSQLBoundColumnExpression:
		expression_type = (expression as GDSQLBoundColumnExpression).data_type
	elif expression is GDSQLComparisonExpression or expression is GDSQLLogicalExpression:
		expression_type = TYPE_BOOL
	if expression_type == TYPE_NIL or expression_type == column.data_type:
		return true
	return column.data_type == TYPE_FLOAT and expression_type == TYPE_INT


func _is_compatible(value: Variant, column: GDSQLColumnDefinition) -> bool:
	if value == null:
		return column.nullable
	if column.data_type == TYPE_NIL or typeof(value) == column.data_type:
		return true
	return column.data_type == TYPE_FLOAT and typeof(value) == TYPE_INT


func _error(code: StringName, message: String) -> GDSQLQueryValidationResult:
	var result := GDSQLQueryValidationResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
