@tool
extends RefCounted
class_name GBatisCase

var value
var result_map: String
var result_type: String
var result_embeded: GBatisResultMap

func _init(conf: Dictionary) -> void:
	value = conf.get("value")
	result_map = conf.get("resultMap", "").strip_edges()
	result_type = conf.get("resultType", "").strip_edges()
	
func push_element(element):
	if not result_embeded:
		result_embeded = GBatisResultMap.new({})
	result_embeded.push_back(element)
