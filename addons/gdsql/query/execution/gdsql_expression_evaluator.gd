class_name GDSQLExpressionEvaluator
extends RefCounted

var function_registry: GDSQLQueryFunctionRegistry


func _init(function_registry: GDSQLQueryFunctionRegistry = null) -> void:
	self.function_registry = function_registry


func evaluate(expression: GDSQLQueryExpression, row_context: GDSQLRowRecord) -> Variant:
	if expression == null:
		return null
	if expression is GDSQLLiteralExpression:
		return (expression as GDSQLLiteralExpression).value
	if expression is GDSQLBoundColumnExpression:
		if row_context == null:
			return null
		var bound_column := expression as GDSQLBoundColumnExpression
		return row_context.get_source_value(
			bound_column.table_id,
			bound_column.column_id.column_name,
			bound_column.source_qualifier,
		)
	if expression is GDSQLColumnExpression:
		if row_context == null:
			return null
		return row_context.get_value((expression as GDSQLColumnExpression).column_name)
	if expression is GDSQLComparisonExpression:
		return _evaluate_comparison(expression as GDSQLComparisonExpression, row_context)
	if expression is GDSQLLogicalExpression:
		return _evaluate_logical(expression as GDSQLLogicalExpression, row_context)
	if expression is GDSQLArithmeticExpression:
		return _evaluate_arithmetic(expression as GDSQLArithmeticExpression, row_context)
	if expression is GDSQLNullCheckExpression:
		return _evaluate_null_check(expression as GDSQLNullCheckExpression, row_context)
	if expression is GDSQLFunctionExpression:
		return _evaluate_function(expression as GDSQLFunctionExpression, row_context)
	return null


func _evaluate_comparison(expression: GDSQLComparisonExpression, row: GDSQLRowRecord) -> Variant:
	var left: Variant = evaluate(expression.left, row)
	var right: Variant = evaluate(expression.right, row)
	if left == null or right == null:
		return null
	match expression.operator:
		GDSQLComparisonExpression.ComparisonOperator.EQUAL:
			return left == right
		GDSQLComparisonExpression.ComparisonOperator.NOT_EQUAL:
			return left != right
		GDSQLComparisonExpression.ComparisonOperator.GREATER_THAN:
			return left > right
		GDSQLComparisonExpression.ComparisonOperator.LESS_THAN:
			return left < right
		GDSQLComparisonExpression.ComparisonOperator.GREATER_THAN_OR_EQUAL:
			return left >= right
		GDSQLComparisonExpression.ComparisonOperator.LESS_THAN_OR_EQUAL:
			return left <= right
	return false


func _evaluate_logical(expression: GDSQLLogicalExpression, row: GDSQLRowRecord) -> Variant:
	var left: Variant = evaluate(expression.left, row)
	match expression.operator:
		GDSQLLogicalExpression.LogicalOperator.AND:
			var right: Variant = evaluate(expression.right, row)
			if left == false or right == false:
				return false
			if left == null or right == null:
				return null
			return true
		GDSQLLogicalExpression.LogicalOperator.OR:
			var right: Variant = evaluate(expression.right, row)
			if left == true or right == true:
				return true
			if left == null or right == null:
				return null
			return false
		GDSQLLogicalExpression.LogicalOperator.NOT:
			return null if left == null else not bool(left)
	return false


func _evaluate_arithmetic(expression: GDSQLArithmeticExpression, row: GDSQLRowRecord) -> Variant:
	var left: Variant = evaluate(expression.left, row)
	var right: Variant = evaluate(expression.right, row)
	if left == null or right == null:
		return null
	match expression.operator:
		GDSQLArithmeticExpression.ArithmeticOperator.ADD:
			return left + right
		GDSQLArithmeticExpression.ArithmeticOperator.SUBTRACT:
			return left - right
		GDSQLArithmeticExpression.ArithmeticOperator.MULTIPLY:
			return left * right
		GDSQLArithmeticExpression.ArithmeticOperator.DIVIDE:
			return null if right == 0 else float(left) / float(right)
		GDSQLArithmeticExpression.ArithmeticOperator.MODULO:
			return null if right == 0 else left % right
	return null


func _evaluate_null_check(expression: GDSQLNullCheckExpression, row: GDSQLRowRecord) -> bool:
	var is_null := evaluate(expression.operand, row) == null
	if expression.operator == GDSQLNullCheckExpression.NullCheckOperator.IS_NOT_NULL:
		return not is_null
	return is_null


func _evaluate_function(expression: GDSQLFunctionExpression, row: GDSQLRowRecord) -> Variant:
	if function_registry == null:
		return null
	var function := function_registry.resolve(expression.name)
	if not function.is_valid():
		return null
	var values: Array = []
	for argument in expression.arguments:
		values.append(evaluate(argument, row))
	return function.call(values)
