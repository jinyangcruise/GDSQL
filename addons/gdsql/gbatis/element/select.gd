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
var sql = ""
var auto_mapping_level = "PARTIAL"
var method_return_info: Dictionary

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
	
func set_auto_mapping_level(type: String):
	auto_mapping_level = type
	
func set_method_return_info(info: Dictionary):
	method_return_info = info
	
func query():
	# cache TODO
	var dao = SQLParser.parse_to_dao(sql)
	if not database_id.is_empty():
		dao.use_db_name(database_id)
	var query_result = dao.query()
	assert(query_result != null, "Error occur.")
	assert(query_result.ok(), "Error occur. %s" % query_result.get_err())
	
	# 对数据进行映射
	# 看用户的调用函数的返回值的类型（有可能没定义）
	var defined_return_type = method_return_info.type != TYPE_NIL
	# 最终要返回的类型
	var return_type = "" # Object, Array, Dictionary, Other
	# 根据函数返回值推断的automapping的类型
	var mapping_to_type = "" # = type_string(method_return_info.type) # int, String etc.
	var mapping_to_object = false
	
	if not method_return_info.class_name.is_empty():
		return_type = "Object"
		mapping_to_type = method_return_info.class_name
		mapping_to_object = true
	elif method_return_info.type == TYPE_ARRAY:
		return_type = "Array"
		mapping_to_type = "" # 不确定
		if method_return_info.hint == PROPERTY_HINT_ARRAY_TYPE:
			mapping_to_type = method_return_info.hint_string
			if not DataTypeDef.DATA_TYPE_COMMON_NAMES.has(mapping_to_object):
				mapping_to_object = true
	elif method_return_info.type == TYPE_DICTIONARY:
		return_type = "Dictionary"
		mapping_to_type = "Dictionary"
	else:
		return_type = "Other"
		mapping_to_type = type_string(method_return_info.type)
		
	# 看配置的result_type（配置的automapping的类型）
	# 和函数返回值推断的automapping的类型是否一致
	if not result_type.is_empty():
		assert(result_type == mapping_to_type or mapping_to_type.is_empty(), 
			"resultType `%s` not match your method type `%s`." % \
			[result_type, mapping_to_type])
	# resultType和resultMap都没配置，就用函数返回值推断的类型
	elif result_map.is_empty():
		assert(method_return_info.type != TYPE_NIL, 
			"You have to configure resultType or resultMap to your <select>;" +\
			"Or you can specify a return type to your method.")
		result_type = mapping_to_type
		
	# 原始数据
	var head = query_result.get_head()
	var datas = query_result.get_data()
	
	# 如果用户没有定义函数的返回类型，那么根据datas的大小来决定返回一个还是一组
	#if not defined_return_type:
		# TODO FIXME 虽然有多行，但可能是因为子对象有很多
		#var need_array = datas.size() > 1
		#var msg = " ".join([
			#"This query will return %s" % "an Array" if need_array else "one data",
			#"because your method does not have a return type.",
			#"It's highly recommended to define return type for your mapper's methods."
		#])
		#print_rich("[color=yellow]%s[/color]" % msg)
		#push_warning(msg)
		
	# TODO FIXME 虽然有多行，但可能是因为子对象有很多
	#if not need_array:
		#assert(datas.size() == 1, 
			#"Result set is supposed to have one row, but %d." % datas.size())
			
	# 定义了每条数据映射到的数据类型
	if not result_type.is_empty():
		# 反向补充一下mapping_to_type，因为后面有些地方可能要用
		if mapping_to_type.is_empty():
			mapping_to_type = result_type
			
		# 每条数据映射到对象
		if mapping_to_object:
			assert(auto_mapping_level != "NONE", 
				"Cannot mapping data to %s because auto_mapping_level is NONE" \
				% result_type)
				
			# 检查一下是否有重复的字段
			var columns = []
			var pk_index = {} # 主键索引，可能涉及多表
			for j in head:
				var column = head[j]["field_as"]
				assert(not columns.has(column), 
					"Duplicated column name `%s`." % column)
				if head[j]["PK"] and not pk_index.values().has(column):
					pk_index[j] = column
				columns.push_back(column)
				
			# obj的属性列表及其类型，缓存到这个变量中
			var model_obj = GDSQLUtils.evaluate_command(null, 
				"%s.new()" % result_type) as Object
			assert(is_instance_valid(model_obj), 
				"Cannot initialize this class %s" % result_type)
				
			var list = (model_obj as Object).get_property_list()
			var object_prop_map = {} # 属性是子对象，可能涉及Nested Result Mapping
			var prop_map = {}
			for i in list:
				prop_map[i.name] = i
				if auto_mapping_level == "FULL" and not i.class_name.is_empty():
					object_prop_map[i.name] = i
					
			# column和prop不一定完全相同，比如可能有冒号，比如大小写、下划线、驼峰格式不同
			var prop_type = {}
			
			if return_type == "Array":
				# 用不上了，删掉
				if not model_obj is RefCounted:
					model_obj.free()
				var pk_confirm = [-1] # 为了引用，搞成数组
				var pk_obj = {} # 用主键关联obj
				var ret_datas = []
				for data in datas:
					var obj = null
					# 每个主键只允许返回一个对应的对象。如果主键不存在，那就每条数据都返回
					# 一个对象，这也是允许的。
					if pk_confirm[0] != -1:
						obj = pk_obj.get(data[pk_confirm[0]], null)
					if obj == null:
						obj = GDSQLUtils.evaluate_command(
							null, "%s.new()" % result_type) as Object
						ret_datas.push_back(obj)
					else:
						# PARTIAL时，只填充obj的简单属性（非object的属性）,由于已经填充
						# 过了，所以跳过这条数据。（这条多余的数据之所以被查询出来，是由于
						# 联表查询出来的子对象的数据之间的不同导致的，然而在PARTIAL模式下，
						# 不对子对象进行填充）
						if auto_mapping_level == "PARTIAL":
							continue
							
					_automapping_obejct(columns, prop_map, object_prop_map, prop_type,
						data, pk_index, pk_confirm, pk_obj, obj)
			elif return_type == "Object":
				assert(not datas.is_empty(), 
					"Cannot mapping to %s because no data." % mapping_to_type)
				# 如果有多条数据，但是主键值都相同，那么就没关系 TODO
				# TODO
				
		# 一条数据映射到数组
		elif result_type == "Array":
			if return_type == "Array":
				return datas
			# 没查询到数据，则返回空数组
			if datas.is_empty():
				return []
			return datas[0]
		# 一条数据映射到字典
		elif result_type == "Dictionary":
			if return_type == "Array":
				var ret_datas = []
				for i in datas:
					var map = {}
					for j in head:
						var column = head[j]["field_as"]
						assert(not map.has(column), 
							"Duplicated column name `%s`." % column)
						map[column] = i[j]
					ret_datas.push_back(map)
				return ret_datas
				
			# 没查询到数据，则返回空字典，连键都不设置
			var map = {}
			if datas.is_empty():
				return map
				
			assert(datas.size() == 1, "Result set size() != 1.")
			for j in head:
				var column = head[j]["field_as"]
				assert(not map.has(column), 
					"Duplicated column name `%s`." % column)
				map[column] = datas[0][j]
			return map
		# 一条数据映射到其他类型比如int， String 或 [int|String|...]
		else:
			# 是否是1个字段，也不能是0，因为像int, String这样的返回值，应该要返回1个。
			assert(head.size() == 1, 
				"Result set is supposed to have one column, but %d." % \
				head.size())
				
			var to_type = DataTypeDef.DATA_TYPE_COMMON_NAMES[result_type]
			# 需要返回数组
			var use_str_to_val = false
			if datas[0][0] is String and typeof(str_to_var(datas[0][0])) == to_type:
				use_str_to_val = true
			if return_type == "Array":
				var ret_datas = []
				for i in datas:
					if use_str_to_val:
						ret_datas.push_back(str_to_var(i[0]))
					else:
						ret_datas.push_back(type_convert(i[0], to_type))
				return ret_datas
				
			assert(datas.size() == 1, "Result set size() != 1.")
			if use_str_to_val:
				return str_to_var(datas[0][0])
			return type_convert(datas[0][0], to_type)
			
	var qr = QueryResult.new()
	return qr
	
func _get_similar_prop(prop_map: Dictionary, column_1: String):
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
	
## columns: 数据集的列名数组
## prop_map: 对象的属性列表，用name作为key
## object_prop_map: 属性列表，该属性是子对象，可能涉及Nested Result Mapping
## prop_type: column和prop不一定完全相同，比如可能有冒号，比如大小写、下划线、驼峰格式不同
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
## pk_index: 主键的可能索引
## pk_confirm: array(1) 主键确认的索引
## pk_obj: 用主键关联obj
## 
func _automapping_obejct(columns: Array, prop_map: Dictionary, 
object_prop_map: Dictionary, prop_type: Dictionary, data: Array, 
pk_index: Dictionary, pk_confirm: Array, pk_obj: Dictionary, obj: Object) -> Object:
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
			prop_is_object = type == TYPE_OBJECT
		else:
			# 如果要写成属性冒号的形式，那第一部分肯定需要写成原本形式才行，
			# 不需要判断大小写，蛇形，驼峰之类的。
			if column.contains(":"):
				if not column.get_slice(":", 0) in obj:
					prop_type[column] = {"exist":false}
					continue
					
			# 根据列名找对应的属性名
			var column_1 = column.get_slice(":", 0)
			prop = _get_similar_prop(prop_map, column_1)
			if prop.is_empty():
				prop_type[column] = {"exist":false}
				continue
				
			type = prop_map[prop].type
			prop_is_object = type == TYPE_OBJECT
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
		if type == TYPE_NIL or \
		typeof(data[j]) == prop_type[column]["column_type"]:
			obj.set_indexed(column, data[j]) # 支持":"的属性路径，比如"pos:x"
		else:
			# NOTICE type_convert并不是万能的，依赖于引擎
			# 底层数据格式的相互转换。例如：
			# type_convert("Vector2(1, 1)", Vector2) 并不会得到
			# Vector2(1, 1)，而是得到Vector2(0, 0)。
			# 先测试type_convert是否正确
			var value = null
			var value_set = false
			if prop_type[column]["method"].is_empty():
				if data[j] is String:
					value = str_to_var(data[j])
					value_set = true
					if typeof(value) == prop_type[column]["column_type"]:
						prop_type[column]["method"] = "str_to_var"
			if prop_type[column]["method"] == "str_to_var":
				obj.set_indexed(column, 
					value if value_set else str_to_var(data[j]))
			else:
				obj.set_indexed(column, 
					type_convert(data[j], prop_type[column]["type"]))
					
		# 主键
		if pk_index.has(j):
			if pk_confirm[0] == -1:
				pk_confirm[0] = j
			# 已经找到一个了，怎么又冒出来一个
			assert(pk_confirm[0] == j, 
				"Multiple primary keys: [%s, %s] are mapped to %s." % [pk_confirm[0], j])
			pk_obj[data[j]] = obj
			
		if auto_mapping_level == "FULL":
			for p in object_prop_map:
				var nest_obj = obj.get(p)
				# TODO set property
	return obj
