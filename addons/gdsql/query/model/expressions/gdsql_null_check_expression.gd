class_name GDSQLNullCheckExpression
extends GDSQLQueryExpression

enum NullCheckOperator {
	IS_NULL,
	IS_NOT_NULL,
}

var operand: GDSQLQueryExpression
var operator: NullCheckOperator


func _init(
		_operand: GDSQLQueryExpression = null,
		_operator: NullCheckOperator = NullCheckOperator.IS_NULL,
) -> void:
	operand = _operand
	operator = _operator


func accept(visitor: GDSQLExpressionVisitor) -> Variant:
	return visitor.visit_null_check(self)
