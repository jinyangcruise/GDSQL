@tool
extends RefCounted

#<!ELEMENT case (constructor?,id*,result*,association*,collection*, discriminator?)>
#<!ATTLIST case
#value CDATA #REQUIRED
#resultMap CDATA #IMPLIED
#resultType CDATA #IMPLIED
#>

var value
var result_map: String
var result_type: String
var result_embeded: GDSQL.GBatisResultMap
var mapper_parser_ref: WeakRef: set = set_mapper_parser_ref

# --------- 内部使用 ----------
var _result_map: GDSQL.GBatisResultMap # 把case当作一个resultMap来用
var head: Array

func _init(conf: Dictionary) -> void:
	value = conf.get("value")
	result_map = conf.get("resultMap", "").strip_edges()
	result_type = conf.get("resultType", "").strip_edges()
	assert(result_map.is_empty() or result_type.is_empty(), 
		"Cannot set resultMap and resultType at the same time in <case>.")
	if not result_type.is_empty():
		# result_type必须是一个对象的className
		assert(not GDSQL.DataTypeDef.DATA_TYPE_COMMON_NAMES.has(result_type) and
			not ClassDB.is_parent_class(result_type, &"Resource"),
			"Attr resultType %s in <case> should be an Object's class_name" % result_type)
			
func set_mapper_parser_ref(mapper_parser):
	mapper_parser_ref = mapper_parser
	
func clean():
	mapper_parser_ref = null
	head.clear()
	if _result_map:
		_result_map.clean()
		_result_map = null
	elif result_embeded:
		result_embeded.clean()
		result_embeded = null
	
func push_element(element):
	if not result_embeded:
		result_embeded = GDSQL.GBatisResultMap.new({"type": result_type})
		result_embeded.set_mapper_parser_ref(mapper_parser_ref)
	result_embeded.push_element(element)
	
func get_result_type():
	if _result_map == null:
		assert(false, "Call parent node <discriminator>'s prepare_deal() first!")
		return null
	# 递归找到返回的对象的类名
	return _result_map.get_deepest_result_type()
	
func get_auto_mapping():
	if _result_map == null:
		assert(false, "Call parent node <discriminator>'s prepare_deal() first!")
		return null
	return _result_map.get_deepest_auto_mapping()
	
#func get_result_map() -> GDSQL.GBatisResultMap:
	#assert(_result_map != null, "Call parent node <discriminator>'s prepare_deal() first!")
	## 递归找到返回的resultMap
	#return _result_map.get_deepest_result_map()
	
func get_prop_column():
	if _result_map == null:
		assert(false, "Call parent node <discriminator>'s prepare_deal() first!")
		return null
	return _result_map.get_deepest_prop_column()
	
func get_associations():
	if _result_map == null:
		assert(false, "Call parent node <discriminator>'s prepare_deal() first!")
		return null
	return _result_map.get_deepest_associations()
	
func get_collections():
	if _result_map == null:
		assert(false, "Call parent node <discriminator>'s prepare_deal() first!")
		return null
	return _result_map.get_deepest_collections()
	
## 是否用了result_map属性而不是result_type属性。
func is_result_map() -> bool:
	return not result_map.is_empty()
	
func check_head(p_head: Array):
	head = p_head
	
## 每处理一条数据需要调用一下
func prepare_deal(data: Array):
	if _result_map != null:
		return
		
	_result_map = result_embeded
	if _result_map == null:
		if not result_map.is_empty():
			_result_map = mapper_parser_ref.get_ref().get_element(result_map)
			if _result_map == null:
				assert(false, "Not found <resultMap> of id %s" % result_map)
				return null
			if not _result_map is GDSQL.GBatisResultMap:
				assert(false, "Not found <resultMap> of id %s" % result_map)
				return null
		else:
			_result_map = GDSQL.GBatisResultMap.new({"type": result_type})
			_result_map.set_mapper_parser_ref(mapper_parser_ref)
			
	_result_map.check_head(head)
	_result_map.prepare_deal(data)
	
## 每处理一条数据后需要调用一下
func reset():
	if _result_map == null:
		assert(false, "Call parent node <discriminator>'s prepare_deal() first!")
		return null
	# 如果有鉴别器，则返回值不稳定，需要重置
	if _result_map.discriminator != null:
		_result_map.reset()
		_result_map = null
	
