class_name GDSQLColumnAssignment
extends RefCounted

var column: StringName
var expression: GDSQLQueryExpression


func _init(
		column: StringName = &"",
		expression: GDSQLQueryExpression = null,
) -> void:
	self.column = column
	self.expression = expression
