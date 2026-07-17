class_name GDSQLOrderClause
extends RefCounted

enum SortDirection { ASCENDING, DESCENDING }

var expression: GDSQLQueryExpression
var direction: SortDirection = SortDirection.ASCENDING


func _init(
		expression: GDSQLQueryExpression = null,
		direction: SortDirection = SortDirection.ASCENDING,
) -> void:
	self.expression = expression
	self.direction = direction
