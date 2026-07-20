class_name GDSQLExpressionVisitor
extends RefCounted

func visit_column(expression: GDSQLColumnExpression) -> Variant:
	return null


func visit_bound_column(expression: GDSQLBoundColumnExpression) -> Variant:
	return null


func visit_literal(expression: GDSQLLiteralExpression) -> Variant:
	return null


func visit_comparison(expression: GDSQLComparisonExpression) -> Variant:
	return null


func visit_logical(expression: GDSQLLogicalExpression) -> Variant:
	return null


func visit_arithmetic(expression: GDSQLArithmeticExpression) -> Variant:
	return null


func visit_null_check(expression: GDSQLNullCheckExpression) -> Variant:
	return null


func visit_function(expression: GDSQLFunctionExpression) -> Variant:
	return null
