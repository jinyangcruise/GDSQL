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
#                                            NOTICE if all configured columns'
#                                            values are null, then the Object
#                                            is null.
#>
var id: String
var type: String
var _extends: String
var auto_mapping: String

var mapper_parser_ref: WeakRef: set = set_mapper_parser_ref
var column_prefix: String = "" # set by association or collection

# ----------- 内部使用 ------------
var result_embeded: Array # 内嵌的子元素
var sub_elements: Array # 包括继承的元素和内嵌的子元素

# discriminator可能导致要使用别的简单类型type
var real_type: String
# discriminator可能导致autoMapping改变
var real_auto_mapping: String
var head: Array
# 在有discriminator的情况下，每条数据都需要prepare_deal；否则只需要做一次。
var need_prepare_deal: bool = true
var mapping_to_object: bool = false
var mapping_to_array: bool = false
var mapping_to_dictionary: bool = false
var mapping_to_other: bool = false

var object_class_name: String = "" # 当mapping_to_object==true时有用
var primary_prop = ""
var primary_column = ""
var column_prop_map: Dictionary # 子元素<id>和<result>定义的关联，column => [prop]
								# NOTICE 一个列可以给多个属性赋值。
								# NOTICE 考虑使用该变量还是get_deepest_column_prop()
var array_type: String = "" # 当mapping_to_array==true时有用
var discriminator: GBatisDiscriminator

# ----------- mapping to object -----------
var columns: Array # [数据集的列名]， 从head中提取的
var prop_map: Dictionary # 对象类名 => {对象的属性列表，用name作为key}
var prop_info: Dictionary # 对象类名 => {column和prop不一定完全相同，比如可能有冒号，
						  # 比如大小写、下划线、驼峰格式不同}
var pk_index: Dictionary # 主键的可能索引，序号是key，column是value
var pk_confirm: Array = [-1] # [主键确认的索引]
var pk_obj: Dictionary # =用主键关联obj

func _init(conf: Dictionary) -> void:
	id = conf.get("id", "").strip_edges()
	type = conf.get("type", "").strip_edges()
	_extends = conf.get("extends", "").strip_edges()
	auto_mapping = conf.get("autoMapping", "").strip_edges()
	real_type = type
	real_auto_mapping = auto_mapping
	
## 全部子元素都push完后，调用一次该函数
func end_push_element():
	sub_elements = get_sub_element()
	
func push_element(i):
	# 只允许存在一个discriminator
	if i is GBatisDiscriminator:
		if discriminator != null:
			assert(false, "At most one <discriminator> can be put under <resultMap>.")
		discriminator = i
		
	if i is GBatisId or i is GBatisResult:
		var column_name = null
		if column_prefix == "":
			column_name = i.column
		else:
			column_name = column_prefix + i.column
		if i is GBatisId:
			if primary_prop != "":
				assert(false, "Only one <id> can be put under <resultMap>.")
			primary_prop = i.property
			primary_column = column_name
			
		for column in column_prop_map:
			# 多个不同的列对应一个属性，这是错的
			if column_prop_map[column].has(i.property):
				assert(false, "Duplicate attr property " + i.property)
		if not column_prop_map.has(column_name):
			column_prop_map[column_name] = []
		column_prop_map[column_name].push_back(i.property)
		
	result_embeded.push_back(i)
	
func set_mapper_parser_ref(mapper_parser):
	mapper_parser_ref = mapper_parser
	
func clean():
	mapper_parser_ref = null
	for i in sub_elements:
		i.clean()
	sub_elements.clear()
	result_embeded.clear()
	head.clear()
	column_prop_map.clear()
	discriminator = null
	columns.clear()
	prop_map.clear()
	prop_info.clear()
	pk_index.clear()
	pk_confirm.clear()
	pk_obj.clear()
	
## 由于可以extends，所以通过该方法获取子元素
## 涉及到内存释放，所以请勿多次调用，除非自己管理内存
func get_sub_element():
	if _extends == "":
		return result_embeded
		
	var props = {}
	var a_columns = {}
	var ret = []
	for i in range(result_embeded.size()-1, -1, -1):
		var e = result_embeded[i]
		if e is GBatisId or e is GBatisResult or e is GBatisAssociation or \
		e is GBatisCollection:
			props[e.property] = 0
		elif e is GBatisDiscriminator:
			a_columns[e.column] = 0
		ret.push_back(e)
		
	var extend_result_map = mapper_parser_ref.get_ref().get_element(_extends) as GBatisResultMap
	var extends_children = extend_result_map.sub_elements
	extend_result_map.result_embeded.clear() # 清空引用，防止内存泄漏
	extend_result_map.sub_elements.clear() # 清空引用，防止内存泄漏
	for i in range(extends_children.size()-1, -1, -1):
		var e = extends_children[i]
		if e is GBatisId or e is GBatisResult or e is GBatisAssociation or \
		e is GBatisCollection:
			if props.has(e.property):
				continue
		elif e is GBatisDiscriminator:
			if props.has(e.column):
				continue
		ret.push_back(e)
		
	ret.reverse()
	return ret
	
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
	return type if ret == "" else ret
	
## 如果存在discriminator，需要合并返回其对应的prop_column。
## 别的地方勿用.
func get_deepest_auto_mapping() -> String:
	var ret = ""
	if discriminator != null:
		ret = discriminator.get_auto_mapping()
	return auto_mapping if ret == "" else ret
	
## 如果存在discriminator，需要合并返回其对应的prop_column。
## 别的地方勿用.
func get_deepest_prop_column() -> Dictionary:
	var ret = {}
	for i in sub_elements:
		if i is GBatisId or i is GBatisResult:
			if column_prefix == "":
				ret[i.property] = i.column
			else:
				ret[i.property] = column_prefix + i.column
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
	for i in sub_elements:
		if i is GBatisAssociation:
			ret.push_back(i)
		elif i is GBatisDiscriminator:
			ret.append_array(i.get_associations())
	return ret
	
## 如果存在discriminator，需要合并返回其包含的collection。
## 别的地方勿用.
func get_deepest_collections() -> Array:
	var ret = []
	for i in sub_elements:
		if i is GBatisCollection:
			ret.push_back(i)
		elif i is GBatisDiscriminator:
			ret.append_array(i.get_collections())
	return ret
	
## 检查表头
func check_head(p_head: Array):
	if not head.is_empty():
		return
		
	head = p_head
	# 准备columns和pk_index
	# columns: Array # 数据集的列名数组
	# pk_index: Dictionary # 主键的可能索引
	for j in head.size():
		var column = head[j]["field_as"]
		#if columns.has(column):
			#assert(false, "Duplicated column name " + column)
		if primary_column == "":
			if head[j]["PK"] and pk_index.find_key(column) == null:
				pk_index[j] = column
		else:
			if column == primary_column:
				pk_index[j] = column
		columns.push_back(column)
		
	# 检查一下xml配置有没有问题
	for i in sub_elements:
		if i is GBatisId or i is GBatisResult:
			var column_name = null
			if column_prefix == "":
				column_name = i.column
			else:
				column_name = column_prefix + i.column
			if not columns.has(column_name):
				assert(false, "Not found column: " + column_name + \
					" in Result set. Check your xml config.")
		elif i is GBatisDiscriminator or i is GBatisAssociation or \
		i is GBatisCollection:
			i.check_head(head)
			
## 应对discriminator分裂造成有多个类
func prepare_prop_map():
	if prop_map.has(object_class_name):
		return
		
	prop_map[object_class_name] = {}
	prop_info[object_class_name] = {} # 顺便初始化一下prop_info
	# obj的属性列表及其类型，缓存到这个变量中
	var model_obj = GDSQLUtils.evaluate_command_script(object_class_name + ".new()") as Object
	if model_obj == null:
		assert(false, "Cannot initialize this class " + object_class_name)
		
	# 准备 prop_map 
	# prop_map: Dictionary # 对象的属性列表，用name作为key
	var list = model_obj.get_property_list()
	for i in list:
		prop_map[object_class_name][i.name] = i
		
	if not model_obj is RefCounted:
		model_obj.free()
	
## 每处理一条数据需要调用一下。由于鉴别器discriminator可能存在，需要调用一下。
func prepare_deal(data: Array):
	# need_prepare_deal默认为true，所以至少会执行一次
	if need_prepare_deal:
		real_type = type
		if discriminator == null:
			need_prepare_deal = false
		else:
			need_prepare_deal = true
			discriminator.prepare_deal(data)
			real_auto_mapping = get_deepest_auto_mapping()
			var case_return_type = discriminator.get_result_type()
			if case_return_type != "":
				real_type = case_return_type
				
		if _is_class_name(real_type):
			mapping_to_object = true
			object_class_name = real_type
			prepare_prop_map()
		elif real_type.begins_with("Array[") and real_type.ends_with("]"):
			mapping_to_array = true
			array_type = real_type.replace("Array[", "").replace("]", "").strip_edges()
		elif real_type == "Array":
			mapping_to_array = true
		elif real_type == "Dictionary":
			mapping_to_dictionary = true
		else:
			mapping_to_other = true
			
	# assocoiation和collection由于存在内部的resultMap，所以由它们自己决定是否prepare_deal
	var associations = get_deepest_associations()
	for a: GBatisAssociation in associations:
		# select == ""的，是用left join，共用数据集的，所以要提前prepare。
		if a.select == "":
			a.prepare_deal(data)
			
	var collections = get_deepest_collections()
	for c: GBatisCollection in collections:
		# select == ""的，是用left join，共用数据集的，所以要提前prepare。
		if c.select == "":
			c.prepare_deal(data)
			
## 将传入的一条数据进行映射后再返回。
func deal(data: Array) -> Array:
	# 每条数据映射到对象
	var ret = null
	if mapping_to_object:
		ret = _automapping_obejct(data)
	# 每条数据映射到数组
	elif mapping_to_array:
		ret = _automapping_array(data)
	# 每条数据映射到字典
	elif mapping_to_dictionary:
		ret = _automapping_dictionary(data)
	# 每条数据映射到其他类型比如int， String 或 [int|String|...]
	elif mapping_to_other:
		ret = _automapping_other(data)
	else:
		assert(false, "Inner err in result_map. 101.")
		
	reset()
	return [ret]
	
## 每处理完一条数据调用一下
func reset():
	if need_prepare_deal:
		mapping_to_object = false
		mapping_to_array = false
		mapping_to_dictionary = false
		mapping_to_other = false
		# 重置类名，因为discriminator可能导致每一行的类不同
		object_class_name = ""
		array_type = ""
		real_type = type
		real_auto_mapping = auto_mapping
	if discriminator:
		discriminator.reset()
	for i in sub_elements:
		if i is GBatisAssociation:
			i.reset()
		elif i is GBatisCollection:
			i.reset()
			
func _automapping_obejct(data: Array) -> Object:
	# 整体分为三部分：1，先给obj本身的简单字段赋值；2，然后给association定义的obj的对象字段
	# 赋值，也就是说，obj的某个属性如果也是一个sub obj，看能否把值赋值给sub obj的字段；
	# 3；最后给collection定义的集合赋值
	
	# 都是null，要返回null
	var all_null = true
	for i in data:
		if typeof(i) != TYPE_NIL:
			all_null = false
			break
	if all_null:
		return null
		
	var obj = _get_obj_or_generate(data)
	if obj == null:
		assert(false, "Error occur in _get_obj_or_generate().")
		
	# 不是新的obj，就不用做简单字段赋值和一对一对象赋值
	if obj.has_meta("new"):
		# INFO 第一部分：先给obj的简单字段赋值
		var succ1 = _automapping_object_simple_property(data, obj)
		
		# -1 means all columns are null so the obj should be null
		if succ1 == -1:
			_free_obj(obj)
			return null
			
		if not succ1:
			_free_obj(obj)
			assert(false, "Err occur in _automapping_object_simple_property().")
			
		# 这里我们已经确定了是否存在主键
		if pk_confirm[0] != -1:
			pk_obj[data[pk_confirm[0]]] = obj
			
		# INFO 第二部分：association，一对一对象赋值
		var succ2 = _automapping_associations(data, obj)
		if not succ2:
			_free_obj(obj)
			assert(false, "Err occur in _automapping_associations().")
		obj.remove_meta("new")
		
	# INFO 第三部分：collection，一对多集合赋值
	var succ3 = _automapping_collections(data, obj)
	if not succ3:
		_free_obj(obj)
		assert(false, "Err occur in _automapping_collections()")
	return obj
	
func _free_obj(obj: Object):
	if not obj is RefCounted:
		obj.free()
		
## 返回值null表示有错误发生。-1表示返回null对象，1表示正常返回obj
func _automapping_object_simple_property(data: Array, obj: Object) -> int:
	# 一批<id>,<result>配置的column和[prop]的对应关系
	var final_column_prop_map = get_deepest_column_prop()
	# 优先使用<id>和<result>来找prop，并记录，后续防止重复设置
	var dealed_props = []
	var dealed_column_indexes = []
	var all_null = true
	for column in final_column_prop_map:
		var prop = final_column_prop_map[column]
		var col_index = columns.find(column)
		if col_index == -1:
			assert(false, "Not found column %s in ResultSet's head" % column)
		if column == primary_column:
			pk_confirm[0] = col_index
		dealed_column_indexes.push_back(col_index)
		for p in prop:
			_obj_set_indexed(obj, column, p, data[col_index])
			dealed_props.push_back(p)
			if all_null and typeof(data[col_index]) != TYPE_NIL:
				all_null = false
				
	# NONE - 禁用自动映射。仅对手动映射的属性进行映射。
	if real_auto_mapping == "false" or \
	mapper_parser_ref.get_ref().auto_mapping_level == "NONE":
		return -1 if all_null else 1
		
	for j in columns.size():
		if dealed_column_indexes.has(j):
			continue
			
		var column = columns[j] as String
		if prop_info[object_class_name].has(column) and \
		not prop_info[object_class_name][column]["exist"]:
			continue
			
		var prop: String
		var prop_type: int = -1
		var prop_is_object: bool = false
		if prop_info[object_class_name].has(column):
			# 这里的column本来就是用户没有手动映射的，所以只允许有1个猜测的属性
			if prop_info[object_class_name][column].prop.size() > 1:
				assert(false, "Inner error 104.")
			prop = prop_info[object_class_name][column].prop[0]
			prop_type = prop_info[object_class_name][column].prop_type[0]
			prop_is_object = prop_info[object_class_name][column].prop_is_object[0]
		else:
			# 如果要写成属性冒号的形式，那第一部分肯定需要写成原本形式才行，
			# 不需要判断大小写，蛇形，驼峰之类的。
			if column.contains(":"):
				prop = column.get_slice(":", 0)
				if not prop in obj:
					prop_info[object_class_name][column] = {"exist":false}
					continue
					
				prop = column
				if dealed_props.has(prop):
					prop_info[object_class_name][column] = {"exist":false}
					continue
					
				prop_type = typeof(obj.get_indexed(column))
			else:
				# 根据列名找对应的属性名
				prop = _get_similar_prop(column)
				if prop == "" or dealed_props.has(prop):
					prop_info[object_class_name][column] = {"exist":false}
					continue
					
				prop_type = prop_map[object_class_name][prop].type
				
			prop_is_object = _is_prop_an_object(prop_map[object_class_name][prop])
			prop_info[object_class_name][column] = {
				"exist": true, # 这列数据是否是obj中的属性
				"prop": [prop], # 这列数据对应的属性名称
				"prop_type": [prop_type], # 这列数据的数据类型。
				"prop_is_object": [prop_is_object],
				"method": [""] # 填充时用type_convert还是str_to_var转化数据
			}
			
		# 现在是根据column名称来给某个属性赋值，如果这个属性代表一个对象，
		# 是不可能把一个值赋给对象的，除非是赋给对象的某属性（意味着要通过冒号）。
		if prop_is_object and not prop.contains(":"):
			continue
			
		_obj_set_indexed(obj, column, prop, data[j])
		
		# 主键
		if pk_index.has(j):
			if pk_confirm[0] == -1:
				pk_confirm[0] = j
			else:
				# 已经找到一个了，怎么又冒出来一个
				if pk_confirm[0] != j:
					assert(false, 
					"Multiple primary keys [%s, %s] are mapped to %s." % \
					[pk_confirm[0], j, object_class_name])
	return 1
	
func _obj_set_indexed(obj: Object, column: String, prop: String, val: Variant):
	if not prop_info[object_class_name].has(column):
		prop_info[object_class_name][column] = {
			"exist": true, # 这列数据是否是obj中的属性
			"prop": [], # 这列数据对应的属性名称，支持多属性
			"prop_type": [], # 这列数据的数据类型，支持多属性
			"prop_is_object": [false], # true or false is not important here
			"method": [] # 填充时用type_convert还是str_to_var转化数据，支持多属性
		}
		
	if not prop_info[object_class_name][column].prop.has(prop):
		prop_info[object_class_name][column].prop.push_back(prop)
		prop_info[object_class_name][column].prop_type.push_back(-1)
		prop_info[object_class_name][column].method.push_back("")
		
	var prop_index = prop_info[object_class_name][column].prop.find(prop)
	var prop_type = prop_info[object_class_name][column].prop_type[prop_index]
	if prop_type == -1:
		if prop_map[object_class_name].has(prop):
			prop_type = prop_map[object_class_name][prop].type
		else:
			prop_type = typeof(obj.get_indexed(prop))
		prop_info[object_class_name][column].prop_type[prop_index] = prop_type
		
	var value = null
	var value_set = false
	var method = prop_info[object_class_name][column].method[prop_index]
	if method == "":
		# NOTICE type_convert并不是万能的，依赖于引擎
		# 底层数据格式的相互转换。例如：
		# type_convert("Vector2(1, 1)", Vector2) 并不会得到
		# Vector2(1, 1)，而是得到Vector2(0, 0)。
		if typeof(val) == prop_type or prop_type == TYPE_NIL:
			method = "none"
		elif val is String:
			value = str_to_var(val)
			if typeof(value) == prop_type:
				value_set = true
				method = "str_to_var"
			else:
				method = "type_convert"
		else:
			method = "type_convert"
		prop_info[object_class_name][column].method[prop_index] = method
		
	match method:
		"none":
			obj.set_indexed(prop, val)
		"str_to_var":
			obj.set_indexed(prop, value if value_set else str_to_var(val))
		"type_convert":
			obj.set_indexed(prop, type_convert(val, prop_type))
		_:
			assert(false, "Inner error 103.")
			
func _automapping_associations(data: Array, obj: Object) -> bool:
	var associations = get_deepest_associations()
	for ass: GBatisAssociation in associations:
		if not ass.property in obj:
			assert(false, "Invalid property %s in %s" % \
			[ass.property, object_class_name])
		if not _is_prop_an_object(prop_map[object_class_name][ass.property]):
			assert(false, "Property %s in %s should be an Object" % \
			[ass.property, object_class_name])
			
		var sub_obj = null
		# 调用另一个<select>
		if ass.select != "":
			# 用关联列去调用一条select语句获取结果
			var link_cols = ass.column.split(",")
			var args = []
			for i in link_cols.size():
				link_cols[i] = link_cols[i].strip_edges()
				if ass.column_prefix != "" and link_cols[i].begins_with(ass.column_prefix):
					push_warning("Do you mean to add column_prefix:[%s] to column:[%s] twice?" % \
						[ass.column_prefix, link_cols[i]])
				link_cols[i] = ass.column_prefix + link_cols[i]
				var col_index = columns.find(link_cols[i])
				if col_index == -1:
					assert(false, 
					"Cannot found column: %s in Result set." % link_cols[i])
				args.push_back(data[col_index])
			assert(args.size() == link_cols.size(), "Err occur.")
			sub_obj = mapper_parser_ref.get_ref().\
				call_method_in_namespace(ass.select, args)
		else:
			#ass._result_map.check_head(head) 已经在主resultMap check_head时统一做了
			#ass._result_map.prepare_deal(data)
			var a_ret = ass._result_map.deal(data)
			if not a_ret is Array:
				assert(false, "Err occur in association's resultMap deal().")
			sub_obj = a_ret[0]
			if sub_obj != null:
				sub_obj.remove_meta("new_for_select")
				
		obj.set(ass.property, sub_obj)
		# 允许sub_obj是null，但是不允许设置失败
		if sub_obj != null:
			if not is_instance_valid(obj.get(ass.property)):
				assert(false, "Set associated property %s failed!" % ass.property)
	return true
	
func _automapping_collections(data: Array, obj: Object) -> bool:
	var collections = get_deepest_collections()
	for col: GBatisCollection in collections:
		if not col.property in obj:
			assert(false, "Invalid property %s in %s" % \
			[col.property, object_class_name])
		if not (prop_map[object_class_name][col.property].type == TYPE_ARRAY or \
		prop_map[object_class_name][col.property].type == TYPE_NIL):
			assert(false, "Property %s in %s should be an Array" % \
			[col.property, object_class_name])
			
		var of_type = ""
		if prop_map[object_class_name][col.property].type == TYPE_NIL:
			pass # leave empty
		elif prop_map[object_class_name][col.property].hint == PROPERTY_HINT_ARRAY_TYPE:
			of_type = prop_map[object_class_name][col.property].hint_string
			if col.of_type != "" and col.of_type != of_type:
				assert(false, 
				"of_type in %s.%s not match of_type in <collection>." % \
				[object_class_name, col.property])
				
		# 调用另一个<select>
		if col.select != "":
			# 用关联列去调用一条select语句获取结果
			var link_cols = col.column.split(",")
			var args = []
			for i in link_cols.size():
				link_cols[i] = link_cols[i].strip_edges()
				if col.column_prefix != "" and link_cols[i].begins_with(col.column_prefix):
					push_warning("Do you mean to add column_prefix:[%s] to column:[%s] twice??" % \
						[col.column_prefix, link_cols[i]])
				link_cols[i] = col.column_prefix + link_cols[i]
				var col_index = columns.find(link_cols[i])
				if col_index == -1:
					assert(false, 
					"Cannot found column: %s in Result set." % link_cols[i])
				args.push_back(data[col_index])
			assert(args.size() == link_cols.size(), "Err occur.")
			var arr = mapper_parser_ref.get_ref().\
				call_method_in_namespace(col.select, args)
			if not arr is Array:
				assert(false, "Call %s failed." % col.select)
				
			var list = _gen_array(of_type)
			if of_type == "":
				list = arr
			else:
				list.assign(arr)
			obj.set(col.property, list)
			if obj.get(col.property) != list:
				assert(false, "Set collected property %s failed!" % col.property)
		else:
			var list = obj.get(col.property)
			if list == null:
				list = _gen_array(of_type)
				obj.set(col.property, list)
				
			var a_ret = col._result_map.deal(data)
			if not a_ret is Array:
				assert(false, "Err occur in collection's resultMap deal().")
			var element = a_ret[0]
			if typeof(element) != TYPE_NIL and not list.has(element):
				if element is Object:
					element.remove_meta("new_for_select")
				list.push_back(element)
				
	return true
	
func _automapping_array(data: Array):
	if array_type == "":
		return data
	var ret_data = _gen_array(array_type)
	if data.is_same_typed(ret_data):
		return data
	ret_data.assign(data)
	return ret_data
	
func _automapping_dictionary(data: Array) -> Dictionary:
	var map = {}
	for j in columns.size():
		var column = columns[j]
		#if map.has(column):
			#push_warning("Duplicated column name `%s`." % column)
		map[column] = data[j]
	return map
	
func _automapping_other(data: Array):
	if data.size() != 1:
		assert(false, "Result set is supposed to have one column, but %d." % data.size())
	if real_type == "" or \
	DataTypeDef.DATA_TYPE_COMMON_NAMES[real_type] == typeof(data[0]):
		return data[0]
		
	if data[0] is String:
		var v = str_to_var(data[0])
		if typeof(v) == DataTypeDef.DATA_TYPE_COMMON_NAMES[real_type]:
			return v
		
	return type_convert(data[0], DataTypeDef.DATA_TYPE_COMMON_NAMES[real_type])
	
func _get_similar_prop(column_1: String):
	var prop = ""
	if prop_map[object_class_name].has(column_1):
		prop = column_1
	elif prop_map[object_class_name].has(column_1.to_lower()):
		prop = column_1.to_lower()
	elif prop_map[object_class_name].has(column_1.to_upper()):
		prop = column_1.to_upper()
	else:
		var snake = column_1.to_snake_case()
		if prop_map[object_class_name].has(snake):
			prop = snake
		elif prop_map[object_class_name].has(snake.to_upper()):
			prop = snake.to_upper()
		else:
			var camel = column_1.to_camel_case()
			if prop_map[object_class_name].has(camel):
				prop = camel
			elif prop_map[object_class_name].has(camel.to_lower()):
				prop = camel.to_lower()
			elif prop_map[object_class_name].has(camel.to_upper()):
				prop = camel.to_upper()
			elif prop_map[object_class_name].has(camel[0].to_upper() + camel.substr(1)):
				prop = camel[0].to_upper() + camel.substr(1)
	return prop
	
func _is_prop_an_object(property_info: Dictionary):
	return property_info.type == TYPE_OBJECT and \
		not DataTypeDef.RESOURCE_TYPE_NAMES.has(property_info.class_name)
		
func _is_class_name(s: String) -> bool:
	if s == "":
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
		obj = GDSQLUtils.evaluate_command_script(object_class_name + ".new()")
		if obj:
			obj.set_meta("new", true) # 临时存储
			obj.set_meta("new_for_select", true) # 临时存储，给外部的select用
	return obj
	
func _gen_array(p_array_type: String):
	if p_array_type == "":
		return []
	# 不能使用evaluate_command，原因是Expression虽然成功返回但并不是typed array
	return GDSQLUtils.evaluate_command_script(
		"[] as Array[" + p_array_type + "]")
