class_name GDSQLLogicalExpression
extends GDSQLQueryExpression

enum LogicalOperator { AND, OR, NOT }

var left: GDSQLQueryExpression
var operator: LogicalOperator
var right: GDSQLQueryExpression


func _init(
		p_left: GDSQLQueryExpression = null,
		p_operator: LogicalOperator = LogicalOperator.AND,
		p_right: GDSQLQueryExpression = null,
) -> void:
	left = p_left
	operator = p_operator
	right = p_right


func accept(visitor: GDSQLExpressionVisitor) -> Variant:
	return visitor.visit_logical(self)
