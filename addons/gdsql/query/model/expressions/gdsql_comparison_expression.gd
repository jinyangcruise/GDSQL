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
		left: GDSQLQueryExpression = null,
		operator: ComparisonOperator = ComparisonOperator.EQUAL,
		right: GDSQLQueryExpression = null,
) -> void:
	self.left = left
	self.operator = operator
	self.right = right


func accept(visitor: GDSQLExpressionVisitor) -> Variant:
	return visitor.visit_comparison(self)
