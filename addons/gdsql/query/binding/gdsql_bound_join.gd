class_name GDSQLBoundJoin
extends RefCounted

var type: GDSQLJoinSpec.JoinType
var source: GDSQLBoundTableSource
var condition: GDSQLQueryExpression


func _init(
		type: GDSQLJoinSpec.JoinType = GDSQLJoinSpec.JoinType.INNER,
		source: GDSQLBoundTableSource = null,
		condition: GDSQLQueryExpression = null,
) -> void:
	self.type = type
	self.source = source
	self.condition = condition
