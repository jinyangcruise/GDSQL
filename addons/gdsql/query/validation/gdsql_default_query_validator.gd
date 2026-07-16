class_name GDSQLDefaultQueryValidator
extends GDSQLQueryValidator

const FunctionCatalog = preload("res://addons/gdsql/query/model/gdsql_query_function_catalog.gd")

var catalog: GDSQLCatalogService
var function_catalog: FunctionCatalog


func _init(
		catalog: GDSQLCatalogService = null,
		function_catalog: FunctionCatalog = null,
) -> void:
	self.catalog = catalog
	self.function_catalog = function_catalog


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
	if not query.joins.is_empty() or not query.grouping.is_empty() or query.having != null:
		return _error(
			&"GDSQL_VALIDATION_SELECT_FEATURE_UNSUPPORTED",
			"Joins, grouping, and having are not implemented in the select pipeline.",
		)
	var result := GDSQLQueryValidationResult.new()
	var bound_select := GDSQLBoundSelectQuery.new()
	bound_select.source = table
	bound_select.limit = query.limit
	bound_select.offset = query.offset
	bound_select.distinct = query.distinct
	for projection_index in query.projections.size():
		var projection := query.projections[projection_index]
		if projection == null or projection.expression == null:
			return _error(
				&"GDSQL_VALIDATION_INVALID_PROJECTION",
				"Select projections require an expression.",
			)
		var bound_expression := _bind_expression(projection.expression, table, source.alias, result)
		if bound_expression == null:
			return result
		bound_select.projections.append(
			GDSQLSelectProjection.new(bound_expression, projection.alias),
		)
	if query.predicate != null:
		bound_select.predicate = _bind_expression(query.predicate, table, source.alias, result)
		if bound_select.predicate == null:
			return result
		if not _is_boolean_expression(bound_select.predicate):
			return _error(
				&"GDSQL_VALIDATION_PREDICATE_TYPE",
				"Select predicate must produce a boolean value.",
			)
	for clause in query.ordering:
		if clause == null or clause.expression == null:
			return _error(
				&"GDSQL_VALIDATION_INVALID_ORDERING",
				"Order clauses require an expression.",
			)
		var bound_ordering := _bind_expression(clause.expression, table, source.alias, result)
		if bound_ordering == null:
			return result
		bound_select.ordering.append(
			GDSQLOrderClause.new(bound_ordering, clause.direction),
		)
	var bound_query := GDSQLBoundQuery.new()
	bound_query.source_query = query
	bound_query.root_operation = bound_select
	bound_query.referenced_tables.append(table)
	bound_query.output_schema = GDSQLResultSchema.new()
	if bound_select.projections.is_empty():
		for column in table.columns:
			bound_query.output_schema.columns.append(_copy_column(column))
	else:
		var output_names: Dictionary = { }
		for projection_index in bound_select.projections.size():
			var projection := bound_select.projections[projection_index]
			var output_name := _projection_output_name(projection, projection_index)
			if output_names.has(output_name):
				return _error(
					&"GDSQL_VALIDATION_DUPLICATE_PROJECTION_NAME",
					"Projection output name '%s' appears more than once." % output_name,
				)
			output_names[output_name] = true
			bound_query.output_schema.columns.append(
				_projection_column(projection, output_name, table),
			)
	result.bound_query = bound_query
	result.value = bound_query
	return result


func _projection_output_name(
		projection: GDSQLSelectProjection,
		index: int,
) -> StringName:
	if projection.alias != &"":
		return projection.alias
	if projection.expression is GDSQLBoundColumnExpression:
		return (projection.expression as GDSQLBoundColumnExpression).column_id.column_name
	return StringName("column_%d" % index)


func _projection_column(
		projection: GDSQLSelectProjection,
		output_name: StringName,
		table: GDSQLTableDefinition,
) -> GDSQLColumnDefinition:
	if projection.expression is GDSQLBoundColumnExpression:
		var source_name := (projection.expression as GDSQLBoundColumnExpression).column_id.column_name
		var source_column := table.get_column(source_name)
		var column := _copy_column(source_column)
		column.name = output_name
		return column
	var data_type := TYPE_NIL
	var nullable := true
	if projection.expression is GDSQLLiteralExpression:
		var value: Variant = (projection.expression as GDSQLLiteralExpression).value
		data_type = typeof(value)
		nullable = value == null
	else:
		data_type = _expression_type(projection.expression)
		nullable = _expression_nullable(projection.expression)
	return GDSQLColumnDefinition.new(output_name, data_type, nullable)


func _copy_column(column: GDSQLColumnDefinition) -> GDSQLColumnDefinition:
	return GDSQLColumnDefinition.new(
		column.name,
		column.data_type,
		column.nullable,
		column.unique,
		column.auto_increment,
		column.default_value,
	)


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
		bound_column.nullable = column.nullable
		return bound_column
	if expression is GDSQLComparisonExpression:
		var comparison := expression as GDSQLComparisonExpression
		var left := _bind_expression(comparison.left, table, source_alias, result)
		var right := _bind_expression(comparison.right, table, source_alias, result)
		if left == null or right == null:
			return null
		if not _validate_comparison_types(comparison.operator, left, right, result):
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
		if not _is_boolean_expression(left) \
				or (logical.operator != GDSQLLogicalExpression.LogicalOperator.NOT \
								and not _is_boolean_expression(right)):
			result.add_diagnostic(
				GDSQLQueryDiagnostic.new(
					&"GDSQL_VALIDATION_LOGICAL_TYPE",
					"Logical expressions require boolean operands.",
				),
			)
			return null
		return GDSQLLogicalExpression.new(left, logical.operator, right)
	if expression is GDSQLArithmeticExpression:
		var arithmetic := expression as GDSQLArithmeticExpression
		var left := _bind_expression(arithmetic.left, table, source_alias, result)
		var right := _bind_expression(arithmetic.right, table, source_alias, result)
		if left == null or right == null:
			return null
		if not _validate_arithmetic_types(arithmetic.operator, left, right, result):
			return null
		return GDSQLArithmeticExpression.new(left, arithmetic.operator, right)
	if expression is GDSQLNullCheckExpression:
		var null_check := expression as GDSQLNullCheckExpression
		var operand := _bind_expression(null_check.operand, table, source_alias, result)
		if operand == null:
			return null
		return GDSQLNullCheckExpression.new(operand, null_check.operator)
	if expression is GDSQLFunctionExpression:
		return _bind_function(expression as GDSQLFunctionExpression, table, source_alias, result)
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
		if not _is_boolean_expression(bound_operation.predicate):
			return _error(
				&"GDSQL_VALIDATION_PREDICATE_TYPE",
				"Update predicate must produce a boolean value.",
			)
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
		if not _is_boolean_expression(bound_operation.predicate):
			return _error(
				&"GDSQL_VALIDATION_PREDICATE_TYPE",
				"Delete predicate must produce a boolean value.",
			)
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
	var expression_type := _expression_type(expression)
	if expression_type == TYPE_NIL or expression_type == column.data_type:
		return true
	return column.data_type == TYPE_FLOAT and expression_type == TYPE_INT


func _bind_function(
		expression: GDSQLFunctionExpression,
		table: GDSQLTableDefinition,
		source_alias: StringName,
		result: GDSQLQueryValidationResult,
) -> GDSQLQueryExpression:
	if function_catalog == null or not function_catalog.contains(expression.name):
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_VALIDATION_UNKNOWN_FUNCTION",
				"Unknown query function '%s'." % expression.name,
			),
		)
		return null
	var definition := function_catalog.resolve(expression.name)
	if expression.aggregate or definition.aggregate:
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_VALIDATION_AGGREGATE_UNSUPPORTED",
				"Aggregate function '%s' requires the grouping pipeline, which is not implemented." % expression.name,
			),
		)
		return null
	if not definition.accepts_argument_count(expression.arguments.size()):
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_VALIDATION_FUNCTION_ARITY",
				"Function '%s' does not accept %d arguments." \
						% [expression.name, expression.arguments.size()],
			),
		)
		return null
	var bound_arguments: Array[GDSQLQueryExpression] = []
	for argument in expression.arguments:
		var bound_argument := _bind_expression(argument, table, source_alias, result)
		if bound_argument == null:
			return null
		bound_arguments.append(bound_argument)
	if not _validate_function_types(expression.name, bound_arguments, result):
		return null
	return GDSQLFunctionExpression.new(expression.name, bound_arguments, false)


func _validate_comparison_types(
		operator: GDSQLComparisonExpression.ComparisonOperator,
		left: GDSQLQueryExpression,
		right: GDSQLQueryExpression,
		result: GDSQLQueryValidationResult,
) -> bool:
	var left_type := _expression_type(left)
	var right_type := _expression_type(right)
	if left_type == TYPE_NIL or right_type == TYPE_NIL \
			or left_type == right_type \
			or (_is_numeric_type(left_type) and _is_numeric_type(right_type)):
		return true
	result.add_diagnostic(
		GDSQLQueryDiagnostic.new(
			&"GDSQL_VALIDATION_COMPARISON_TYPE",
			"Comparison operands have incompatible types %s and %s." % [left_type, right_type],
		),
	)
	return false


func _validate_function_types(
		name: StringName,
		arguments: Array[GDSQLQueryExpression],
		result: GDSQLQueryValidationResult,
) -> bool:
	var normalized := String(name).to_lower()
	if normalized == "lower" or normalized == "upper" or normalized == "length":
		var data_type := _expression_type(arguments[0])
		if data_type != TYPE_NIL and data_type != TYPE_STRING and data_type != TYPE_STRING_NAME:
			result.add_diagnostic(
				GDSQLQueryDiagnostic.new(
					&"GDSQL_VALIDATION_FUNCTION_TYPE",
					"Function '%s' requires a string argument." % name,
				),
			)
			return false
	if normalized == "abs":
		var data_type := _expression_type(arguments[0])
		if data_type != TYPE_NIL and not _is_numeric_type(data_type):
			result.add_diagnostic(
				GDSQLQueryDiagnostic.new(
					&"GDSQL_VALIDATION_FUNCTION_TYPE",
					"Function 'abs' requires a numeric argument.",
				),
			)
			return false
	if normalized == "coalesce":
		var resolved_type := TYPE_NIL
		for argument in arguments:
			var argument_type := _expression_type(argument)
			if argument_type == TYPE_NIL:
				continue
			if resolved_type == TYPE_NIL:
				resolved_type = argument_type
			elif argument_type != resolved_type \
					and not (_is_numeric_type(argument_type) and _is_numeric_type(resolved_type)):
				result.add_diagnostic(
					GDSQLQueryDiagnostic.new(
						&"GDSQL_VALIDATION_FUNCTION_TYPE",
						"Function 'coalesce' requires compatible argument types.",
					),
				)
				return false
	return true


func _validate_arithmetic_types(
		operator: GDSQLArithmeticExpression.ArithmeticOperator,
		left: GDSQLQueryExpression,
		right: GDSQLQueryExpression,
		result: GDSQLQueryValidationResult,
) -> bool:
	var left_type := _expression_type(left)
	var right_type := _expression_type(right)
	if left_type == TYPE_NIL or right_type == TYPE_NIL:
		return true
	if operator == GDSQLArithmeticExpression.ArithmeticOperator.ADD \
			and left_type == TYPE_STRING and right_type == TYPE_STRING:
		return true
	if not _is_numeric_type(left_type) or not _is_numeric_type(right_type):
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_VALIDATION_ARITHMETIC_TYPE",
				"Arithmetic expressions require numeric operands; ADD also accepts two strings.",
			),
		)
		return false
	if operator == GDSQLArithmeticExpression.ArithmeticOperator.MODULO \
			and (left_type != TYPE_INT or right_type != TYPE_INT):
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_VALIDATION_ARITHMETIC_TYPE",
				"Modulo requires integer operands.",
			),
		)
		return false
	return true


func _expression_type(expression: GDSQLQueryExpression) -> Variant.Type:
	if expression is GDSQLLiteralExpression:
		return typeof((expression as GDSQLLiteralExpression).value)
	if expression is GDSQLBoundColumnExpression:
		return (expression as GDSQLBoundColumnExpression).data_type
	if expression is GDSQLComparisonExpression \
			or expression is GDSQLLogicalExpression \
			or expression is GDSQLNullCheckExpression:
		return TYPE_BOOL
	if expression is GDSQLFunctionExpression:
		if function_catalog == null:
			return TYPE_NIL
		var function := expression as GDSQLFunctionExpression
		var definition := function_catalog.resolve(function.name)
		if definition == null:
			return TYPE_NIL
		var return_type := definition.return_type
		if return_type == TYPE_NIL \
				and (String(function.name).to_lower() == "coalesce" \
								or String(function.name).to_lower() == "abs"):
			for argument in function.arguments:
				var argument_type := _expression_type(argument)
				if argument_type != TYPE_NIL:
					return argument_type
		return return_type
	if expression is GDSQLArithmeticExpression:
		var arithmetic := expression as GDSQLArithmeticExpression
		var left_type := _expression_type(arithmetic.left)
		var right_type := _expression_type(arithmetic.right)
		if arithmetic.operator == GDSQLArithmeticExpression.ArithmeticOperator.DIVIDE:
			return TYPE_FLOAT
		if left_type == TYPE_STRING and right_type == TYPE_STRING:
			return TYPE_STRING
		if left_type == TYPE_FLOAT or right_type == TYPE_FLOAT:
			return TYPE_FLOAT
		return TYPE_INT if left_type == TYPE_INT and right_type == TYPE_INT else TYPE_NIL
	return TYPE_NIL


func _expression_nullable(expression: GDSQLQueryExpression) -> bool:
	if expression is GDSQLLiteralExpression:
		return (expression as GDSQLLiteralExpression).value == null
	if expression is GDSQLBoundColumnExpression:
		return (expression as GDSQLBoundColumnExpression).nullable
	if expression is GDSQLNullCheckExpression:
		return false
	return true


func _is_boolean_expression(expression: GDSQLQueryExpression) -> bool:
	return _expression_type(expression) == TYPE_BOOL


func _is_numeric_type(data_type: Variant.Type) -> bool:
	return data_type == TYPE_INT or data_type == TYPE_FLOAT


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
