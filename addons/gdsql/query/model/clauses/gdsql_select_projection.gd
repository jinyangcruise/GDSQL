class_name GDSQLSelectProjection
extends RefCounted

var expression: GDSQLQueryExpression
var alias: StringName


func _init(
		_expression: GDSQLQueryExpression = null,
		_alias: StringName = &"",
) -> void:
	expression = _expression
	alias = _alias
