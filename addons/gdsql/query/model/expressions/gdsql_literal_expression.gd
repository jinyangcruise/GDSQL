class_name GDSQLLiteralExpression
extends GDSQLQueryExpression

var value: Variant


func _init(p_value: Variant = null) -> void:
	value = p_value


func accept(visitor: GDSQLExpressionVisitor) -> Variant:
	return visitor.visit_literal(self)
