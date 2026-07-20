class_name GDSQLLiteralExpression
extends GDSQLQueryExpression

var value: Variant


func _init(value: Variant = null) -> void:
	self.value = value


func accept(visitor: GDSQLExpressionVisitor) -> Variant:
	return visitor.visit_literal(self)
