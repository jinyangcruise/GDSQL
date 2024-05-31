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
var auto_mapping: String

var mapper_parser_ref: WeakRef: set = set_mapper_parser_ref

# ----------- 内部使用 ------------
var result_embeded: Array # 内嵌的子元素

# discriminator可能导致要使用别的简单类型type
var real_type: String
# discriminator可能导致autoMapping改变
var real_auto_mapping: String
var head: Array
var mapping_to_object: bool = false
var object_class_name: String = ""
var primary_prop = ""
var primary_column = ""
var column_prop_map: Dictionary # 子元素<id>和<result>定义的关联，column => [prop]
								# NOTICE 一个列可以给多个属性赋值。
								# NOTICE 考虑使用该变量还是get_deepest_column_prop()
var discriminator: GBatisDiscriminator

# ----------- mapping to object -----------
var columns: Array # [数据集的列名]， 从head中提取的
var prop_map: Dictionary # 对象的属性列表，用name作为key
var prop_info: Dictionary # column和prop不一定完全相同，比如可能有冒号，
						  # 比如大小写、下划线、驼峰格式不同
var pk_index: Dictionary # 主键的可能索引，序号是key，column是value
var pk_confirm: Array # [主键确认的索引]
var pk_obj: Dictionary # =用主键关联obj

func _init(conf: Dictionary) -> void:
	id = conf.get("id", "").strip_edges()
	type = conf.get("type", "").strip_edges()
	_extends = conf.get("extends", "").strip_edges()
	auto_mapping = conf.get("autoMapping", "").strip_edges()
	real_type = type
	real_auto_mapping = auto_mapping
	
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
	
### 如果存在discriminator，需要返回其对应的resultMap，否则返回自己.
### 该方法仅在<case>标签中用，别的地方勿用。
#func get_deepest_result_map() -> GBatisResultMap:
	#if discriminator != null:
		#return discriminator.get_result_map()
	#return self
	
## 如果存在discriminator，需要返回其对应的resultType。
## 该方法发仅在<case>标签中用，别的地方勿用
func get_deepest_result_type() -> String:
	var ret = ""
	if discriminator != null:
		ret = discriminator.get_result_type()
	return type if ret.is_empty() else ret
	
## 如果存在discriminator，需要合并返回其对应的prop_column。
## 别的地方勿用.
func get_deepest_auto_mapping() -> String:
	var ret = ""
	if discriminator != null:
		ret = discriminator.get_auto_mapping()
	return auto_mapping if ret.is_empty() else ret
	
## 如果存在discriminator，需要合并返回其对应的prop_column。
## 别的地方勿用.
func get_deepest_prop_column() -> Dictionary:
	var ret = {}
	for i in result_embeded:
		if i is GBatisId or i is GBatisResult:
			ret[i.property] = i.column
		elif i is GBatisDiscriminator:
			ret.merge(discriminator.get_prop_column())
	return ret
	
func get_deepest_column_prop() -> Dictionary:
	if discriminator == null:
		return column_prop_map
		
	var info = get_deepest_prop_column()
	var ret = {}
	for prop in info:
		if not ret.has(info[prop]):
			ret[info[prop]] = []
		ret[info[prop]].push_back(prop)
	return ret
	
## 如果存在discriminator，需要合并返回其包含的association。
## 别的地方勿用.
func get_deepest_associations() -> Array:
	var ret = []
	for i in result_embeded:
		if i is GBatisAssociation:
			ret.push_back(i)
		elif i is GBatisDiscriminator:
			ret.append_array(i.get_associations())
	return ret
	
## 如果存在discriminator，需要合并返回其包含的collection。
## 别的地方勿用.
func get_deepest_collections() -> Array:
	var ret = []
	for i in result_embeded:
		if i is GBatisAssociation:
			ret.push_back(i)
		elif i is GBatisDiscriminator:
			ret.append_array(i.get_collections())
	return ret
	
## 初始化，准备映射到对象。
## head， 表头
func prepare_mapping_to_object(p_head: Array):
	if not columns.is_empty():
		return
		
	head = p_head
	columns = []
	prop_map = {}
	prop_info = {}
	pk_index = {}
	pk_confirm = [-1]
	pk_obj = {}
	
	# 准备columns和pk_index
	# columns: Array # 数据集的列名数组
	# pk_index: Dictionary # 主键的可能索引
	for j in head.size():
		var column = head[j]["field_as"]
		assert(not columns.has(column), 
			"Duplicated column name `%s`." % column)
		if primary_column.is_empty():
			if head[j]["PK"] and pk_index.find_key(column) == null:
				pk_index[j] = column
		else:
			if column == primary_column:
				pk_index[j] = column
		columns.push_back(column)
		
	# 检查一下xml配置有没有问题
	for i in result_embeded:
		if i is GBatisId or i is GBatisResult:
			assert(columns.has(i.column),
			"Not found column: %s in Result set. Check your xml config." % i.column)
			
	# obj的属性列表及其类型，缓存到这个变量中
	var model_obj = GDSQLUtils.evaluate_command(null, 
		"%s.new()" % object_class_name) as Object
	assert(is_instance_valid(model_obj), 
		"Cannot initialize this class %s" % object_class_name)
		
	# 准备 prop_map 
	# prop_map: Dictionary # 对象的属性列表，用name作为key
	_prepare_prop_map(model_obj)
	
	if not model_obj is RefCounted:
		model_obj.free()
		
func _prepare_prop_map(obj: Object):
	if not prop_map.is_empty():
		return
	var list = obj.get_property_list()
	for i in list:
		prop_map[i.name] = i
		
## 每处理一条数据需要调用一下。由于鉴别器discriminator可能存在，需要调用一下。
func prepare_deal(p_head: Array, data: Array):
	if discriminator != null:
		discriminator.prepare_deal(p_head, data)
		real_auto_mapping = get_deepest_auto_mapping()
		var case_return_type = discriminator.get_selected_case_return_type()
		if _is_class_name(case_return_type):
			mapping_to_object = true
			object_class_name = case_return_type
		else:
			real_type = case_return_type
			
		# 不需要prepare_deal，因为association调用resultMap的deal的时候，也会自动调用
		# prepare_deal
		#var associations = get_deepest_associations()
		#for a: GBatisAssociation in associations:
			#a.prepare_deal(p_head, data)
			
	if object_class_name.is_empty() and _is_class_name(type):
		mapping_to_object = true
		object_class_name = type
		
## 将传入的一条数据进行映射后再返回。
func deal(p_head: Array, data: Array):
	prepare_deal(p_head, data)
	
	#if not real_type.is_empty():
		## 每条数据映射到对象
		#if mapping_to_object:
			#return _deal_mapping_to_object(data)
		## 每条数据映射到数组
		#elif real_type == "Array":
			#return _deal_mapping_to_array(data)
		## 每条数据映射到字典
		#elif real_type == "Dictionary":
			#return _deal_mapping_to_dictionary(data)
		## 每条数据映射到其他类型比如int， String 或 [int|String|...]
		#else:
			#return _deal_mapping_to_other(data, head)
			
	reset()
	#return obj # TODO if mapping to obj
		
## 每处理完一条数据调用一下
func reset():
	# 重置类名，因为discriminator可能导致每一行的类不同
	object_class_name = ""
	real_type = type
	real_auto_mapping = auto_mapping
	if discriminator:
		discriminator.reset()
	for i in result_embeded:
		if i is GBatisAssociation:
			i.reset()
		
func _automapping_obejct(data: Array) -> Object:
	# 整体分为三部分：1，先给obj本身的简单字段赋值；2，然后给association定义的obj的对象字段
	# 赋值，也就是说，obj的某个属性如果也是一个sub obj，看能否把值赋值给sub obj的字段；
	# 3；最后给collection定义的集合赋值
	
	# 第一部分：先给obj的简单字段赋值
	var obj = _get_obj_or_generate(data)
	
	_automapping_object_simple_property(data, obj)
	
	# 第二部分：association
	_automapping_associations(data, obj)
	return obj
	
func _automapping_object_simple_property(data: Array, obj: Object):
	# 一批<id>,<result>配置的column和[prop]的对应关系
	var final_column_prop_map = get_deepest_column_prop()
	for j in columns.size():
		var column = columns[j] as String
		if prop_info.has(column) and \
		not prop_info[column]["exist"]:
			continue
			
		var prop = [] # 支持一个列对应多个属性的情况
		var column_type = [] # 当column带冒号时，和prop_type不一样
		var prop_is_object = []
		
		# 优先使用<id>和<result>来找prop
		if final_column_prop_map.has(column):
			prop = final_column_prop_map[column]
			for p in prop:
				# 如果对象中没有<id>, <result>配置的这个属性，要报错
				if p.contains(":"):
					# 限于技术问题，我们最多检查一层
					var pp = p.get_slice(":", 0)
					assert(pp in obj, 
						"Invalid set property %s of %s" % [p, object_class_name])
					# NOTICE 带冒号的如果用户拼写错误会导致报错。而我们目前
					# 没有什么好办法提前检测。
					column_type.push_back(typeof(obj.get_indexed(p))) # use p not pp
					prop_is_object.push_back(_is_prop_an_object(prop_map[pp]))
				else:
					assert(p in obj, 
						"Invalid set property %s of %s" % [p, object_class_name])
					column_type.push_back(prop_map[p].type)
					prop_is_object.push_back(_is_prop_an_object(prop_map[p]))
					
		# NONE - 禁用自动映射。仅对手动映射的属性进行映射。
		if prop.is_empty() and (real_auto_mapping == "false" or \
		mapper_parser_ref.get_ref().auto_mapping_level == "NONE"):
			continue
			
		if prop.is_empty():
			if prop_info.has(column):
				prop = prop_info[column]["prop"]
				for p in prop:
					column_type.push_back(prop_map[p].type)
					prop_is_object.push_back(_is_prop_an_object(prop_map[p]))
			else:
				# 如果要写成属性冒号的形式，那第一部分肯定需要写成原本形式才行，
				# 不需要判断大小写，蛇形，驼峰之类的。
				var a_prop = ""
				if column.contains(":"):
					a_prop = column.get_slice(":", 0)
					if not a_prop in obj:
						prop_info[column] = {"exist":false}
						continue
						
					prop.push_back(column)
					column_type.push_back(typeof(obj.get_indexed(column)))
				else:
					# 根据列名找对应的属性名
					a_prop = _get_similar_prop(column)
					if a_prop.is_empty():
						prop_info[column] = {"exist":false}
						continue
					prop.push_back(a_prop)
					column_type = prop_map[a_prop].type
					
				prop_is_object.push_back(_is_prop_an_object(prop_map[a_prop]))
				
				prop_info[column] = {
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
			# PARTIAL时，只填充obj的简单属性（非object的属性，但Resouce也属于简单属性）
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
				var method_map = prop_info[column]["method"]
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
			if pk_index.has(j):
				if pk_confirm[0] == -1:
					pk_confirm[0] = j
					# 弥补_get_obj_or_generate在不知道主键的时候没有关联
					pk_obj[data[j]] = obj
				else:
					# 已经找到一个了，怎么又冒出来一个
					assert(pk_confirm[0] == j, 
						"Multiple primary keys [%s, %s] are mapped to %s." % \
						[pk_confirm[0], j, object_class_name])
						
func _automapping_associations(data: Array, obj: Object):
	var associations = get_deepest_associations()
	for ass: GBatisAssociation in associations:
		assert(ass.property in obj, "Invalid property %s in %s" % \
			[ass.property, object_class_name])
		assert(_is_prop_an_object(prop_map[ass.property]), 
			"Property %s in %s should be an Object" % [ass.property, object_class_name])
			
		var sub_obj = null
		if not ass.select.is_empty():
			# 用关联列去调用一条select语句获取结果
			var col_index = columns.find(ass.column)
			assert(col_index != -1, "Cannot found column: %s in Result set." % ass.column)
			sub_obj = mapper_parser_ref.get_ref().\
				call_method_in_namespace(ass.select, [data[col_index]])
		else:
			sub_obj = ass._result_map.deal(head, data)
			
		obj.set(ass.property, sub_obj)
		# 允许sub_obj是null，但是不允许设置失败
		if sub_obj != null:
			assert(is_instance_valid(obj.get(ass.property)), 
				"Set associated property %s failed!" % ass.property)
				
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
		
func _is_class_name(s: String) -> bool:
	if s.is_empty():
		return false
	return not DataTypeDef.DATA_TYPE_COMMON_NAMES.has(s) and \
		not DataTypeDef.RESOURCE_TYPE_NAMES.has(s)
		
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
			# 这里会把第一个obj的pk_obj关联丢失，因为还不知道主键是哪个，所以在别的地方要补上
			if pk_confirm[0] != -1:
				pk_obj[data[pk_confirm[0]]] = obj
	return obj
