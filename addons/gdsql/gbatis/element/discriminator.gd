@tool
extends RefCounted
class_name GBatisDiscriminator

var column: String
var java_type: String
var cases: Array

func _init(conf: Dictionary) -> void:
	column = conf.get("column").strip_edges()
	java_type = conf.get("javaType").strip_edges()
	
func push_element(case: GBatisCase):
	cases.push_back(case)
