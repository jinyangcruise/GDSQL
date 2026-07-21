class_name GDSQLJoinSpec
extends RefCounted

enum JoinType { INNER, LEFT, RIGHT, FULL }

var type: JoinType
var source: GDSQLQuerySource
var condition: GDSQLQueryExpression


func _init(
		type: JoinType = JoinType.INNER,
		source: GDSQLQuerySource = null,
		condition: GDSQLQueryExpression = null,
) -> void:
	self.type = type
	self.source = source
	self.condition = condition
