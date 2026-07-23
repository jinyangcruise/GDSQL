class_name GDSQLQueryPlan
extends RefCounted

var root: GDSQLPlanNode


func _init(_root: GDSQLPlanNode = null) -> void:
	root = _root
