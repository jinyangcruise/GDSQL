class_name GDSQLLiteralExpression
extends GDSQLQueryExpression

var value: Variant


func _init(_value: Variant = null) -> void:
	value = _value


func accept(visitor: GDSQLExpressionVisitor) -> Variant:
	return visitor.visit_literal(self)
