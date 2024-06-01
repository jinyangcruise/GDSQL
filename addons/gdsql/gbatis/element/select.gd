@tool
extends RefCounted
class_name GBatisSelect
#<!ELEMENT select (#PCDATA | include | trim | where | set | foreach | choose 
#| if | bind)*>
#<!ATTLIST select
#id CDATA #REQUIRED
#parameterMap CDATA #IMPLIED -------- ❌ not support
#parameterType CDATA #IMPLIED ------- ❌ not support
#resultMap CDATA #IMPLIED
#resultType CDATA #IMPLIED
#resultSetType (FORWARD_ONLY | SCROLL_INSENSITIVE | SCROLL_SENSITIVE | DEFAULT) #IMPLIED ❌ not support
#statementType (STATEMENT|PREPARED|CALLABLE) #IMPLIED ❌ not support
#fetchSize CDATA #IMPLIED ----------- ❌ not support
#timeout CDATA #IMPLIED ------------- ❌ not support
#flushCache (true|false) #IMPLIED
#useCache (true|false) #IMPLIED
#databaseId CDATA #IMPLIED
#lang CDATA #IMPLIED ---------------- ❌ not support
#resultOrdered (true|false) #IMPLIED  ❌ not support
#resultSets CDATA #IMPLIED ---------- ❌ not support. Identifies the name of 
#                                        the result set where this complex type 
#                                        will be loaded from. 
#                                        eg. resultSets="blogs,authors"
#>
var id = ""
var result_map = ""
## NOTICE 如果resultType和resultMap都是空的，则按照用户调用的方法的返回值的定义来进行返回
var result_type = "" # 表示一条数据的映射数据类型。NOTICE 一条数据的。
#var fetch_size = ""
var flush_cache = true
var use_cache = true
var database_id = ""

var sql = "": set = set_sql
var method_return_info: Dictionary: set = set_method_return_info
var mapper_parser_ref: WeakRef: set = set_mapper_parser_ref

## ----------------- 内部使用 ------------------
var object_class_name: String
var columns: Array # 数据集的列名数组
var prop_map: Dictionary # 对象的属性列表，用name作为key
var prop_info: Dictionary # column和prop不一定完全相同，比如可能有冒号，比如大小写、下划线、驼峰格式不同
# prop_info[column] = {
#    "exist": true, # 这列数据是否是obj中的属性
#    "prop": prop, # 这列数据对应的属性名称
#    "column_type": TYPE_XX, # 这列数据的数据类型。
#    "method": "" # 填充时用type_convert还是str_to_var转化数据
# }
var pk_index: Dictionary # 主键的可能索引
var pk_confirm: Array = [-1] # 主键确认的索引
var pk_obj: Dictionary # 用主键关联obj
var _result_map: GBatisResultMap # resultType和resultMap统一到这个变量上

func _init(conf: Dictionary) -> void:
	id = conf.get("id").strip_edges()
	result_map = conf.get("resultMap", "").strip_edges()
	result_type = conf.get("resultType", "").strip_edges()
	assert(result_map.is_empty() or result_type.is_empty(), 
		"Cannot set resultMap and resultType at the same time of <select>.")
	#fetch_size = conf.get("fetchSize", "").strip_edges()
	flush_cache = type_convert(conf.get("flushCache", "false").strip_edges(), TYPE_BOOL)
	use_cache = type_convert(conf.get("useCache", "true").strip_edges(), TYPE_BOOL)
	database_id = conf.get("databaseId", "").strip_edges()
	
func clean():
	pass
	
func set_mapper_parser_ref(mapper_parser):
	mapper_parser_ref = mapper_parser
	
func set_sql(p_sql: String):
	sql = p_sql
	reset()
	
func set_method_return_info(info: Dictionary):
	method_return_info = info
	
func reset():
	object_class_name = ""
	columns.clear()
	prop_map.clear()
	prop_info.clear()
	pk_index.clear()
	pk_confirm = [-1]
	pk_obj.clear()
	
func query():
	# cache TODO
	
	var dao = SQLParser.parse_to_dao(sql)
	if not database_id.is_empty():
		dao.use_db_name(database_id)
	var query_result = dao.query()
	assert(query_result != null, "Error occur.")
	assert(query_result.ok(), "Error occur. %s" % query_result.get_err())
	
	# xml指定了返回QueryResult，或mapper中的函数指定返回QueryResult)，那么原样返回
	if result_map.is_empty() and \
	(result_type == "QueryResult" or method_return_info.class_name == "QueryResult"):
		return query_result
		
	# 最终要返回的类型
	var return_type = "" # Object, Array, Dictionary, Other
	# 根据函数返回值推断的automapping的类型
	var mapping_to_type = "" # = type_string(method_return_info.type) # int, String etc.
	var mapping_to_object = false
	
	# 调用函数需要返回一个Object
	if not method_return_info.class_name.is_empty():
		mapping_to_type = method_return_info.class_name
		# Resouce类型的，和用户自定义的Object不能用一种办法处理，反而应该用other的办法
		if DataTypeDef.RESOURCE_TYPE_NAMES.has(method_return_info.class_name):
			return_type = "Other"
		else:
			return_type = "Object"
			object_class_name = mapping_to_type
			mapping_to_object = true
	# 调用函数需要返回一个数组
	elif method_return_info.type == TYPE_ARRAY:
		return_type = "Array"
		mapping_to_type = "" # 不确定
		if method_return_info.hint == PROPERTY_HINT_ARRAY_TYPE:
			mapping_to_type = method_return_info.hint_string # 确定
			if not DataTypeDef.RESOURCE_TYPE_NAMES.has(mapping_to_type) and \
			not DataTypeDef.DATA_TYPE_COMMON_NAMES.has(mapping_to_type):
				mapping_to_object = true
				object_class_name = mapping_to_type
	# 调用函数需要返回一个字典
	elif method_return_info.type == TYPE_DICTIONARY:
		return_type = "Dictionary"
		mapping_to_type = "Dictionary"
	# 调用函数需要返回一个某类型的值
	elif method_return_info.type != TYPE_NIL:
		return_type = "Other"
		mapping_to_type = type_string(method_return_info.type)
	# 调用函数没定义返回值类型
	else:
		# 后面根据resultType和resultMap配置的具体东西来看
		return_type = "Undefined"
		mapping_to_type = ""
		
	# 看配置的result_type（配置的automapping的类型）
	# 和函数返回值推断的automapping的类型是否一致
	if not result_type.is_empty():
		if result_type == mapping_to_type or mapping_to_type == "":
			pass # leave empty
		# 不一致的话，要检查继承关系
		else:
			if DataTypeDef.DATA_TYPE_COMMON_NAMES.has(result_type):
				assert(false, "resultType `%s` not match your method type `%s`." % \
				[result_type, mapping_to_type])
			elif mapping_to_type == "Object":
				pass # leave empty
			elif result_type == "Resource":
				if not (mapping_to_type == "RefCounted" or mapping_to_type == "Object"):
					assert(false, "Resouce dose not inherit from " + mapping_to_type)
			else:
				var o = GDSQLUtils.evaluate_command_script(result_type + ".new()")
				if not o:
					assert(false, "Cannot initialize " + result_type)
				var is_inherit = GDSQLUtils.evaluate_command_script( 
					"o is " + mapping_to_type, ["o"], [o])
				if not is_inherit:
					assert(false, result_type + " dose not inherit from " + mapping_to_type)
		# xml配置了，但是函数返回值没定义。要确认一下xml配置的是不是Object
		if mapping_to_type.is_empty():
			mapping_to_type = result_type
			# 既不是普通数据类型也不是Resource，就当做Object
			if not DataTypeDef.DATA_TYPE_COMMON_NAMES.has(mapping_to_type) and \
			not DataTypeDef.RESOURCE_TYPE_NAMES.has(mapping_to_type):
				mapping_to_object = true
				object_class_name = result_type
				
	# resultType和resultMap都没配置，就用函数返回值推断的类型
	elif result_map.is_empty():
		if method_return_info.type != TYPE_NIL:
			result_type = mapping_to_type
			
	# 原始数据
	var head = query_result.get_head()
	var datas = query_result.get_data()
	
	# xml不配置mapping类型，调用函数不指定返回数据类型，或不指定数组元素的数据类型，那么返回raw datas
	if result_type.is_empty() and result_map.is_empty() and mapping_to_type.is_empty():
		if return_type == "Undefined":
			if mapper_parser_ref.get_ref().return_type_undefined_behavior == "ALWAYS_ARRAY":
				return datas
			elif datas.size() == 1: # ARRAY_WHEN_NECESSARY
				return datas[0]
			else:
				return datas
		elif return_type == "Array":
			return datas
		else:
			assert(false, "Inner error 104.") # 没考虑到的情况
			
	# 用一个resultMap来映射数据
	if not result_map.is_empty():
		_result_map = mapper_parser_ref.get_ref().get_element(result_map)
		assert(_result_map != null, "Not found <resultMap> of id %s" % result_map)
		assert(_result_map is GBatisResultMap, "Not found <resultMap> of id %s" % result_map)
	else:
		_result_map = GBatisResultMap.new({"type": result_type})
		_result_map.set_mapper_parser_ref(mapper_parser_ref)
		
	if return_type == "Undefined":
		if mapper_parser_ref.get_ref().return_type_undefined_behavior == "ALWAYS_ARRAY":
			return_type = "Array"
		elif datas.size() == 1: # ARRAY_WHEN_NECESSARY
			if mapping_to_object:
				return_type = "Object"
			elif result_type == "Array":
				return_type = "OneRow"
			elif result_type == "Dictionary":
				return_type = "Dictionary"
			else:
				return_type = "Other"
		else:
			return_type = "Array"
			
	if return_type == "Array":
		var ret_datas = _gen_array()
		for data in datas:
			_result_map.prepare_deal(head, data)
			var map_to_obj = _result_map.mapping_to_object
			var map_to_array = _result_map.mapping_to_array
			var map_to_dictionary = _result_map.mapping_to_dictionary
			
			var a_ret = _result_map.deal(head, data)
			if not a_ret is Array:
				assert(false, "Err occur in result_map deal().")
			if (map_to_obj or map_to_array or map_to_dictionary) and a_ret[0] == null:
				assert(false, "Err occur in result_map deal().")
				
			a_ret = a_ret[0]
			var push = true
			if a_ret is Object:
				if a_ret.has_meta("new_for_select"):
					a_ret.remove_meta("new_for_select")
				else:
					push = false
			if push:
				ret_datas.push_back(a_ret)
		return ret_datas
	else:
		if datas.is_empty():
			if return_type == "Object":
				return null
			if return_type == "OneRow":
				return []
			if return_type == "Dictionary":
				return {}
			if return_type == "Other":
				if DataTypeDef.RESOURCE_TYPE_NAMES.has(result_type):
					return null
				assert(false, "Result set is supposed to have one row, but 0.")
				
		_result_map.prepare_deal(head, datas[0])
		if return_type == "Object":
			if not _result_map.mapping_to_object:
				assert(false, "resultMap return type not match method return type.")
		elif return_type == "OneRow":
			if not _result_map.mapping_to_array:
				assert(false, "resultMap return type not match method return type.")
		elif return_type == "Dictionary":
			if not _result_map.mapping_to_dictionary:
				assert(false, "resultMap return type not match method return type.")
		elif return_type == "Other":
			if not _result_map.mapping_to_other:
				assert(false, "resultMap return type not match method return type.")
		else:
			assert(false, "Inner error 105.") # 没考虑到的情况
			
		var a_ret = _result_map.deal(head, datas[0])
		if not a_ret is Array:
			assert(false, "Err occur in result_map deal().")
		if a_ret is Object and a_ret.has_meta("new_for_select"):
			a_ret.remove_meta("new_for_select")
		return a_ret[0]
		
func _gen_array():
	if method_return_info.hint == PROPERTY_HINT_ARRAY_TYPE:
		# 不能使用evaluate_command，原因是Expression虽然成功返回但并不是typed array
		return GDSQLUtils.evaluate_command_script(
			"[] as Array[" + method_return_info.hint_string + "]")
	return []
