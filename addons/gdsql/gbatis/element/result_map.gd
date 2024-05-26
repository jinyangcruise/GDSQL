@tool
extends RefCounted
class_name  GBatisResultMap

var id: String
var type: String
var _extends: String
var auto_mapping: String

var result_embeded: Array

func _init(conf: Dictionary) -> void:
	id = conf.get("id", "").strip_edges()
	type = conf.get("type", "").strip_edges()
	_extends = conf.get("extends", "").strip_edges()
	auto_mapping = conf.get("autoMapping", "").strip_edges()
	
func push_element(element):
	result_embeded.push_back(element)
