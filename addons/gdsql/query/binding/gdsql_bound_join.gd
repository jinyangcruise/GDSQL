class_name GDSQLBoundJoin
extends RefCounted

var type: GDSQLJoinSpec.JoinType
var source: GDSQLBoundTableSource
var condition: GDSQLQueryExpression


func _init(
		_type: GDSQLJoinSpec.JoinType = GDSQLJoinSpec.JoinType.INNER,
		_source: GDSQLBoundTableSource = null,
		_condition: GDSQLQueryExpression = null,
) -> void:
	type = _type
	source = _source
	condition = _condition
