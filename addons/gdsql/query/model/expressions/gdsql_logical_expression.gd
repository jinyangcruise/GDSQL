class_name GDSQLLogicalExpression
extends GDSQLQueryExpression

enum LogicalOperator { AND, OR, NOT }

var left: GDSQLQueryExpression
var operator: LogicalOperator
var right: GDSQLQueryExpression


func _init(
		_left: GDSQLQueryExpression = null,
		_operator: LogicalOperator = LogicalOperator.AND,
		_right: GDSQLQueryExpression = null,
) -> void:
	left = _left
	operator = _operator
	right = _right


func accept(visitor: GDSQLExpressionVisitor) -> Variant:
	return visitor.visit_logical(self)
