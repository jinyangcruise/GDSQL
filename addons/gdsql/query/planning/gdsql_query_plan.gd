class_name GDSQLQueryPlan
extends RefCounted

var root: GDSQLPlanNode


func _init(p_root: GDSQLPlanNode = null) -> void:
	root = p_root
