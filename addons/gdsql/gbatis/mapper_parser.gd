@tool
## 一个解析mapper xml的工具。解析规则参考:
## @see https://mybatis.org/mybatis-3/sqlmap-xml.html
## @see http://mybatis.org/dtd/mybatis-3-mapper.dtd
extends RefCounted

#@export_enum("NONE", "PARTIAL", "FULL")
@export_enum("NONE", "PARTIAL")
## 全局自动映射等级。
## NONE - 禁用自动映射。仅对手动映射的属性进行映射。
## PARTIAL -对除在内部定义了嵌套结果映射（也就是连接的属性）以外的属性进行映射。
##          也就是对复杂属性以外的属性进行映射。复杂属性是指属性指向了一个对象（非Resource）。
## FULL - auto-maps everything. ❌ not support 鉴于实际情况中非常不实用，就不支持了。
var auto_mapping_level: String = "PARTIAL"

## 如果mapper中的函数没有定义返回值类型，但是，GBatis该如何返回数据。
## - ALWAYS_ARRAY: 总是返回一个数组
@export_enum("ALWAYS_ARRAY", "ARRAY_WHEN_NECESSARY")
var return_type_undefined_behavior: String = "ALWAYS_ARRAY"

## 方法请求返回值的信息.
## - name 是该属性的名称，类型为 String；
## - class_name 为空 StringName，除非该属性为 TYPE_OBJECT 并继承自某个类；
## - type 是该属性的类型，类型为 int（见 Variant.Type）；
## - hint 是应当如何编辑该属性（见 PropertyHint）；
## - hint_string 取决于 hint（见 PropertyHint）；
## - usage 是 PropertyUsageFlags 的组合
@export var method_return_info: Dictionary


## 数据缓存。用方法名-参数，序列化后作为key，用返回值序列化作为value。
static var _cache_manager: Dictionary

## NOTICE which is also used in GDSQL.GBatisCache
const BIND = "__bind__"

static var re_placeholder: RegEx = RegEx.new()
#static var re_split: RegEx = RegEx.new()

static func _static_init() -> void:
	# deal #{ roleId } ${   rrrr} #   { user . roleId } ${list[0} ${bea.abc[ 33 ]} ${map[a]}
	#re_placeholder.compile(r'(?is)(#\s*\{\s*|\$\s*\{\s*)([a-zA-Z_][a-zA-Z0-9_]*\s*\.?\s*[a-zA-Z0-9_]*\s*)\s*(\}\s*|\s*\})')
	#re_placeholder.compile(r'(?is)(#\s*\{\s*|\$\s*\{\s*)([a-zA-Z_][a-zA-Z0-9_]*(\s*[\.\s]*[a-zA-Z0-9_]*|\s*[\[\s]*[0-9]*[\s]*\])*)\s*(\}\s*|\s*\})')
	re_placeholder.compile(r'(?is)(#\s*\{\s*|\$\s*\{\s*)([a-zA-Z_][a-zA-Z0-9_]*((\s*[\.\s]*[a-zA-Z0-9_]*|\s*[\[\s]*[a-zA-Z0-9_]*[\s]*\])*)*)\s*(\}\s*|\s*\})')
	#re_split.compile(r'(?is)[^\.\[\]]+')
	
@export var config: GXML:
	set(val):
		var validator = GDSQL.GBatisMapperValidator.new()
		var succ = validator.validate(val)
		if succ:
			config = val
			if not _cache_manager.has(config.resource_path):
				for i in config.root_item.content:
					if i is GDSQL.GXMLItem and i.name == "cache":
						_cache_manager[config.resource_path] = GDSQL.GBatisCache.new(i.attrs)
						break
					
## TODO 等官方支持可变参数数量函数时，可以进行优化
## https://github.com/godotengine/godot/pull/82808
## btw: Ability to print and log script backtraces
## https://github.com/godotengine/godot/pull/91006
func query(method_id: String, param: Dictionary):
	if config == null:
		assert(false, "config is empty!")
		return null
	param[BIND] = {}
	var item = _get_item(method_id)
	if not item:
		assert(false, "not found this method: %s" % method_id)
		return null
	match item.name:
		"select":
			var element = _deal_select(item, param, 0)
			var cache : GDSQL.GBatisCache = null
			if _cache_manager.has(config.resource_path):
				cache = _cache_manager[config.resource_path]
				if element.flush_cache == "true":
					cache.clear_cache()
					
			var ret = null
			if cache and element.use_cache == "true":
				var cache_ret = cache.get_cache(method_id, param)
				if cache_ret[0]:
					ret = cache_ret[1]
				else:
					ret = element.query()
					if element.query_status == "ok":
						cache.set_cache_by_key(cache_ret[2], ret)
			else:
				ret = element.query()
			element.clean()
			return ret
		"update", "insert", "replace", "delete":
			var element = _deal_element(item, param, 0)
			
			if element.flush_cache == "true" and _cache_manager.has(config.resource_path):
				var cache = _cache_manager[config.resource_path] as GDSQL.GBatisCache
				cache.clear_cache()
				
			var ret = element.query()
			element.clean()
			return ret
		_:
			assert(false, "method must be one of select, insert, replace, update and delete.")
			return null
			
## ALERT WARNING 目前只知道可以获取resultMap，其他类型的未经测试
func get_element(id: String):
	if config == null:
		assert(false, "config is empty!")
		return null
	var item = _get_item(id)
	if not item:
		assert(false, "Not found element of id: %s." % id)
		return null
	var element = _deal_element(item, {}, 0) # ALERT 目前调用get_element的地方并不需要替换占位符
	return element
	
## 调用namespace中的方法
func call_method_in_namespace(method: String, args: Array =[]):
	if config == null:
		assert(false, "config is empty!")
		return null
	var ns = config.root_item.attrs.get("namespace", "")
	var obj = GDSQL.GDSQLUtils.evaluate_command_script(ns + ".new()")
	if not method in obj:
		assert(false, "Cannot find method %s in %s" % [method, ns])
		return null
	obj.mapper_xml = config
	var ret = obj.callv(method, args)
	if not obj is RefCounted:
		obj.free()
	return ret
	
## 适用于某些item获取其全部sql内容或部分sql内容。适用范围请搜索该方法的调用者，比如<select>的_deal_selct()。
func _item_to_string(item: GDSQL.GXMLItem, param: Dictionary, depth: int, valid_sub_items: Array, binded_param: Array):
	var ret = ""
	for i in item.content:
		if i is GDSQL.GXMLItem:
			if not valid_sub_items.has(i.name):
				assert(false, "Invalid element %s in <%s>." % [i.name, item.name])
				return null
			_record_binded_param(i, binded_param)
			ret = _combine(ret, _deal_element(i, param, depth + 1))
		else:
			ret = _combine_pcdata(ret, i, param, depth)
	return ret
	
func _get_item(id: String) -> GDSQL.GXMLItem:
	for i in config.root_item.content:
		if i is GDSQL.GXMLItem and (i as GDSQL.GXMLItem).attrs.get("id", "") == id:
			return i
	return null
	
func _deal_element(item:GDSQL.GXMLItem, param: Dictionary, depth: int):
	if not item:
		return ""
	match item.name:
		"cache-ref":
			return _deal_cache_ref(item, param, depth)
		"cache":
			return _deal_cache(item, param, depth)
		"parameterMap":
			return _deal_parameter_map(item, param, depth)
		"parameter":
			return _deal_parameter(item, param, depth)
		"resultMap":
			return _deal_result_map(item, param, depth)
		"id":
			return _deal_id(item, param, depth)
		"result":
			return _deal_result(item, param, depth)
		"idArg":
			return _deal_id_arg(item, param, depth)
		"arg":
			return _deal_arg(item, param, depth)
		"collection":
			return _deal_collection(item, param, depth)
		"association":
			return _deal_association(item, param, depth)
		"discriminator":
			return _deal_discriminator(item, param, depth)
		"case":
			return _deal_case(item, param, depth)
		"property":
			return _deal_property(item, param, depth)
		"typeAlias":
			return _deal_type_alias(item, param, depth)
		"select":
			return _deal_select(item, param, depth)
		"insert":
			return _deal_insert(item, param, depth)
		"replace":
			return _deal_replace(item, param, depth)
		"selectKey":
			return _deal_select_key(item, param, depth)
		"update":
			return _deal_update(item, param, depth)
		"delete":
			return _deal_delete(item, param, depth)
		"include":
			return _deal_include(item, param, depth)
		"bind":
			return _deal_bind(item, param, depth)
		"sql":
			return _deal_sql(item, param, depth)
		"trim":
			return _deal_trim(item, param, depth)
		"where":
			return _deal_where(item, param, depth)
		"set":
			return _deal_set(item, param, depth)
		"foreach":
			return _deal_foreach(item, param, depth)
		"choose":
			return _deal_choose(item, param, depth)
		"when":
			return _deal_when(item, param, depth)
		"otherwise":
			return _deal_otherwise(item, param, depth)
		"if":
			return _deal_if(item, param, depth)
		_:
			return ""
			
#<!ELEMENT cache-ref EMPTY>
#<!ATTLIST cache-ref
#namespace CDATA #REQUIRED
#> ❌ not support
@warning_ignore("unused_parameter")
func _deal_cache_ref(item:GDSQL.GXMLItem, param: Dictionary, depth: int):
	return ""
	
#<!ELEMENT cache (property*)>
#<!ATTLIST cache
#type CDATA #IMPLIED ------------- ❌ not support
#eviction CDATA #IMPLIED --------- 缓存回收策略，可以不设置，默认值为 LRU（最近最少使用）
#                                  策略。其他可能的值包括 FIFO（先进先出）、
#                                  SOFT（软引用）❌和 WEAK（弱引用）❌
#flushInterval CDATA #IMPLIED ---- 缓存刷新间隔，单位为毫秒。如果设置为非零值，MyBatis 
#                                  会在指定的时间间隔内自动刷新缓存。
#size CDATA #IMPLIED ------------- 缓存大小，默认值为 1024。如果设置为非零值，MyBatis 
#                                  会在缓存大小超过指定值时开始回收缓存。
#                                  它指定的是缓存中可以存储的键值对的最大数量，而不是缓存
#                                  所占用的内存大小。当缓存中的键值对数量达到或超过这个指
#                                  定值时，MyBatis 就会根据缓存配置和策略来决定哪些缓存
#                                  条目应该被淘汰，以保持缓存的大小不超过指定的值。
#readOnly CDATA #IMPLIED --------- ❌ not support
#                                  是否只读，默认为 false。只读的缓存会给所有调用者返回
#                                  同一个实例，因此这些对象不能被修改，这提供了性能优势。
#blocking CDATA #IMPLIED --------- ❌ not support
#>
@warning_ignore("unused_parameter")
func _deal_cache(item:GDSQL.GXMLItem, param: Dictionary, depth: int) -> GDSQL.GBatisCache:
	return GDSQL.GBatisCache.new(item.attrs)
	
#<!ELEMENT parameterMap (parameter+)?>
#<!ATTLIST parameterMap
#id CDATA #REQUIRED
#type CDATA #REQUIRED
#>
## @deprecated ❌ not support
@warning_ignore("unused_parameter")
func _deal_parameter_map(item:GDSQL.GXMLItem, param: Dictionary, depth: int):
	return ""
	
#<!ELEMENT parameter EMPTY>
#<!ATTLIST parameter
#property CDATA #REQUIRED
#javaType CDATA #IMPLIED
#jdbcType CDATA #IMPLIED
#mode (IN | OUT | INOUT) #IMPLIED
#resultMap CDATA #IMPLIED
#scale CDATA #IMPLIED
#typeHandler CDATA #IMPLIED
#>
## @deprecated ❌ not support
@warning_ignore("unused_parameter")
func _deal_parameter(item:GDSQL.GXMLItem, param: Dictionary, depth: int):
	return ""
	
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
#autoMapping (unset|true|false) #IMPLIED -- 是否继承全局自动映射等级。
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
func _deal_result_map(item:GDSQL.GXMLItem, param: Dictionary, depth: int) -> GDSQL.GBatisResultMap:
	var ret = GDSQL.GBatisResultMap.new(item.attrs)
	ret.set_mapper_parser_ref(weakref(self))
	for i in item.content:
		if i is GDSQL.GXMLItem:
			if not ["constructor", "id", "result", "association", "collection", 
			"discriminator"].has(i.name):
				assert(false, "Invalid element %s in resultMap." % i.name)
				return null
			ret.push_element(_deal_element(i, param, depth+1))
	ret.end_push_element()
	#assert(not element_cache.has(ret.id), "Duplicate element id: %s." % ret.id)
	#element_cache[ret.id] = ret
	return ret
	
#<!ELEMENT id EMPTY>
#<!ATTLIST id
#property CDATA #REQUIRED -------- changed from #IMPLED to #REQUIRED
#javaType CDATA #IMPLIED --------- gdscript variant type or a class name, 
#                                  eg. int, String, SysDept, Dictionary
#column CDATA #REQUIRED ---------- changed from #IMPLED to #REQUIRED
#jdbcType CDATA #IMPLIED --------- ❌ not support
#typeHandler CDATA #IMPLIED ------ ❌ not support
#>
@warning_ignore("unused_parameter")
func _deal_id(item:GDSQL.GXMLItem, param: Dictionary, depth: int) -> GDSQL.GBatisId:
	return GDSQL.GBatisId.new(item.attrs)
	
#<!ELEMENT result EMPTY>
#<!ATTLIST result
#property CDATA #REQUIRED -------- changed from #IMPLED to #REQUIRED
#javaType CDATA #IMPLIED --------- gdscript variant type or a class name, 
#                                  eg. int, String, SysDept, Dictionary
#column CDATA #REQUIRED ---------- changed from #IMPLED to #REQUIRED
#jdbcType CDATA #IMPLIED --------- ❌ not support
#typeHandler CDATA #IMPLIED ------ ❌ not support
#>
@warning_ignore("unused_parameter")
func _deal_result(item:GDSQL.GXMLItem, param: Dictionary, depth: int) -> GDSQL.GBatisResult:
	return GDSQL.GBatisResult.new(item.attrs)
	
#<!ELEMENT idArg EMPTY>
#<!ATTLIST idArg
#javaType CDATA #IMPLIED
#column CDATA #IMPLIED
#jdbcType CDATA #IMPLIED
#typeHandler CDATA #IMPLIED
#select CDATA #IMPLIED
#resultMap CDATA #IMPLIED
#name CDATA #IMPLIED
#columnPrefix CDATA #IMPLIED
#>  
## @deprecated ❌ not support
@warning_ignore("unused_parameter")
func _deal_id_arg(item:GDSQL.GXMLItem, param: Dictionary, depth: int):
	return ""
	
#<!ELEMENT arg EMPTY>
#<!ATTLIST arg
#javaType CDATA #IMPLIED
#column CDATA #IMPLIED
#jdbcType CDATA #IMPLIED
#typeHandler CDATA #IMPLIED
#select CDATA #IMPLIED
#resultMap CDATA #IMPLIED
#name CDATA #IMPLIED
#columnPrefix CDATA #IMPLIED
#> 
## @deprecated ❌ not support
@warning_ignore("unused_parameter")
func _deal_arg(item:GDSQL.GXMLItem, param: Dictionary, depth: int):
	var ret = ""
	return ret
	
#<!ELEMENT collection (constructor?,id*,result*,association*,collection*, discriminator?)>
#<!ATTLIST collection
#===============================================================================
#基本属性：
#property CDATA #REQUIRED ----------- property name
#javaType CDATA #IMPLIED ------------ ClassName
#                                     如果obj中的property属性没有定义是什么类型的对象，
#                                     则需要在此指定一下。
#ofType CDATA #IMPLIED -------------- 集合元素的java类型
#jdbcType CDATA #IMPLIED ------------ ❌ not support
#typeHandler CDATA #IMPLIED --------- ❌ not support
#===============================================================================
#集合的嵌套 Select 查询：
#column CDATA #IMPLIED -------------- associate column name. When using multiple 
#                                     resultset this attribute specifies the 
#                                     columns (separated by commas) that will be 
#                                     correlated with the foreignColumn to identify
#                                     the parent and the child of a relationship.
#                                     NOTICE column belongs to parent fetch.
#select CDATA #IMPLIED -------------- auto fetch data by configured <select>'s 
#                                     id when needed. If this attr is set, then 
#                                     NRM(Nested Result Mapping) which uses 
#                                     some `JOIN`s will not work.
#fetchType (lazy|eager) #IMPLIED ---- ❌ not support. INFO _get() will not be
#                                     called if properties are defined in 
#                                     Object. So we couldn't find a proper
#                                     way to achieve this lazy feature.
#
#                                     lazy: [default] fetch data when this 
#                                           property is getted;
#                                     eager: fetch data immediately.
#===============================================================================
#集合的嵌套结果映射：
#resultMap CDATA #IMPLIED ----------- configured result map.
#columnPrefix CDATA #IMPLIED -------- 当连接多个表时，你可能会不得不使用列别名来避免在 
#                                     ResultSet 中产生重复的列名。指定 columnPrefix 
#                                     列名前缀允许你将带有这些前缀的列映射到一个外部的
#                                     结果映射中。这在结果集中拥有多个相同类型的子对象时
#                                     很有用，可以共享同一个resultMap，但是又用前缀做了
#                                     区分。
#notNullColumn CDATA #IMPLIED ------- ❌ not support
#autoMapping (unset|true|false) #IMPLIED -- 是否继承全局自动映射等级。
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
#===============================================================================
#关联的多结果集（ResultSet）：---------- ❌ not support
#column CDATA #IMPLIED -------------- see above.
#resultSet CDATA #IMPLIED ----------- ❌ not support
#foreignColumn CDATA #IMPLIED ------- Identifies the name of the columns that 
#                                     contains the foreign keys which values 
#                                     will be matched against the values of the 
#                                     columns specified in the column attibute 
#                                     of the parent type.
#                                     NOTICE foreignColumn belongs to child fetch.
#>
func _deal_collection(item:GDSQL.GXMLItem, param: Dictionary, depth: int) -> GDSQL.GBatisCollection:
	var ret = GDSQL.GBatisCollection.new(item.attrs)
	ret.set_mapper_parser_ref(weakref(self))
	for i in item.content:
		if i is GDSQL.GXMLItem:
			if not ["constructor", "id", "result", "association", "collection", 
			"discriminator"].has(i.name):
				assert(false, "Invalid element %s in collection." % i.name)
				return null
			ret.push_element(_deal_element(i, param, depth+1))
	return ret
	
#<!ELEMENT association (constructor?,id*,result*,association*,collection*, discriminator?)>
#<!ATTLIST association
#===============================================================================
#基本属性：
#property CDATA #REQUIRED ----------- property name
#javaType CDATA #IMPLIED ------------ ClassName
#                                     如果obj中的property属性没有定义是什么类型的对象，
#                                     则需要在此指定一下。
#jdbcType CDATA #IMPLIED ------------ ❌ not support
#typeHandler CDATA #IMPLIED --------- ❌ not support
#===============================================================================
#关联的嵌套 Select 查询：
#column CDATA #IMPLIED -------------- associate column name. When using multiple 
#                                     resultset this attribute specifies the 
#                                     columns (separated by commas) that will be 
#                                     correlated with the foreignColumn to identify
#                                     the parent and the child of a relationship.
#                                     NOTICE column belongs to parent fetch.
#select CDATA #IMPLIED -------------- auto fetch data by configured <select>'s 
#                                     id when needed. If this attr is set, then 
#                                     NRM(Nested Result Mapping) which uses 
#                                     some `JOIN`s will not work.
#fetchType (lazy|eager) #IMPLIED ---- ❌ not support. INFO _get() will not be
#                                     called if properties are defined in 
#                                     Object. So we couldn't find a proper
#                                     way to achieve this lazy feature.
#
#                                     lazy: [default] fetch data when this 
#                                           property is getted;
#                                     eager: fetch data immediately.
#===============================================================================
#关联的嵌套结果映射：
#resultMap CDATA #IMPLIED ----------- configured result map.
#columnPrefix CDATA #IMPLIED -------- 当连接多个表时，你可能会不得不使用列别名来避免在 
#                                     ResultSet 中产生重复的列名。指定 columnPrefix 
#                                     列名前缀允许你将带有这些前缀的列映射到一个外部的
#                                     结果映射中。这在结果集中拥有多个相同类型的子对象时
#                                     很有用，可以共享同一个resultMap，但是又用前缀做了
#                                     区分。
#notNullColumn CDATA #IMPLIED ------- ❌ not support
#autoMapping (unset|true|false) #IMPLIED -- 是否继承全局自动映射等级。
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
#===============================================================================
#关联的多结果集（ResultSet）：---------- ❌ not support
#column CDATA #IMPLIED -------------- see above.
#resultSet CDATA #IMPLIED ----------- ❌ not support
#foreignColumn CDATA #IMPLIED ------- Identifies the name of the columns that 
#                                     contains the foreign keys which values 
#                                     will be matched against the values of the 
#                                     columns specified in the column attibute 
#                                     of the parent type.
#                                     NOTICE foreignColumn belongs to child fetch.
#>
## 一对一关联
func _deal_association(item:GDSQL.GXMLItem, param: Dictionary, depth: int) -> GDSQL.GBatisAssociation:
	var ret = GDSQL.GBatisAssociation.new(item.attrs)
	ret.set_mapper_parser_ref(weakref(self))
	for i in item.content:
		if i is GDSQL.GXMLItem:
			if not ["constructor", "id", "result", "association", "collection", 
			"discriminator"].has(i.name):
				assert(false, "Invalid element %s in association." % i.name)
				return null
			ret.push_element(_deal_element(i, param, depth+1))
	return ret
	
#<!ELEMENT discriminator (case+)>
#<!ATTLIST discriminator
#column CDATA #REQUIRED
#javaType CDATA #REQUIRED ------- gdscript simple variant type. 
#                                 eg. int, String, bool
#jdbcType CDATA #IMPLIED -------- ❌ not support
#typeHandler CDATA #IMPLIED ----- ❌ not support
#> 
func _deal_discriminator(item:GDSQL.GXMLItem, param: Dictionary, depth: int) -> GDSQL.GBatisDiscriminator:
	var ret = GDSQL.GBatisDiscriminator.new(item.attrs)
	var case_values = []
	for i in item.content:
		if i is GDSQL.GXMLItem:
			if i.name != "case":
				assert(i, "Invalid element %s in discriminator." % i.name)
				return null
			var case_ret = _deal_case(i, param, depth+1)
			if case_values.has(case_ret.value):
				assert(false, "Duplicate value of child element <case>.")
				return null
			ret.push_element(case_ret)
	return ret
	
#<!ELEMENT case (constructor?,id*,result*,association*,collection*, discriminator?)>
#<!ATTLIST case
#value CDATA #REQUIRED
#resultMap CDATA #IMPLIED
#resultType CDATA #IMPLIED
#>
func _deal_case(item:GDSQL.GXMLItem, param: Dictionary, depth: int) -> GDSQL.GBatisCase:
	var result_map_id = item.attrs.get("resultMap", "").strip_edges() as String
	var result_type = item.attrs.get("resultType", "").strip_edges() as String
	if not (result_map_id.is_empty() or result_type.is_empty()):
		assert(false, "In <case>, cannot set resultMap and resultType at the same time.")
		return null
		
	var value = _get_value(item.attrs.get("value").strip_edges(), param, depth)
	var conf = {
		"value": value,
		"id": result_map_id,
		"type": result_type
	}
	var ret = GDSQL.GBatisCase.new(conf)
	ret.set_mapper_parser_ref(weakref(self))
	for i in item.content:
		if i is GDSQL.GXMLItem:
			if not ["constructor", "id", "result", "association", "collection", 
			"discriminator"].has(i.name):
				assert(false, "Invalid element %s in case." % i.name)
				return
			ret.push_element(_deal_element(i, param, depth+1))
	return ret
	
#<!ELEMENT property EMPTY>
#<!ATTLIST property
#name CDATA #REQUIRED
#value CDATA #REQUIRED
#> 
## @deprecated ❌ not support
@warning_ignore("unused_parameter")
func _deal_property(item:GDSQL.GXMLItem, param: Dictionary, depth: int):
	return ""
	
#<!ELEMENT typeAlias EMPTY>
#<!ATTLIST typeAlias
#alias CDATA #REQUIRED
#type CDATA #REQUIRED
#>
## @deprecated ❌ not support
@warning_ignore("unused_parameter")
func _deal_type_alias(item:GDSQL.GXMLItem, param: Dictionary, depth: int):
	return ""
	
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
	var valid_sub_items = ["include", "trim", "where", "set", "foreach", "choose", "if", "bind"]
	var binded_param = []
	var sql = _item_to_string(item, param, depth, valid_sub_items, binded_param)
	
	var ret = GDSQL.GBatisSelect.new(item.attrs)
	ret.set_mapper_parser_ref(weakref(self))
	ret.set_sql(sql)
	ret.set_method_return_info(method_return_info)
	#assert(not element_cache.has(ret.id), "Duplicate element id: %s." % ret.id)
	#element_cache[ret.id] = ret
	return ret
	
#<!ELEMENT insert (#PCDATA | selectKey | include | trim | where | set | foreach 
#| choose | if | bind)*>
#<!ATTLIST insert
#id CDATA #REQUIRED
#parameterMap CDATA #IMPLIED ------------------------ ❌ not support
#parameterType CDATA #IMPLIED ----------------------- ❌ not support
#timeout CDATA #IMPLIED ----------------------------- ❌ not support
#flushCache (true|false) #IMPLIED
#statementType (STATEMENT|PREPARED|CALLABLE) #IMPLIED ❌ not support
#useGeneratedKeys (true|false) #IMPLIED
#keyProperty CDATA #IMPLIED ------------------------- 由数据库内部生成的主键对应的对象
#                                                     的属性或字典的键，多个用逗号分割，
#                                                     配合useGeneratedKeys使用，如
#                                                     果useGeneratedKeys为true，但
#                                                     是未配置该特性，则默认属性和列名
#                                                     完全相同时，才进行设置。
#keyColumn CDATA #IMPLIED --------------------------- keyProperty对应的列名。如果
#                                                     property和column名称一样，可
#                                                     以省略该特性；否则请按照和
#                                                     keyProperty相同的顺序填写相应
#                                                     的列名。
#databaseId CDATA #IMPLIED
#lang CDATA #IMPLIED -------------------------------- ❌ not support
#> 
	var valid_sub_items = ["selectKey", "include", "trim", "where", "set", "foreach", "choose", "if", "bind"]
	var binded_param = []
	var sql = _item_to_string(item, param, depth, valid_sub_items, binded_param)
	
	var ret = GDSQL.GBatisInsert.new(item.attrs)
	ret.set_sql(sql)
	ret.set_method_return_info(method_return_info)
	if ret.use_generated_keys == "true" and param.size() == 2:
		for i in param:
			if i != BIND:
				if param[i] is Object or param[i] is Dictionary:
					ret.set_param_obj_or_dict(param[i])
				break
	#assert(not element_cache.has(ret.id), "Duplicate element id: %s." % ret.id)
	#element_cache[ret.id] = ret
	return ret
	
# NOTICE GBatis新增特性。mybatis原本不支持replace.
#<!ELEMENT replace (#PCDATA | selectKey | include | trim | where | set | foreach 
#| choose | if | bind)*>
#<!ATTLIST replace
#id CDATA #REQUIRED
#parameterMap CDATA #IMPLIED ------------------------ ❌ not support
#parameterType CDATA #IMPLIED ----------------------- ❌ not support
#timeout CDATA #IMPLIED ----------------------------- ❌ not support
#flushCache (true|false) #IMPLIED
#statementType (STATEMENT|PREPARED|CALLABLE) #IMPLIED ❌ not support
#useGeneratedKeys (true|false) #IMPLIED
#keyProperty CDATA #IMPLIED ------------------------- 由数据库内部生成的主键对应的对象
#                                                     的属性或字典的键，多个用逗号分割，
#                                                     配合useGeneratedKeys使用，如
#                                                     果useGeneratedKeys为true，但
#                                                     是未配置该特性，则默认属性和列名
#                                                     完全相同时，才进行设置。
#keyColumn CDATA #IMPLIED --------------------------- keyProperty对应的列名。如果
#                                                     property和column名称一样，可
#                                                     以省略该特性；否则请按照和
#                                                     keyProperty相同的顺序填写相应
#                                                     的列名。
#databaseId CDATA #IMPLIED
#lang CDATA #IMPLIED -------------------------------- ❌ not support
#> 
	var valid_sub_items = ["selectKey", "include", "trim", "where", "set", "foreach", "choose", "if", "bind"]
	var binded_param = []
	var sql = _item_to_string(item, param, depth, valid_sub_items, binded_param)
	
	var ret = GDSQL.GBatisReplace.new(item.attrs)
	ret.set_sql(sql)
	ret.set_method_return_info(method_return_info)
	if ret.use_generated_keys == "true" and param.size() == 2:
		for i in param:
			if i != BIND:
				if param[i] is Object or param[i] is Dictionary:
					ret.set_param_obj_or_dict(param[i])
				break
	#assert(not element_cache.has(ret.id), "Duplicate element id: %s." % ret.id)
	#element_cache[ret.id] = ret
	return ret
	
#<!ELEMENT selectKey (#PCDATA | include | trim | where | set | foreach | choose | if | bind)*>
#<!ATTLIST selectKey
#resultType CDATA #IMPLIED
#statementType (STATEMENT|PREPARED|CALLABLE) #IMPLIED
#keyProperty CDATA #IMPLIED
#keyColumn CDATA #IMPLIED
#order (BEFORE|AFTER) #IMPLIED
#databaseId CDATA #IMPLIED
#>  ❌ not support. You can set useGeneratedKeys="true" in <insert> or <replace>
@warning_ignore("unused_parameter")
func _deal_select_key(item:GDSQL.GXMLItem, param: Dictionary, depth: int):
	return ""
	
#<!ELEMENT update 
#(#PCDATA | selectKey | include | trim | where | set | foreach | choose | if | bind)*>
#<!ATTLIST update
#id CDATA #REQUIRED
#parameterMap CDATA #IMPLIED ------------------------ ❌ not support
#parameterType CDATA #IMPLIED ----------------------- ❌ not support
#timeout CDATA #IMPLIED ----------------------------- ❌ not support
#flushCache (true|false) #IMPLIED
#statementType (STATEMENT|PREPARED|CALLABLE) #IMPLIED ❌ not support
#keyProperty CDATA #IMPLIED ------------------------- ❌ not support
#useGeneratedKeys (true|false) #IMPLIED ------------- ❌ not support
#keyColumn CDATA #IMPLIED --------------------------- ❌ not support
#databaseId CDATA #IMPLIED
#lang CDATA #IMPLIED -------------------------------- ❌ not support
#>
	var valid_sub_items = ["selectKey", "include", "trim", "where", "set", "foreach", "choose", "if", "bind"]
	var binded_param = []
	var sql = _item_to_string(item, param, depth, valid_sub_items, binded_param)
	
	var ret = GDSQL.GBatisUpdate.new(item.attrs)
	ret.set_sql(sql)
	ret.set_method_return_info(method_return_info)
	#assert(not element_cache.has(ret.id), "Duplicate element id: %s." % ret.id)
	#element_cache[ret.id] = ret
	return ret
	
#<!ELEMENT delete (#PCDATA | include | trim | where | set | foreach | choose | if | bind)*>
#<!ATTLIST delete
#id CDATA #REQUIRED
#parameterMap CDATA #IMPLIED
#parameterType CDATA #IMPLIED
#timeout CDATA #IMPLIED
#flushCache (true|false) #IMPLIED
#statementType (STATEMENT|PREPARED|CALLABLE) #IMPLIED
#databaseId CDATA #IMPLIED
#lang CDATA #IMPLIED
#>
	var valid_sub_items = ["include", "trim", "where", "set", "foreach", "choose", "if", "bind"]
	var binded_param = []
	var sql = _item_to_string(item, param, depth, valid_sub_items, binded_param)
	
	var ret = GDSQL.GBatisDelete.new(item.attrs)
	ret.set_sql(sql)
	ret.set_method_return_info(method_return_info)
	#assert(not element_cache.has(ret.id), "Duplicate element id: %s." % ret.id)
	#element_cache[ret.id] = ret
	return ret
	
#<!ELEMENT include (property+)?>
#<!ATTLIST include
#refid CDATA #REQUIRED
#>
func _deal_include(item:GDSQL.GXMLItem, param: Dictionary, depth: int):
	var ref_item = _get_item(item.attrs.get("refid").strip_edges())
	var ret = _deal_element(ref_item, param, depth+1)
	if not (typeof(ret) == TYPE_STRING or (typeof(ret) == TYPE_ARRAY and ret.size() == 2)):
		assert(false, "Error occur.")
		return null
	if ret is Array:
		return ret[1]
	return ret
	
#<!ELEMENT bind EMPTY>
#<!ATTLIST bind
 #name CDATA #REQUIRED
 #value CDATA #REQUIRED
#>
func _deal_bind(item:GDSQL.GXMLItem, param: Dictionary, depth: int):
	var a_name = item.attrs.get("name").strip_edges() as String
	if param.has(a_name):
		assert(false, "Please change your bind param name %s which is occupied by method's param." % a_name)
		return null
	for d in param[BIND]:
		if param[BIND][d].has(a_name):
			assert(false, "Already bind this parameter: %s." % a_name)
			return null
			
	if not param[BIND].has(depth):
		param[BIND][depth] = {}
		
	var a_value = _get_value(item.attrs.get("value").strip_edges(), param, depth)
	param[BIND][depth][a_name] = a_value
	return ""
	
#<!ELEMENT sql (#PCDATA | include | trim | where | set | foreach | choose | if | bind)*>
#<!ATTLIST sql
#id CDATA #REQUIRED
#lang CDATA #IMPLIED -----------X
#databaseId CDATA #IMPLIED ----------X
#>
	var valid_sub_items = ["include", "trim", "where", "set", "foreach", "choose", "if", "bind"]
	var binded_param = []
	var ret = _item_to_string(item, param, depth, valid_sub_items, binded_param)
	#assert(not element_cache.has(ret.id), "Duplicate element id: %s." % ret.id)
	#element_cache[ret.id] = ret
	return ret
	
#<!ELEMENT trim (#PCDATA | include | trim | where | set | foreach | choose | if | bind)*>
#<!ATTLIST trim
#prefix CDATA #IMPLIED 表示在trim包裹的SQL语句前面添加的指定内容。
#suffix CDATA #IMPLIED 表示在trim包裹的SQL末尾添加指定内容
#prefixOverrides CDATA #IMPLIED 表示去掉（覆盖）trim包裹的SQL的指定首部内容
#suffixOverrides CDATA #IMPLIED 表示去掉（覆盖）trim包裹的SQL的指定尾部内容
#>
	var valid_sub_items = ["include", "trim", "where", "set", "foreach", "choose", "if", "bind"]
	var binded_param = []
	var ret = _item_to_string(item, param, depth, valid_sub_items, binded_param)
	
	var prefix = item.attrs.get("prefix", "") as String
	var prefixOverrides = item.attrs.get("prefixOverrides", "") as String
	var suffix = item.attrs.get("suffix", "") as String
	var suffixOverrides = item.attrs.get("suffixOverrides", "") as String
	
	if not prefix.is_empty():
		ret = prefix + ret
	if not prefixOverrides.is_empty() and ret.begins_with(prefixOverrides):
		ret = ret.substr(prefixOverrides.length())
	if not suffix.is_empty():
		ret += suffix
	if not suffixOverrides.is_empty() and ret.ends_with(suffixOverrides):
		ret = ret.substr(0, ret.length() - suffixOverrides.length())
	_clear_binded_param(depth+1, binded_param, param)
	return ret
	
#<!ELEMENT where (#PCDATA | include | trim | where | set | foreach | choose | if | bind)*>
	var valid_sub_items = ["include", "trim", "where", "set", "foreach", "choose", "if", "bind"]
	var binded_param = []
	var ret = _item_to_string(item, param, depth, valid_sub_items, binded_param)
	
	if ret.countn("and", 0, 3) > 0:
		ret = ret.substr(3)
	elif ret.countn("or", 0, 2) > 0:
		ret = ret.substr(2)
	ret = _combine("where", ret)
	_clear_binded_param(depth+1, binded_param, param)
	return ret
	
#<!ELEMENT set (#PCDATA | include | trim | where | set | foreach | choose | if | bind)*>
	var valid_sub_items = ["include", "trim", "where", "set", "foreach", "choose", "if", "bind"]
	var binded_param = []
	var ret = _item_to_string(item, param, depth, valid_sub_items, binded_param)
	
	if ret.ends_with(","):
		ret = ret.substr(0, ret.length()-1)
	ret = _combine("set", ret)
	_clear_binded_param(depth+1, binded_param, param)
	return ret
	
#<!ELEMENT foreach (#PCDATA | include | trim | where | set | foreach | choose | if | bind)*>
#<!ATTLIST foreach
#collection CDATA #REQUIRED 指定要遍历的集合或数组的变量名称
#item CDATA #IMPLIED 设置每次迭代变量的名称
#index CDATA #IMPLIED 若遍历的是list，index代表下标；若遍历的是map，index代表键
#open CDATA #IMPLIED 设置循环体的开始内容
#close CDATA #IMPLIED 设置循环体的结束内容
#separator CDATA #IMPLIED 设置每一次循环之间的分隔符
#>
func _deal_foreach(item:GDSQL.GXMLItem, param: Dictionary, depth: int):
	var ret = ""
	var binded_param = []
	var collection = _get_value(item.attrs.get("collection").strip_edges(), param, depth)
	if collection == null:
		assert(false, "Not found collection: %s" % item.attrs.get("collection"))
		return null
	if not (typeof(collection) == TYPE_ARRAY or typeof(collection) == TYPE_DICTIONARY):
		assert(false, "collection must be an Array or a Dictionary.")
		return null
	var is_array = typeof(collection) == TYPE_ARRAY
	
	var e_item = item.attrs.get("item", "").strip_edges() as String
	if param.has(e_item):
		assert(false, "Please change your bind param name %s which is occupied by method's param." % e_item)
		return null
	for d in param[BIND]:
		if param[BIND][d].has(e_item):
			assert(false, "Already bind this parameter: %s." % e_item)
			
	var e_index = item.attrs.get("index", "").strip_edges() as String
	if param.has(e_index):
		assert(false, "Please change your bind param name %s which is occupied by method's param." % e_index)
		return null
	for d in param[BIND]:
		if param[BIND][d].has(e_index):
			assert(false, "Already bind this parameter: %s." % e_index)
			return null
			
	var e_open = item.attrs.get("open", "") as String
	var e_close = item.attrs.get("close", "") as String
	var e_separator = item.attrs.get("separator", "") as String
	
	for i in item.content:
		ret = _combine(ret, e_open)
		var index = -1
		for e in collection:
			index += 1
			# 模拟bind的行为，相当于临时bind
			if not param[BIND].has(depth+1):
				param[BIND][depth+1] = {}
			if not e_item.is_empty():
				param[BIND][depth+1][e_item] = e if is_array else collection[e]
			if not e_index.is_empty():
				param[BIND][depth+1][e_index] = index if is_array else e
				
			if i is GDSQL.GXMLItem:
				if not ["include", "trim", "where", "set", "foreach", "choose", 
				"if", "bind"].has(i.name):
					assert(false, "Invalid element %s in foreach." % i.name)
					return null
				_record_binded_param(i, binded_param)
				ret = _combine(ret, _deal_element(i, param, depth+1))
			else:
				ret = _combine_pcdata(ret, i, param, depth)
				
			# 去掉临时的bind
			if not e_item.is_empty():
				param[BIND][depth+1].erase(e_item)
			if not e_index.is_empty():
				param[BIND][depth+1].erase(e_index)
				
			if index < collection.size() - 1:
				ret = _combine(ret, e_separator)
		ret = _combine(ret, e_close)
	_clear_binded_param(depth+1, binded_param, param)
	return ret
	
#<!ELEMENT choose (when* , otherwise?)>
func _deal_choose(item:GDSQL.GXMLItem, param: Dictionary, depth: int):
	var ret = ""
	for i in item.content:
		# 只能从里边取一个
		var otherwise_flag = false
		if i is GDSQL.GXMLItem:
			if not ["when", "otherwise"].has(i.name):
				assert(false, "Invalid element %s in choose." % i.name)
				return null
			if otherwise_flag:
				assert(false, "Otherwise element should be the last one element and can at most exist once.")
				return null
			if i.name == "otherwise":
				otherwise_flag = true
			var info = _deal_element(i, param, depth+1)
			if info and info[0]:
				ret = _combine(ret, info[1])
				break
	return ret
	
#<!ELEMENT when (#PCDATA | include | trim | where | set | foreach | choose | if | bind)*>
#<!ATTLIST when
#test CDATA #REQUIRED
#>
func _deal_when(item:GDSQL.GXMLItem, param: Dictionary, depth: int):
	var test = _get_value(item.attrs.get("test"), param, depth)
	if not test:
		return [false, ""]
		
	var ret = ""
	var binded_param = []
	for i in item.content:
		if i is GDSQL.GXMLItem:
			if not ["include", "trim", "where", "set", "foreach", "choose", 
			"if", "bind"].has(i.name):
				assert(false, "Invalid element %s in when." % i.name)
				return null
			_record_binded_param(i, binded_param)
			ret = _combine(ret, _deal_element(i, param, depth+1))
		else:
			ret = _combine_pcdata(ret, i, param, depth)
	_clear_binded_param(depth+1, binded_param, param)
	return [true, ret]
	
#<!ELEMENT otherwise (#PCDATA | include | trim | where | set | foreach | choose | if | bind)*>
	var valid_sub_items = ["include", "trim", "where", "set", "foreach", "choose", "if", "bind"]
	var binded_param = []
	var ret = _item_to_string(item, param, depth, valid_sub_items, binded_param)
	return ret
	
#<!ELEMENT if (#PCDATA | include | trim | where | set | foreach | choose | if | bind)*>
#<!ATTLIST if
#test CDATA #REQUIRED
#>
func _deal_if(item:GDSQL.GXMLItem, param: Dictionary, depth: int):
	var test = _get_value(item.attrs.get("test"), param, depth)
	if not test:
		return ""
		
	var valid_sub_items = ["include", "trim", "where", "set", "foreach", "choose", "if", "bind"]
	var binded_param = []
	var ret = _item_to_string(item, param, depth, valid_sub_items, binded_param)
	return ret
	
func _combine(s1: String, s2: String) -> String:
	s2 = _cast_null(s2).strip_edges()
	if s1.is_empty():
		return s2
	if s2.is_empty():
		return s1
	return s1 + " " + s2
	
## 拼接，但是会将s2中的占位符替换成真实数据. depth表示s2的深度
func _combine_pcdata(s1: String, s2: String, param: Dictionary, depth: int) -> String:
	s2 = _cast_null(s2).strip_edges()
	if s2.is_empty():
		return s1
	s2 = _replace_param(s2, param, depth)
	return s1 + " " + s2
	
func _cast_null(value) -> String:
	return "" if typeof(value) == TYPE_NIL else value
	
## 替换占位符
func _replace_param(s: String, param: Dictionary, depth: int) -> String:
	# 支持的格式： #{ roleId } ${   rrrr} #   { user . roleId } ${list[0} ${bea.abc[ 33 ]}  ${map[a]}
	# 一些例子：
	#aaa 1:[#   { ]	2:[user.roleId ]	3:[]	4:[]
	#bbb [#   { user.roleId } ]
	#aaa 1:[$ {]	2:[bea[ 0 ].abc[ 33 ][5].ee[8][mm]]	3:[]	4:[]
	#bbb [$ {bea[ 0 ].abc[ 33 ][5].ee[8][mm]} ]
	#aaa 1:[${  ]	2:[test .rrrr]	3:[]	4:[]
	#bbb [${  test .rrrr}
				#]
	#aaa 1:[#   
				#{]	2:[loginName   ]	3:[]	4:[]
	#bbb [#   
				#{loginName   }]
	var matches = re_placeholder.search_all(s) # 4个匹配项（其中第3、4个始终为空字符串）
	if matches.is_empty():
		return s
	var unique_matches = {}
	for i in matches:
		var k = i.get_string(0).strip_edges()
		if not unique_matches.has(k):
			unique_matches[k] = i
			
	for k: String in unique_matches:
		var prop = (unique_matches[k] as RegExMatch).get_string(2).strip_edges()
		#var value = null # 被替换的值
		#if prop.contains(".") or prop.contains("["):
			#assert(not prop.ends_with("."), "Error near: %s" % prop)
			#assert(not prop.ends_with("[]"), "Error near: %s" % prop)
			#assert(prop.count("[") == prop.count("]"), "`[` and `]` not match. Near: %s" % prop)
			#prop = prop.replace("\t", "").replace(" ", "")
			#assert(not prop.contains(".["), "Error near: %s" % prop)
			#
			#var splits_matches = re_split.search_all(prop)
			#var splits = []
			#for i in splits_matches:
				#var key = i.get_string().strip_edges()
				#if not key.is_empty():
					#splits.push_back(key)
			#var param_name = splits[0]
			#assert(param.has(param_name), "Not found param: %s." % param_name)
			#value = param[param_name]
			#var index = 0
			#while splits.size() > index:
				#index += 1
				#var key = splits[index] as String
				#if value is Dictionary:
					#if value.has(key):
						#value = value.get(key)
					#elif str(key.to_float()) == key and value.has(key.to_float()):
						#value = value.get(key.to_float())
					#elif str(key.to_int()) == key and value.has(key.to_int()):
						#value = value.get(key.to_int())
					#else:
						#assert(false, "Invalid index: %s of %s" % [prop, param_name])
				#elif value is Object:
					#assert(key.is_valid_identifier(), "Invalid index: %s of %s" % [prop, param_name])
					#value = value.get(key)
				#elif value is Array:
					#assert(str(key.to_int()) == key, "Invalid index: %s of %s" % [prop, param_name])
					#value = value[key]
				#else:
					#assert(false, "Invalid index: %s of %s" % [prop, param_name])
		#else:
			#if param.get(BIND).has(prop):
				#value = param.get(BIND).get(prop)
			#else:
				#assert(param.size() == 2, "Please specify the owner of property: %s" % prop)
				#for key in param:
					#if key != BIND:
						#assert(param.get(key).has(prop), "Invalid index: %s of %s" % [prop, key])
						#value = param[key][prop]
						#break
						
		# 上面的实现方法比较复杂，有更简单的，如下
		var names = []
		var values = []
		var obj_maybe = null
		for i in param:
			if i == BIND:
				for d in param[BIND]:
					if depth <= d:
						for n in param[BIND][d]:
							names.push_back(n)
							values.push_back(param[BIND][d][n])
			else:
				if param.size() == 2:
					if param[i] is Object:
						obj_maybe = param[i]
					elif param[i] is Dictionary:
						for key in param[i]:
							names.push_back(key)
							values.push_back(param[i][key])
					else:
						names.push_back(i)
						values.push_back(param[i])
				else:
					names.push_back(i)
					values.push_back(param[i])
		var value = null
		if obj_maybe:
			value = GDSQL.GDSQLUtils.evaluate_command(obj_maybe, prop, names, values)
		else:
			value = GDSQL.GDSQLUtils.evaluate_command(null, prop, names, values)
			
		if k.begins_with("$"):
			s = s.replace(k, str(value))
		else:
			s = s.replace(k, var_to_str(value))
	return s
	
func _record_binded_param(item: GDSQL.GXMLItem, record_arr: Array):
	if item.name == "bind":
		record_arr.push_back(item.attrs.get("name").strip_edges())
		
func _clear_binded_param(depth: int, record_arr: Array, param: Dictionary):
	if param[BIND].has(depth):
		for i in record_arr:
			param[BIND][depth].erase(i)
	record_arr.clear()
	
func _get_value(value_string: String, param: Dictionary, depth: int):
	var names = []
	var values = []
	var obj_maybe = null
	for i in param:
		if i == BIND:
			for d in param[BIND]:
				if depth <= d:
					for n in param[BIND][d]:
						names.push_back(n)
						values.push_back(param[BIND][d][n])
		else:
			if param.size() == 2:
				if param[i] is Object:
					obj_maybe = param[i]
				elif param[i] is Dictionary:
					for key in param[i]:
						names.push_back(key)
						values.push_back(param[i][key])
				else:
					names.push_back(i)
					values.push_back(param[i])
			else:
				names.push_back(i)
				values.push_back(param[i])
				
	if obj_maybe:
		return GDSQL.GDSQLUtils.evaluate_command(obj_maybe, value_string, names, values)
	return GDSQL.GDSQLUtils.evaluate_command(null, value_string, names, values)
