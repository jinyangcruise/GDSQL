class_name GDSQLQueryPlan
extends RefCounted

var root: GDSQLPlanNode


func _init(root: GDSQLPlanNode = null) -> void:
	self.root = root
