@tool
extends RefCounted
class_name GBatisSelect

var id = ""
var result_map = ""
## NOTICE 如果resultType和resultMap都是空的，则按照用户调用的方法的返回值的定义来进行返回
var result_type = "" # 表示一条数据的映射数据类型。NOTICE 一条数据的。
#var fetch_size = ""
var flush_cache = true
var use_cache = true
var database_id = ""

var sql = "": set = set_sql
# NONE or PARTIAL or FULL
var auto_mapping_level = "PARTIAL": set = set_auto_mapping_level 
# ALWAYS_ARRAY or ARRAY_WHEN_NECESSARY
var return_type_undefined_behavior = "ALWAYS_ARRAY": set = set_return_type_undefined_behavior
var method_return_info: Dictionary: set = set_method_return_info

## ----------------- 内部使用 ------------------
var object_class_name: String
var columns: Array # 数据集的列名数组
var prop_map: Dictionary # 对象的属性列表，用name作为key
var object_prop_map: Dictionary # 属性列表，该属性是子对象，可能涉及Nested Result Mapping
var prop_type: Dictionary # column和prop不一定完全相同，比如可能有冒号，比如大小写、下划线、驼峰格式不同
# prop_type[column] = {
#    "exist": true, # 这列数据是否是obj中的属性
#    "prop": prop, # 这列数据对应的属性名称
#    "column_type": TYPE_XX, # 这列数据的数据类型。
#    "method": "" # 填充时用type_convert还是str_to_var转化数据
# }
var pk_index: Dictionary # 主键的可能索引
var pk_confirm: Array = [-1] # 主键确认的索引
var pk_obj: Dictionary # 用主键关联obj

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
	
func set_sql(p_sql: String):
	sql = p_sql
	reset()
	
func set_auto_mapping_level(type: String):
	auto_mapping_level = type
	
func set_method_return_info(info: Dictionary):
	method_return_info = info
	
func set_return_type_undefined_behavior(type: String):
	return_type_undefined_behavior = type
	
func reset():
	object_class_name = ""
	columns.clear()
	prop_map.clear()
	object_prop_map.clear()
	prop_type.clear()
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
		assert(result_type == mapping_to_type or mapping_to_type.is_empty(), 
			"resultType `%s` not match your method type `%s`." % \
			[result_type, mapping_to_type])
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
	
	# 准备columns和pk_index
	# columns: Array # 数据集的列名数组
	# pk_index: Dictionary # 主键的可能索引
	var succ = _prepare_columns_pk_index(head)
	assert(succ, "Error occur in _prepare_columns_pk_index().")
	
	# xml不配置mapping类型，调用函数只定义要返回数组，但不指定数组元素的数据类型，那么返回raw datas
	if result_type.is_empty() and result_map.is_empty() and mapping_to_type.is_empty():
		if return_type_undefined_behavior == "ALWAYS_ARRAY":
			return datas
		elif datas.size() == 1: # ARRAY_WHEN_NECESSARY
			return datas[0]
		else:
			return datas
			
	# 定义了每条数据映射到的数据类型
	if not result_type.is_empty():
		# 每条数据映射到对象
		if mapping_to_object:
			return _deal_mapping_to_object(return_type, datas)
		# 每条数据映射到数组
		elif result_type == "Array":
			return _deal_mapping_to_array(return_type, datas)
		# 每条数据映射到字典
		elif result_type == "Dictionary":
			return _deal_mapping_to_dictionary(return_type, datas)
		# 每条数据映射到其他类型比如int， String 或 [int|String|...]
		else:
			# 是否是1个字段，也不能是0，因为像int, String这样的返回值，应该要返回1个。
			assert(head.size() == 1, 
				"Result set is supposed to have one column, but %d." % \
				head.size())
			return _deal_mapping_to_other(return_type, datas)
			
	# 定义了每条数据映射到resultMap
	if not result_map.is_empty():
		pass
	
func _deal_mapping_to_object(return_type: String, datas: Array):
	assert(auto_mapping_level != "NONE", 
		"Cannot mapping data to %s because auto_mapping_level is NONE" \
		% object_class_name)
		
	# obj的属性列表及其类型，缓存到这个变量中
	var model_obj = GDSQLUtils.evaluate_command(null, 
		"%s.new()" % object_class_name) as Object
	assert(is_instance_valid(model_obj), 
		"Cannot initialize this class %s" % object_class_name)
		
	# 准备 prop_map object_prop_map
	# prop_map: Dictionary # 对象的属性列表，用name作为key
	# object_prop_map: Dictionary # 属性列表，该属性是子对象
	var list = (model_obj as Object).get_property_list()
	_prepare_prop_map_object_prop_map(list)
	
	if return_type == "Undefined":
		if return_type_undefined_behavior == "ALWAYS_ARRAY":
			return_type = "Array"
		elif datas.size() == 1: # ARRAY_WHEN_NECESSARY
			return_type = "Object"
		else:
			return_type = "Object" if datas.size() == 1 else "Array"
			
	if return_type == "Array":
		# model_obj用不上了，及时释放
		_free_obj(model_obj)
		var ret_datas = _gen_array()
		for data in datas:
			var obj = _get_obj_or_generate(data)
			assert(obj != null, "Error occur in _get_obj_or_generate().")
			if obj.has_meta("new"):
				obj.remove_meta("new")
				ret_datas.push_back(obj)
			# PARTIAL时，只填充obj的简单属性（非object的属性）,由于已经填充
			# 过了，所以跳过这条数据。（这条多余的数据之所以被查询出来，是由于
			# 联表查询出来的子对象的数据之间的不同导致的，然而在PARTIAL模式下，
			# 不对子对象进行填充）
			# INFO 实际上运行到这里一定是true，因为目前只支持NONE和PARTIAL，
			# 而NONE的情况在前面就拦截了。
			elif auto_mapping_level == "PARTIAL":
				continue
				
			# 把字段值映射到对象的属性内
			_automapping_obejct(data, obj)
		return ret_datas
	elif return_type == "Object":
		assert(not datas.is_empty(), 
			"Cannot mapping to %s because no data." % object_class_name)
			
		var obj = _get_obj_or_generate(datas[0])
		obj.remove_meta("new")
		_automapping_obejct(datas[0], obj)
		# 如果主键都没确认，那肯定会造成将返回多个Object
		var msg = "Result set mapped to multiple Object but your method just need one."
		assert(pk_confirm[0] != -1 or datas.size() == 1, msg)
			
		# 确保每条数据对应的obj都是上面的obj
		for data in datas:
			assert(_obj_exist(data), msg)
		return obj
		
func _deal_mapping_to_array(return_type: String, datas: Array):
	var ret_datas = _gen_array()
	
	if return_type == "Undefined":
		if return_type_undefined_behavior == "ALWAYS_ARRAY":
			return_type = "Array"
		elif datas.size() == 1: # ARRAY_WHEN_NECESSARY
			return_type = ""
		else:
			return_type = "" if datas.size() == 1 else "Array"
		
	if return_type == "Array":
		ret_datas.assign(datas)
		return datas
	# 没查询到数据，则返回空数组
	if datas.is_empty():
		return ret_datas
	ret_datas.assign(datas[0])
	return ret_datas
	
func _deal_mapping_to_dictionary(return_type: String, datas: Array):
	if return_type == "Undefined":
		if return_type_undefined_behavior == "ALWAYS_ARRAY":
			return_type = "Array"
		elif datas.size() == 1: # ARRAY_WHEN_NECESSARY
			return_type = "Dictionary"
		else:
			return_type = "Dictionary" if datas.size() == 1 else "Array"
			
	if return_type == "Array":
		var ret_datas = _gen_array()
		for data in datas:
			var a_map = _automapping_dictionary(data)
			assert(a_map != null, "Error occur in _automapping_dictionary().")
			ret_datas.push_back(a_map)
		return ret_datas
		
	# 没查询到数据，则返回空字典，连键都不设置
	if datas.is_empty():
		return {}
		
	assert(datas.size() == 1, "Result set size() != 1.")
	var map = _automapping_dictionary(datas[0])
	assert(map != null, "Error occur in _automapping_dictionary().")
	return map
	
func _deal_mapping_to_other(return_type: String, datas: Array):
	var to_type = 0
	if DataTypeDef.RESOURCE_TYPE_NAMES.has(result_type):
		to_type = TYPE_OBJECT
	else:
		to_type = DataTypeDef.DATA_TYPE_COMMON_NAMES[result_type]
		
	# 需要返回数组
	var use_origin = false
	var use_str_to_val = false
	if datas.size() > 0:
		if typeof(datas[0][0]) == to_type:
			use_origin = true
		if not use_origin:
			if datas[0][0] is String and typeof(str_to_var(datas[0][0])) == to_type:
				use_str_to_val = true
			
	if return_type == "Undefined":
		if return_type_undefined_behavior == "ALWAYS_ARRAY":
			return_type = "Array"
		elif datas.size() == 1: # ARRAY_WHEN_NECESSARY
			return_type = "OTHER"
		else:
			return_type = "OTHER" if datas.size() == 1 else "Array"
			
	if return_type == "Array":
		var ret_datas = _gen_array()
		for i in datas:
			if use_origin:
				ret_datas.push_back(i[0])
			elif use_str_to_val:
				ret_datas.push_back(str_to_var(i[0]))
			else:
				ret_datas.push_back(type_convert(i[0], to_type))
		return ret_datas
		
	assert(datas.size() == 1, "Result set size() != 1.")
	if use_origin:
		return datas[0][0]
	elif use_str_to_val:
		return str_to_var(datas[0][0])
	return type_convert(datas[0][0], to_type)
	
## 准备columns和pk_index
## columns: Array # 数据集的列名数组
## pk_index: Dictionary # 主键的可能索引
func _prepare_columns_pk_index(head: Array) -> bool:
	for j in head.size():
		var column = head[j]["field_as"]
		assert(not columns.has(column), 
			"Duplicated column name `%s`." % column)
		if head[j]["PK"] and not pk_index.values().has(column):
			pk_index[j] = column
		columns.push_back(column)
	return true
	
## 准备 prop_map object_prop_map
## prop_map: Dictionary # 对象的属性列表，用name作为key
## object_prop_map: Dictionary # 属性列表，该属性是子对象
func _prepare_prop_map_object_prop_map(property_list: Array):
	for i in property_list:
		prop_map[i.name] = i
		if not i.class_name.is_empty():
			object_prop_map[i.name] = i
			
## 每个主键只允许返回一个对应的对象。如果主键不存在，那就每条数据都返回
## 一个对象，这也是允许的。
func _get_obj_or_generate(data: Array) -> Object:
	var obj = null
	# 每个主键只允许返回一个对应的对象。如果主键不存在，那就每条数据都返回
	# 一个对象，这也是允许的。
	if pk_confirm[0] != -1:
		obj = pk_obj.get(data[pk_confirm[0]], null)
	if obj == null:
		obj = GDSQLUtils.evaluate_command(null, "%s.new()" % object_class_name)
		if obj:
			obj.set_meta("new", true) # 临时存储，使用者使用完毕要删除
	return obj
	
## 判断data对应的obj是否存在
func _obj_exist(data: Array) -> bool:
	return pk_confirm[0] != -1 and pk_obj.has(data[pk_confirm[0]])
	
## columns: Array # 数据集的列名数组
## prop_map: Dictionary # 对象的属性列表，用name作为key
## object_prop_map: Dictionary # 属性列表，该属性是子对象，可能涉及Nested Result Mapping
## prop_type: Dictionary # column和prop不一定完全相同，比如可能有冒号，比如大小写、下划线、驼峰格式不同
## prop_type[column] = {
##     # 这列数据是否是obj中的属性
##     "exist": true,
##     # 这列数据对应的属性名称
##     "prop": prop,
##     # 这列数据的数据类型。
##     "column_type": TYPE_XX,
##     ##填充时用type_convert还是str_to_var转化数据
##     "method": ""
## }
## data: 一条数据
## pk_index: Dictionary # 主键的可能索引
## pk_confirm: Array # 主键确认的索引
## pk_obj: Dictionary # 用主键关联obj
## 
func _automapping_obejct(data: Array, obj: Object) -> Object:
	for j in columns.size():
		var column = columns[j] as String
		if prop_type.has(column) and not prop_type[column]["exist"]:
			continue
			
		var prop = ""
		var type = TYPE_NIL
		var prop_is_object = false
		if prop_type.has(column):
			prop = prop_type[column]["prop"]
			type = prop_map[prop].type
			prop_is_object = _is_prop_an_object(prop_map[prop])
		else:
			# 如果要写成属性冒号的形式，那第一部分肯定需要写成原本形式才行，
			# 不需要判断大小写，蛇形，驼峰之类的。
			if column.contains(":"):
				if not column.get_slice(":", 0) in obj:
					prop_type[column] = {"exist":false}
					continue
					
			# 根据列名找对应的属性名
			var column_1 = column.get_slice(":", 0)
			prop = _get_similar_prop(column_1)
			if prop.is_empty():
				prop_type[column] = {"exist":false}
				continue
				
			type = prop_map[prop].type
			prop_is_object = _is_prop_an_object(prop_map[prop])
			prop_type[column] = {
				# 这列数据是否是obj中的属性
				"exist": true,
				# 这列数据对应的属性名称
				"prop": prop,
				# 这列数据的数据类型。
				# NOTICE 带冒号的如果用户拼写错误会导致报错。而我们目前
				# 没有什么好办法提前检测。
				"column_type": type if column_1 == column else \
					typeof(obj.get_indexed(column)),
				# 填充时用type_convert还是str_to_var转化数据
				"method": ""
			}
			
		# PARTIAL时，只填充obj的简单属性（非object的属性）
		if auto_mapping_level == "PARTIAL" and prop_is_object:
			continue
			
		# Nil或二者数据类型相同，直接赋值
		var column_type = prop_type[column]["column_type"]
		if type == TYPE_NIL or typeof(data[j]) == column_type:
			if column.contains(":"):
				obj.set_indexed(column, data[j]) # 支持":"的属性路径，比如"pos:x"
			else:
				obj.set_indexed(prop, data[j])
		else:
			# NOTICE type_convert并不是万能的，依赖于引擎
			# 底层数据格式的相互转换。例如：
			# type_convert("Vector2(1, 1)", Vector2) 并不会得到
			# Vector2(1, 1)，而是得到Vector2(0, 0)。
			# 先测试type_convert是否正确
			var value = null
			var value_set = false
			if prop_type[column]["method"].is_empty():
				if typeof(data[j]) == column_type:
					prop_type[column]["method"] = "none"
				elif data[j] is String:
					value = str_to_var(data[j])
					value_set = true
					if typeof(value) == column_type:
						prop_type[column]["method"] = "str_to_var"
					else:
						prop_type[column]["method"] = "type_convert"
			match prop_type[column]["method"]:
				"none":
					obj.set_indexed(prop, data[j])
				"str_to_var":
					obj.set_indexed(prop, 
						value if value_set else str_to_var(data[j]))
				"type_convert":
					obj.set_indexed(prop, 
						type_convert(data[j], column_type))
				_:
					assert(false, "Inner error 103.")
		# 主键
		if pk_index.has(j):
			if pk_confirm[0] == -1:
				pk_confirm[0] = j
			# 已经找到一个了，怎么又冒出来一个
			assert(pk_confirm[0] == j, 
				"Multiple primary keys [%s, %s] are mapped to %s." % \
				[pk_confirm[0], j, object_class_name])
			pk_obj[data[j]] = obj
			
		if auto_mapping_level == "FULL":
			assert(false, "Not support auto mapping level == 'FULL'")
	return obj
	
func _automapping_dictionary(data: Array) -> Dictionary:
	var map = {}
	for j in columns:
		var column = columns[j]
		assert(not map.has(column), "Duplicated column name `%s`." % column)
		map[column] = data[j]
	return map
	
func _get_similar_prop(column_1: String):
	var prop = ""
	if prop_map.has(column_1):
		prop = column_1
	elif prop_map.has(column_1.to_lower()):
		prop = column_1.to_lower()
	elif prop_map.has(column_1.to_upper()):
		prop = column_1.to_upper()
	else:
		var snake = column_1.to_snake_case()
		if prop_map.has(snake):
			prop = snake
		elif prop_map.has(snake.to_upper()):
			prop = snake.to_upper()
		else:
			var camel = column_1.to_camel_case()
			if prop_map.has(camel):
				prop = camel
			elif prop_map.has(camel.to_lower()):
				prop = camel.to_lower()
			elif prop_map.has(camel.to_upper()):
				prop = camel.to_upper()
			elif prop_map.has(camel[0].to_upper() + camel.substr(1)):
				prop = camel[0].to_upper() + camel.substr(1)
	return prop
	
func _free_obj(obj: Object):
	if not obj is RefCounted:
		obj.free()
		
func _is_prop_an_object(property_info: Dictionary):
	return property_info.type == TYPE_OBJECT and \
		not DataTypeDef.RESOURCE_TYPE_NAMES.has(property_info.class_name)
		
func _gen_array():
	if method_return_info.hint == PROPERTY_HINT_ARRAY_TYPE:
		# 不能使用evaluate_command，原因是Expression虽然成功返回但并不是typed array
		return GDSQLUtils.evaluate_command_script(
			"[] as Array[%s]" % method_return_info.hint_string)
	return []
