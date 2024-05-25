@tool
extends RefCounted
class_name GBatisCase

var value
var result_map: GBatisResultMap

func _init(p_value, p_result_map: GBatisResultMap) -> void:
	value = p_value
	result_map = p_result_map
