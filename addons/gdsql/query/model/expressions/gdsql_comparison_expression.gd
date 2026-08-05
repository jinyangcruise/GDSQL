class_name GDSQLComparisonExpression
extends GDSQLQueryExpression

enum ComparisonOperator {
	EQUAL,
	NOT_EQUAL,
	GREATER_THAN,
	LESS_THAN,
	GREATER_THAN_OR_EQUAL,
	LESS_THAN_OR_EQUAL,
}

var left: GDSQLQueryExpression
var operator: ComparisonOperator
var right: GDSQLQueryExpression


func _init(
		_left: GDSQLQueryExpression = null,
		_operator: ComparisonOperator = ComparisonOperator.EQUAL,
		_right: GDSQLQueryExpression = null,
) -> void:
	left = _left
	operator = _operator
	right = _right


func accept(visitor: GDSQLExpressionVisitor) -> Variant:
	return visitor.visit_comparison(self)
