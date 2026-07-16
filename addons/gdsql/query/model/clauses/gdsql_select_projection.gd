class_name GDSQLSelectProjection
extends RefCounted

var expression: GDSQLQueryExpression
var alias: StringName


func _init(
		expression: GDSQLQueryExpression = null,
		alias: StringName = &"",
) -> void:
	self.expression = expression
	self.alias = alias
