class_name GDSQLArithmeticExpression
extends GDSQLQueryExpression

enum ArithmeticOperator {
	ADD,
	SUBTRACT,
	MULTIPLY,
	DIVIDE,
	MODULO,
}

var left: GDSQLQueryExpression
var operator: ArithmeticOperator
var right: GDSQLQueryExpression


func _init(
		_left: GDSQLQueryExpression = null,
		_operator: ArithmeticOperator = ArithmeticOperator.ADD,
		_right: GDSQLQueryExpression = null,
) -> void:
	left = _left
	operator = _operator
	right = _right


func accept(visitor: GDSQLExpressionVisitor) -> Variant:
	return visitor.visit_arithmetic(self)
