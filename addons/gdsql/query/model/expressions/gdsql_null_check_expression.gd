class_name GDSQLNullCheckExpression
extends GDSQLQueryExpression

enum NullCheckOperator {
	IS_NULL,
	IS_NOT_NULL,
}

var operand: GDSQLQueryExpression
var operator: NullCheckOperator


func _init(
		operand: GDSQLQueryExpression = null,
		operator: NullCheckOperator = NullCheckOperator.IS_NULL,
) -> void:
	self.operand = operand
	self.operator = operator


func accept(visitor: GDSQLExpressionVisitor) -> Variant:
	return visitor.visit_null_check(self)
