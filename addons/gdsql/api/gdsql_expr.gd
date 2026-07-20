## Compact factory for canonical query expressions.
##
## Variant parameters form the literal-coercion boundary. Query expressions
## remain canonical operands, while other values become
## [GDSQLLiteralExpression] instances.
class_name GDSQLExpr
extends RefCounted

## Creates an optionally qualified column expression.
static func column(
		column_name: StringName,
		table_alias: StringName = &"",
) -> GDSQLColumnExpression:
	return GDSQLColumnExpression.new(column_name, table_alias)


## Creates an explicit literal expression.
static func literal(value: Variant) -> GDSQLLiteralExpression:
	return GDSQLLiteralExpression.new(value)


## Creates a logical conjunction from literal or expression operands.
static func and_(left: Variant, right: Variant) -> GDSQLLogicalExpression:
	return GDSQLLogicalExpression.new(
		_to_expression(left),
		GDSQLLogicalExpression.LogicalOperator.AND,
		_to_expression(right),
	)


## Creates a logical disjunction from literal or expression operands.
static func or_(left: Variant, right: Variant) -> GDSQLLogicalExpression:
	return GDSQLLogicalExpression.new(
		_to_expression(left),
		GDSQLLogicalExpression.LogicalOperator.OR,
		_to_expression(right),
	)


## Creates the logical inversion of an operand.
static func not_(expression: Variant) -> GDSQLLogicalExpression:
	return GDSQLLogicalExpression.new(
		_to_expression(expression),
		GDSQLLogicalExpression.LogicalOperator.NOT,
	)


## Creates a scalar function expression and coerces its arguments.
static func scalar(
		function_name: StringName,
		arguments: Array = [],
) -> GDSQLFunctionExpression:
	return GDSQLFunctionExpression.new(
		function_name,
		_to_expression_array(arguments),
	)


## Creates an aggregate function expression and coerces its arguments.
static func aggregate(
		function_name: StringName,
		arguments: Array = [],
) -> GDSQLFunctionExpression:
	return GDSQLFunctionExpression.new(
		function_name,
		_to_expression_array(arguments),
		true,
	)


static func _to_expression(value: Variant) -> GDSQLQueryExpression:
	if value is GDSQLQueryExpression:
		return value
	return literal(value)


static func _to_expression_array(values: Array) -> Array[GDSQLQueryExpression]:
	var expressions: Array[GDSQLQueryExpression] = []
	for value in values:
		expressions.append(_to_expression(value))
	return expressions
