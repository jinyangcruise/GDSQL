class_name GDSQLLogicalExpression
extends GDSQLQueryExpression

enum LogicalOperator { AND, OR, NOT }

var left: GDSQLQueryExpression
var operator: LogicalOperator
var right: GDSQLQueryExpression


func _init(
		left: GDSQLQueryExpression = null,
		operator: LogicalOperator = LogicalOperator.AND,
		right: GDSQLQueryExpression = null,
) -> void:
	self.left = left
	self.operator = operator
	self.right = right


func accept(visitor: GDSQLExpressionVisitor) -> Variant:
	return visitor.visit_logical(self)
