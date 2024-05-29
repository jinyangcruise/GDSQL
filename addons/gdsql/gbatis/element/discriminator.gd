@tool
extends RefCounted
class_name GBatisDiscriminator
#<!ELEMENT discriminator (case+)>
#<!ATTLIST discriminator
#column CDATA #REQUIRED
#javaType CDATA #REQUIRED ------- gdscript simple variant type. 
#                                 eg. int, String, bool
#jdbcType CDATA #IMPLIED -------- ❌ not support
#typeHandler CDATA #IMPLIED ----- ❌ not support
#> 

var column: String
var java_type: String
var cases: Array

# --------- 内部使用 -----------
var selected_case_index: int = -2

func _init(conf: Dictionary) -> void:
	column = conf.get("column").strip_edges()
	java_type = conf.get("javaType").strip_edges()
	assert(DataTypeDef.DATA_TYPE_COMMON_NAMES.has(java_type), 
		"Invalid javaType %s in <discriminator>" % java_type)
		
func push_element(case: GBatisCase):
	cases.push_back(case)
	
# 每处理一条数据需要调用一下
func prepare_deal(head: Array, data: Array):
	if selected_case_index != -2:
		return
		
	var column_value = null
	var type = DataTypeDef.DATA_TYPE_COMMON_NAMES.keys().find(java_type)
	var find = false
	for i in head.size():
		if head[i]["field_as"] == column:
			column_value = type_convert(data[i], type)
			find = true
			break
	assert(find, "Not found column %s in Result set. Defined in <discriminator>." % column)
	
	var index = -1
	for i: GBatisCase in cases:
		index += 1
		if column_value == type_convert(i.value, type):
			i.prepare_deal(head, data)
			break
	selected_case_index = index
	
func get_selected_case_return_type():
	assert(selected_case_index != -2, "Call prepare_deal first!")
	if selected_case_index > -1:
		return (cases[selected_case_index] as GBatisCase).get_return_type()
	return ""
	
#func get_result_map() -> GBatisResultMap:
	#assert(selected_case_index != -2, "Call prepare_deal first!")
	#if selected_case_index > -1:
		#return (cases[selected_case_index] as GBatisCase).get_result_map()
	#return null
	
func get_result_type() -> String:
	assert(selected_case_index != -2, "Call prepare_deal first!")
	if selected_case_index > -1:
		return (cases[selected_case_index] as GBatisCase).get_result_type()
	return ""
	
func get_auto_mapping() -> String:
	assert(selected_case_index != -2, "Call prepare_deal first!")
	if selected_case_index > -1:
		return (cases[selected_case_index] as GBatisCase).get_auto_mapping()
	return ""
	
func get_prop_column() -> Dictionary:
	assert(selected_case_index != -2, "Call prepare_deal first!")
	if selected_case_index > -1:
		return (cases[selected_case_index] as GBatisCase).get_prop_column()
	return {}
	
func get_associations() -> Array:
	assert(selected_case_index != -2, "Call prepare_deal first!")
	if selected_case_index > -1:
		return (cases[selected_case_index] as GBatisCase).get_associations()
	return []
	
func get_collections() -> Array:
	assert(selected_case_index != -2, "Call prepare_deal first!")
	if selected_case_index > -1:
		return (cases[selected_case_index] as GBatisCase).get_collections()
	return []
	
## 处理完一条数据后，要reset
func reset():
	assert(selected_case_index != -2, "Call prepare_deal first!")
	if selected_case_index > -1:
		return (cases[selected_case_index] as GBatisCase).reset()
	selected_case_index = -2
	
