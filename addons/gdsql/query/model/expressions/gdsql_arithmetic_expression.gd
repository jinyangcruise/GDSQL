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
		left: GDSQLQueryExpression = null,
		operator: ArithmeticOperator = ArithmeticOperator.ADD,
		right: GDSQLQueryExpression = null,
) -> void:
	self.left = left
	self.operator = operator
	self.right = right


func accept(visitor: GDSQLExpressionVisitor) -> Variant:
	return visitor.visit_arithmetic(self)
