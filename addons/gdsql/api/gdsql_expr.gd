class_name GDSQLExpr
extends RefCounted
## Code-facing factory and fluent entry point for canonical query expressions.
##
## Factories create the typed expression nodes consumed by validation, binding,
## planning, execution, and editor frontends. Expressions continue
## through fluent methods inherited from [GDSQLQueryExpression]:
## [codeblock]
## GDSQLExpr.column(&"level").greater_than(3).and_(s
##     GDSQLExpr.column(&"active").equals(true),
## )
## [/codeblock]
## Factory operands accept literals or existing expressions. Existing
## expressions retain their structure, while other values become
## [GDSQLLiteralExpression] nodes.

## Starts a fluent expression from a column reference. [param table_alias]
## qualifies the reference during multi-source binding and joins.
## [codeblock]
## GDSQLExpr.column(&"level").greater_than(3)
## GDSQLExpr.column(&"id", &"heroes").equals(1)
## [/codeblock]
static func column(
		column_name: StringName,
		table_alias: StringName = &"",
) -> GDSQLColumnExpression:
	return GDSQLColumnExpression.new(column_name, table_alias)


## Wraps a value as an explicit literal node for direct construction, generated
## code, or APIs that require a [GDSQLQueryExpression].
## [codeblock]
## GDSQLExpr.literal("Mage")
## GDSQLExpr.column(&"name").equals(GDSQLExpr.literal("Mage"))
## [/codeblock]
static func literal(value: Variant) -> GDSQLLiteralExpression:
	return GDSQLLiteralExpression.new(value)


## Combines two predicates with logical AND. The symmetric factory supports
## generated expressions, while the fluent form reads from left to right:
## [codeblock]
## left.and_(right)
## GDSQLExpr.and_(left, right)
## [/codeblock]
static func and_(left: Variant, right: Variant) -> GDSQLLogicalExpression:
	return GDSQLLogicalExpression.new(
		_to_expression(left),
		GDSQLLogicalExpression.LogicalOperator.AND,
		_to_expression(right),
	)


## Combines two predicates with logical OR. The symmetric factory supports
## generated expressions, while the fluent form reads from left to right:
## [codeblock]
## left.or_(right)
## GDSQLExpr.or_(left, right)
## [/codeblock]
static func or_(left: Variant, right: Variant) -> GDSQLLogicalExpression:
	return GDSQLLogicalExpression.new(
		_to_expression(left),
		GDSQLLogicalExpression.LogicalOperator.OR,
		_to_expression(right),
	)


## Inverts one predicate with logical NOT. Both forms create the same canonical
## expression:
## [codeblock]
## condition.not_()
## GDSQLExpr.not_(condition)
## [/codeblock]
static func not_(expression: Variant) -> GDSQLLogicalExpression:
	return GDSQLLogicalExpression.new(
		_to_expression(expression),
		GDSQLLogicalExpression.LogicalOperator.NOT,
	)


## Describes a scalar function whose result is evaluated for each row.
## Arguments may combine columns, calculated expressions, and literal values.
## The returned expression can continue through comparison and logical methods:
## [codeblock]
## GDSQLExpr.scalar(&"upper", [GDSQLExpr.column(&"name")]).equals("MAGE")
## GDSQLExpr.scalar(&"coalesce", [GDSQLExpr.column(&"nickname"), "Unknown"])
## [/codeblock]
static func scalar(
		function_name: StringName,
		arguments: Array = [],
) -> GDSQLFunctionExpression:
	return GDSQLFunctionExpression.new(
		function_name,
		_to_expression_array(arguments),
	)


## Describes an aggregate function evaluated across the active group or result
## set. Arguments may combine columns, calculated expressions, and literals.
## [codeblock]
## GDSQLExpr.aggregate(&"count", [GDSQLExpr.column(&"id")])
## GDSQLExpr.aggregate(&"sum", [GDSQLExpr.column(&"damage")])
## [/codeblock]
static func aggregate(
		function_name: StringName,
		arguments: Array = [],
) -> GDSQLFunctionExpression:
	return GDSQLFunctionExpression.new(
		function_name,
		_to_expression_array(arguments),
		true,
	)


## Preserves expression operands and wraps data operands as literal nodes.
static func _to_expression(value: Variant) -> GDSQLQueryExpression:
	if value is GDSQLQueryExpression:
		return value
	return literal(value)


## Applies operand coercion while preserving argument order.
static func _to_expression_array(values: Array) -> Array[GDSQLQueryExpression]:
	var expressions: Array[GDSQLQueryExpression] = []
	for value in values:
		expressions.append(_to_expression(value))
	return expressions
