class_name GDSQLColumnAssignment
extends RefCounted

var column: StringName
var expression: GDSQLQueryExpression


func _init(
		_column: StringName = &"",
		_expression: GDSQLQueryExpression = null,
) -> void:
	column = _column
	expression = _expression
