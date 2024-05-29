@tool
extends RefCounted
class_name  GBatisResultMap
#<!ELEMENT resultMap (constructor?,id*,result*,association*,collection*, discriminator?)>
#<!ATTLIST resultMap
#id CDATA #REQUIRED
#type CDATA #REQUIRED --------- gdscript variant type or a class name, 
#                               eg. int, String, SysDept, Dictionary
#extends CDATA #IMPLIED ------- extends 属性允许一个 resultMap 继承另一个 resultMap 
#                               的配置。这意味着你可以创建一个基础的 resultMap，然后创建
#                               其他 resultMap 来继承这个基础配置，从而避免重复定义相同
#                               的映射规则。另一方面，对被继承的配置还有覆盖能力（如果定义
#                               了相同的property）。
#autoMapping (unset|true|false) #IMPLIED -- 自动映射方式。
#                                     Regardless of the auto-mapping level 
#                                     configured you can enable or disable the 
#                                     automapping for an specific ResultMap by 
#                                     adding the attribute autoMapping to it.
#
#                                     default: unset 按全局
#                                     true: automapp properties when 
#                                           related columns are selected but not 
#                                           configured;
#                                     false: do not automap columns to 
#                                            properties which are not configured.
#>
var id: String
var type: String
var _extends: String
# NOTICE 有一种情况，auto_mapping会被强制设置为false，就是该resultMap处于<case>中或被
# <case>所引用时。这时如果需要，可以用extends属性继承一些外部定义的属性。
var auto_mapping: String

var mapper_parser_ref: WeakRef: set = set_mapper_parser_ref

# ----------- 内部使用 ------------
var result_embeded: Array # 内嵌的子元素
var extra_result_embeded: Array # 由discriminator引入的额外子元素

var head: Array
var mapping_to_object: bool = false
var object_class_name: String = ""
var primary_prop = ""
var primary_column = ""
var column_prop_map: Dictionary # 子元素<id>和<result>定义的关联，column => [prop]
								# NOTICE 一个列可以给多个属性赋值。
var discriminator: GBatisDiscriminator

# ----------- mapping to object -----------
var columns: Dictionary # 对象数据的类名 => [数据集的列名]， 从head中提取的
var prop_map: Dictionary # 对象数据的类名 => {对象的属性列表，用name作为key}
var prop_info: Dictionary # 对象数据的类名 => {column和prop不一定完全相同，比如可能有冒号，
						  # 比如大小写、下划线、驼峰格式不同}
var pk_index: Dictionary # 对象数据的类名 => {主键的可能索引}
var pk_confirm: Dictionary # 对象数据的类名 => {主键确认的索引}
var pk_obj: Dictionary # 对象数据的类名 => {用主键关联obj}

func _init(conf: Dictionary) -> void:
	id = conf.get("id", "").strip_edges()
	type = conf.get("type", "").strip_edges()
	_extends = conf.get("extends", "").strip_edges()
	auto_mapping = conf.get("autoMapping", "").strip_edges()
	
func push_element(i):
	# 只允许存在一个discriminator
	if i is GBatisDiscriminator:
		assert(discriminator == null, 
			"At most one <discriminator> can be put under <resultMap>.")
		discriminator = i
		
	if i is GBatisId or i is GBatisResult:
		if i is GBatisId:
			assert(primary_prop.is_empty(), 
				"Only one <id> can be put under <resultMap>.")
			primary_prop = i.property
			primary_column = i.column
			
		for column in column_prop_map:
			# 多个不同的列对应一个属性，这是错的
			assert(not column_prop_map[column].has(i.property),
				"Duplicate attr property %s." % i.property)
		if not column_prop_map.has(i.column):
			column_prop_map[i.column] = []
		column_prop_map[i.column].push_back(i.property)
		
	result_embeded.push_back(i)
	
func set_mapper_parser_ref(mapper_parser):
	mapper_parser_ref = mapper_parser
	
func clean():
	pass
	#TODO
	
## 初始化，准备映射到对象。
## head， 表头
func prepare_mapping_to_object(p_head: Array):
	if columns.has(object_class_name):
		return
		
	head = p_head
	columns[object_class_name] = []
	prop_map[object_class_name] = {}
	prop_info[object_class_name] = {}
	pk_index[object_class_name] = {}
	pk_confirm[object_class_name] = -1
	pk_obj[object_class_name] = {}
	
	# 准备columns和pk_index
	# columns: Array # 数据集的列名数组
	# pk_index: Dictionary # 主键的可能索引
	for j in head.size():
		var column = head[j]["field_as"]
		assert(not columns[object_class_name].has(column), 
			"Duplicated column name `%s`." % column)
		if primary_column.is_empty():
			if head[j]["PK"] and pk_index[object_class_name].find_key(column) == null:
				pk_index[object_class_name][j] = column
		else:
			if column == primary_column:
				pk_index[object_class_name][j] = column
		columns[object_class_name].push_back(column)
		
	# 检查一下xml配置有没有问题
	for i in result_embeded:
		if i is GBatisId or i is GBatisResult:
			assert(columns[object_class_name].has(i.column),
			"Not found column: %s in Result set. Check your xml config." % i.column)
			
	# obj的属性列表及其类型，缓存到这个变量中
	var model_obj = GDSQLUtils.evaluate_command(null, 
		"%s.new()" % object_class_name) as Object
	assert(is_instance_valid(model_obj), 
		"Cannot initialize this class %s" % object_class_name)
		
	# 准备 prop_map object_prop_map
	# prop_map: Dictionary # 对象的属性列表，用name作为key
	# object_prop_map: Dictionary # 属性列表，该属性是子对象
	var list = (model_obj as Object).get_property_list()
	for i in list:
		prop_map[object_class_name][i.name] = i
		
## 将传入的一条数据进行映射后再返回
func automapping_data(data: Array):
	# 子元素对结果的影响
	for i in result_embeded:
		if i is GBatisId or i is GBatisResult:
			if i is GBatisId:
				assert(primary_prop.is_empty(), "Only one <id> can be put under <resultMap>.")
				primary_prop = i.property
				primary_column = i.column
			assert(column_prop_map.find_key(i.property) == null, 
				"Duplicate attr property %s." % i.property)
			column_prop_map[i.column] = i.property
			
	# 鉴别器对class_name的影响
	if discriminator:
		discriminator.prepare_deal(head, data)
		var case_return_type = discriminator.get_selected_case_return_type()
		if _is_class_name(case_return_type):
			mapping_to_object = true
			object_class_name = case_return_type
			
	if object_class_name.is_empty() and _is_class_name(type):
			mapping_to_object = true
			object_class_name = type
			
				
	#if not type.is_empty():
		## 每条数据映射到对象
		#if mapping_to_object:
			#return _deal_mapping_to_object(data)
		## 每条数据映射到数组
		#elif type == "Array":
			#return _deal_mapping_to_array(data)
		## 每条数据映射到字典
		#elif type == "Dictionary":
			#return _deal_mapping_to_dictionary(data)
		## 每条数据映射到其他类型比如int， String 或 [int|String|...]
		#else:
			#return _deal_mapping_to_other(data, head)
			
	# 重置类名，因为discriminator可能导致每一行的类不同
	object_class_name = ""
	
func _automapping_obejct(data: Array, obj: Object) -> Object:
	# 整体分为三部分：1，先给obj本身的简单字段赋值；2，然后给association定义的obj的对象字段
	# 赋值，也就是说，obj的某个属性如果也是obj（比如sub obj），看能否把值赋值给sub obj的字段；
	# 3；最后给collection定义的集合赋值
	
	# 第一部分：先给obj本身的字段赋值
	for j in columns[object_class_name].size():
		var column = columns[object_class_name][j] as String
		if prop_info[object_class_name].has(column) and \
		not prop_info[object_class_name][column]["exist"]:
			continue
			
		var prop = [] # 支持一个列对应多个属性的情况
		var column_type = [] # 当column带冒号时，和prop_type不一样
		var prop_is_object = []
		
		# 优先使用<id>和<result>来找prop
		if column_prop_map.has(column):
			prop = column_prop_map[column]
			var p_index = -1
			for p in prop:
				p_index += 1
				# 如果对象中没有<id>, <result>配置的这个属性，要报错
				if p.contains(":"):
					# 限于技术问题，我们最多检查一层
					var pp = p.get_slice(":", 0)
					assert(pp in obj, 
						"Invalid set property %s of %s" % [p, object_class_name])
					# NOTICE 带冒号的如果用户拼写错误会导致报错。而我们目前
					# 没有什么好办法提前检测。
					column_type.push_back(typeof(obj.get_indexed(p))) # use p not pp
					prop_is_object.push_back(_is_prop_an_object(prop_map[object_class_name][pp])) # FIXME?
				else:
					assert(p in obj, 
						"Invalid set property %s of %s" % [p, object_class_name])
					column_type.push_back(prop_map[object_class_name][p].type)
					prop_is_object.push_back(_is_prop_an_object(prop_map[object_class_name][p]))
					
		if prop.is_empty():
			if prop_info[object_class_name].has(column):
				prop = prop_info[object_class_name][column]["prop"]
				for p in prop:
					column_type.push_back(prop_map[object_class_name][p].type)
					prop_is_object.push_back(_is_prop_an_object(prop_map[object_class_name][p]))
			else:
				# 没找到的话通过column来推断，但是需要auto_mapping_level为PARTIAL或FULL
				# 如果auto_mapping == "false"也不去推断
				if mapper_parser_ref.get_ref().auto_mapping_level == "NONE" or \
				auto_mapping == "false":
					continue
					
				# 如果要写成属性冒号的形式，那第一部分肯定需要写成原本形式才行，
				# 不需要判断大小写，蛇形，驼峰之类的。
				var a_prop = ""
				if column.contains(":"):
					a_prop = column.get_slice(":", 0)
					if not a_prop in obj:
						prop_info[object_class_name][column] = {"exist":false}
						continue
						
					prop.push_back(column)
					column_type.push_back(typeof(obj.get_indexed(column)))
				else:
					# 根据列名找对应的属性名
					a_prop = _get_similar_prop(column)
					if a_prop.is_empty():
						prop_info[object_class_name][column] = {"exist":false}
						continue
					prop.push_back(a_prop)
					column_type = prop_map[object_class_name][a_prop].type
					
				prop_is_object.push_back(_is_prop_an_object(prop_map[object_class_name][a_prop]))
				
				prop_info[object_class_name][column] = {
					# 这列数据是否是obj中的属性
					"exist": true,
					# 这列数据对应的属性名称
					"prop": prop,
					# 这列数据的数据类型。
					"column_type": column_type,
					# 填充时用type_convert还是str_to_var转化数据
					"method": prop.map(func(_v): return "")
				}
				
		var prop_index = -1
		for a_prop: String in prop:
			prop_index += 1
			# PARTIAL时，只填充obj的简单属性（非object的属性）
			if prop_is_object[prop_index] and \
			mapper_parser_ref.get_ref().auto_mapping_level == "PARTIAL":
				continue
				
			# 现在是根据column名称来给某个属性赋值，如果这个属性代表一个对象，
			# 是不可能把一个值赋给对象的，除非是赋给对象的某属性（意味着要通过冒号）。
			if prop_is_object[prop_index] and not a_prop.contains(":"):
				continue
				
			if typeof(data[j]) == column_type[prop_index] or \
			TYPE_NIL == column_type[prop_index]:
				obj.set_indexed(a_prop, data[j])
			else:
				# NOTICE type_convert并不是万能的，依赖于引擎
				# 底层数据格式的相互转换。例如：
				# type_convert("Vector2(1, 1)", Vector2) 并不会得到
				# Vector2(1, 1)，而是得到Vector2(0, 0)。
				# 先测试type_convert是否正确
				var value = null
				var value_set = false
				var method_map = prop_info[object_class_name][column]["method"]
				if method_map[prop_index].is_empty():
					if typeof(data[j]) == column_type[prop_index]:
						method_map[prop_index] = "none"
					elif data[j] is String:
						value = str_to_var(data[j])
						value_set = true
						if typeof(value) == column_type[prop_index]:
							method_map[prop_index] = "str_to_var"
						else:
							method_map[prop_index] = "type_convert"
				match method_map[prop_index]:
					"none":
						obj.set_indexed(a_prop, data[j])
					"str_to_var":
						obj.set_indexed(a_prop, 
							value if value_set else str_to_var(data[j]))
					"type_convert":
						obj.set_indexed(a_prop, 
							type_convert(data[j], column_type[prop_index]))
					_:
						assert(false, "Inner error 103.")
			# 主键
			if pk_index[object_class_name].has(j):
				if pk_confirm[object_class_name] == -1:
					pk_confirm[object_class_name] = j
				# 已经找到一个了，怎么又冒出来一个
				assert(pk_confirm[object_class_name] == j, 
					"Multiple primary keys [%s, %s] are mapped to %s." % \
					[pk_confirm[object_class_name], j, object_class_name])
				pk_obj[object_class_name][data[j]] = obj
				
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
	#if prop_map.has(column_1):
		#prop = column_1
	#elif prop_map.has(column_1.to_lower()):
		#prop = column_1.to_lower()
	#elif prop_map.has(column_1.to_upper()):
		#prop = column_1.to_upper()
	#else:
		#var snake = column_1.to_snake_case()
		#if prop_map.has(snake):
			#prop = snake
		#elif prop_map.has(snake.to_upper()):
			#prop = snake.to_upper()
		#else:
			#var camel = column_1.to_camel_case()
			#if prop_map.has(camel):
				#prop = camel
			#elif prop_map.has(camel.to_lower()):
				#prop = camel.to_lower()
			#elif prop_map.has(camel.to_upper()):
				#prop = camel.to_upper()
			#elif prop_map.has(camel[0].to_upper() + camel.substr(1)):
				#prop = camel[0].to_upper() + camel.substr(1)
	return prop
	
func _free_obj(obj: Object):
	if not obj is RefCounted:
		obj.free()
		
func _is_prop_an_object(property_info: Dictionary):
	return property_info.type == TYPE_OBJECT and \
		not DataTypeDef.RESOURCE_TYPE_NAMES.has(property_info.class_name)
		
func _is_class_name(s: String) -> bool:
	if s.is_empty():
		return false
	return not DataTypeDef.DATA_TYPE_COMMON_NAMES.has(s) and \
		not DataTypeDef.RESOURCE_TYPE_NAMES.has(s)
