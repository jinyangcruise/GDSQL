@tool
extends RefCounted
class_name  GBatisId

var column: String
var property: String
var java_type: String

func _init(conf: Dictionary) -> void:
	column = conf.get("column", "").strip_edges()
	property = conf.get("property", "").strip_edges()
	java_type = conf.get("javaType", "").strip_edges()
