class_name GDSQLOrderClause
extends RefCounted

enum SortDirection { ASCENDING, DESCENDING }

var expression: GDSQLQueryExpression
var direction: SortDirection = SortDirection.ASCENDING


func _init(
		_expression: GDSQLQueryExpression = null,
		_direction: SortDirection = SortDirection.ASCENDING,
) -> void:
	expression = _expression
	direction = _direction
