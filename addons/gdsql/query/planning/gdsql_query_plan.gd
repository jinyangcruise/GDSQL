class_name GDSQLQueryPlan
extends RefCounted

var root: GDSQLPlanNode
var requires_concrete_resources := false


func _init(_root: GDSQLPlanNode = null) -> void:
	root = _root
