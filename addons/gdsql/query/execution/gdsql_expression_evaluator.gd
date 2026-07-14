class_name GDSQLExpressionEvaluator
extends RefCounted

func evaluate(expression: GDSQLQueryExpression, row_context: GDSQLRowRecord) -> Variant:
	if expression == null:
		return null
	if expression is GDSQLLiteralExpression:
		return (expression as GDSQLLiteralExpression).value
	if expression is GDSQLBoundColumnExpression:
		if row_context == null:
			return null
		return row_context.get_value((expression as GDSQLBoundColumnExpression).column_id.column_name)
	if expression is GDSQLColumnExpression:
		if row_context == null:
			return null
		return row_context.get_value((expression as GDSQLColumnExpression).column_name)
	if expression is GDSQLComparisonExpression:
		return _evaluate_comparison(expression as GDSQLComparisonExpression, row_context)
	if expression is GDSQLLogicalExpression:
		return _evaluate_logical(expression as GDSQLLogicalExpression, row_context)
	return null


func _evaluate_comparison(expression: GDSQLComparisonExpression, row: GDSQLRowRecord) -> bool:
	var left: Variant = evaluate(expression.left, row)
	var right: Variant = evaluate(expression.right, row)
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


func _evaluate_logical(expression: GDSQLLogicalExpression, row: GDSQLRowRecord) -> bool:
	var left := bool(evaluate(expression.left, row))
	match expression.operator:
		GDSQLLogicalExpression.LogicalOperator.AND:
			return left and bool(evaluate(expression.right, row))
		GDSQLLogicalExpression.LogicalOperator.OR:
			return left or bool(evaluate(expression.right, row))
		GDSQLLogicalExpression.LogicalOperator.NOT:
			return not left
	return false
