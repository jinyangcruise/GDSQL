class_name GDSQLJoinSpec
extends RefCounted

enum JoinType { INNER, LEFT, RIGHT, FULL }

var type: JoinType
var source: GDSQLQuerySource
var condition: GDSQLQueryExpression


func _init(
		_type: JoinType = JoinType.INNER,
		_source: GDSQLQuerySource = null,
		_condition: GDSQLQueryExpression = null,
) -> void:
	type = _type
	source = _source
	condition = _condition
