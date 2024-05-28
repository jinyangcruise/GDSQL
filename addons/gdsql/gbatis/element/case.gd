@tool
extends RefCounted
class_name GBatisCase
#<!ELEMENT case (constructor?,id*,result*,association*,collection*, discriminator?)>
#<!ATTLIST case
#value CDATA #REQUIRED
#resultMap CDATA #IMPLIED
#resultType CDATA #IMPLIED
#>

var value
var result_map: String
var result_type: String
var result_embeded: GBatisResultMap

func _init(conf: Dictionary) -> void:
	value = conf.get("value")
	result_map = conf.get("resultMap", "").strip_edges()
	result_type = conf.get("resultType", "").strip_edges()
	assert(result_map.is_empty() or result_type.is_empty(), 
		"Cannot set resultMap and resultType at the same time in <case>.")
	if not result_type.is_empty():
		# result_type必须是一个对象的className
		assert(not DataTypeDef.DATA_TYPE_COMMON_NAMES.has(result_type) and \
		not DataTypeDef.RESOURCE_TYPE_NAMES.has(result_type),
		"Attr resultType %s in <case> should be an Object's class_name" % result_type)
		
	
func push_element(element):
	if not result_embeded:
		result_embeded = GBatisResultMap.new({})
	result_embeded.push_back(element)
	
func get_return_type() -> String:
	# 递归找到返回的对象的类名
	return ""
	
func get_
	
func prepare_deal(head: Array, data: Array):
	pass
	
func deal(head: Array, data: Array):
	pass
