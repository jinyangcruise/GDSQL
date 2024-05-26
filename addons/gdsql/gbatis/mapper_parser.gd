@tool
extends RefCounted
## 一个解析mapper xml的工具。解析规则参考:
## @see https://mybatis.org/mybatis-3/sqlmap-xml.html
## @see http://mybatis.org/dtd/mybatis-3-mapper.dtd
class_name GBatisMapperParser

@export_enum("NONE", "PARTIAL", "FULL") 
## 全局自动映射等级。
## NONE - disables auto-mapping. Only manually mapped properties will be set.
## PARTIAL - will auto-map results except those that have nested result mappings 
##           defined inside (joins).
##           当全局自动映射级别设置为 PARTIAL 时，MyBatis 会对简单类型进行自动映射，
##           但不会对复杂类型（如嵌套的对象，也就是association和collection）进行自动映射，
##           除非显式地指定。
##           例如：虽然A表也有id，Author属性也有id，但是不会把结果集中的id赋值给Auther。
##           <select id="selectBlog" resultMap="blogResult">
##               select
##                 B.id,
##                 B.title,
##                 A.username,
##               from Blog B left outer join Author A on B.author_id = A.id
##               where B.id = #{id}
##           </select>
##           <resultMap id="blogResult" type="Blog">
##               <association property="author" resultMap="authorResult"/>
##           </resultMap>
##           <resultMap id="authorResult" type="Author">
##             <result property="username" column="author_username"/>
##           </resultMap>
## FULL - auto-maps everything.
var auto_mapping_level: String = "PARTIAL"

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
		config = val
		var validator = GBatisMapperValidator.new()
		validator.validate(config)
		if not validator.err.is_empty():
			push_error("\n".join(validator.err))
			
## TODO 等官方支持可变参数数量函数时，可以进行优化
## https://github.com/godotengine/godot/pull/82808
## btw: Ability to print and log script backtraces
## https://github.com/godotengine/godot/pull/91006
func query(method_id: String, param: Dictionary) -> QueryResult:
	param[BIND] = {}
	var item = _get_item(method_id)
	assert(item, "not found this method: %s" % method_id)
	match item.name:
		"select":
			return _deal_select(item, param, 0).query()
		"update":
			return _deal_update(item, param, 0).query()
		"insert":
			return _deal_insert(item, param, 0).query()
		"replace":
			return _deal_replace(item, param, 0).query()
		"delete":
			return _deal_delete(item, param, 0).query()
		_:
			assert(false, "method must be one of select, insert, update and delete.")
			return null
	
func _get_item(id: String) -> GXMLItem:
	for i in config.root_item.content:
		if i is GXMLItem and (i as GXMLItem).attrs.get("id", "") == id:
			return i
	return null
	
func _deal_element(item:GXMLItem, param: Dictionary, depth: int):
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
			#return _deal_select(item, null)
			pass
		"insert":
			#return _deal_insert(item, null)
			pass
		"replace":
			#return _deal_replace(item, null)
			pass
		"selectKey":
			return _deal_select_key(item, param, depth)
		"update":
			#return _deal_update(item, null)
			pass
		"delete":
			#return _deal_delete(item, null)
			pass
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
func _deal_cache_ref(item:GXMLItem, param: Dictionary, depth: int):
	return ""
	
#<!ELEMENT cache (property*)>
#<!ATTLIST cache
#type CDATA #IMPLIED ------------- ❌ not support
#eviction CDATA #IMPLIED --------- 缓存回收策略，可以不设置，默认值为 FIFO，表示先进先出
#                                  策略。其他可能的值包括 LRU（最近最少使用）、
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
func _deal_cache(item:GXMLItem, param: Dictionary, depth: int) -> GBatisCache:
	return GBatisCache.new(item.attrs)
	
#<!ELEMENT parameterMap (parameter+)?>
#<!ATTLIST parameterMap
#id CDATA #REQUIRED
#type CDATA #REQUIRED
#>
## @deprecated ❌ not support
@warning_ignore("unused_parameter")
func _deal_parameter_map(item:GXMLItem, param: Dictionary, depth: int):
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
func _deal_parameter(item:GXMLItem, param: Dictionary, depth: int):
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
func _deal_result_map(item:GXMLItem, param: Dictionary, depth: int) -> GBatisResultMap:
	var ret = GBatisResultMap.new(item.attrs)
	for i in item.content:
		if i is GXMLItem:
			assert(["constructor", "id", "result", "association", "collection", 
			"discriminator"].has(i.name), "Invalid element %s in resultMap." % i.name)
			ret.push_element(_deal_element(i, param, depth+1))
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
func _deal_id(item:GXMLItem, param: Dictionary, depth: int) -> GBatisId:
	return GBatisId.new(item.attrs)
	
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
func _deal_result(item:GXMLItem, param: Dictionary, depth: int) -> GBatisResult:
	return GBatisResult.new(item.attrs)
	
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
func _deal_id_arg(item:GXMLItem, param: Dictionary, depth: int):
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
func _deal_arg(item:GXMLItem, param: Dictionary, depth: int):
	var ret = ""
	return ret
	
#<!ELEMENT collection (constructor?,id*,result*,association*,collection*, discriminator?)>
#<!ATTLIST collection
#property CDATA #REQUIRED
#column CDATA #IMPLIED
#javaType CDATA #IMPLIED ------------ ❌ not need
#ofType CDATA #IMPLIED
#jdbcType CDATA #IMPLIED ------------ ❌ not support
#select CDATA #IMPLIED
#resultMap CDATA #IMPLIED
#typeHandler CDATA #IMPLIED --------- ❌ not support
#notNullColumn CDATA #IMPLIED ------- ❌ not support
#columnPrefix CDATA #IMPLIED -------- ❌ not support
#resultSet CDATA #IMPLIED ----------- ❌ not support
#foreignColumn CDATA #IMPLIED
#autoMapping (unset|true|false) #IMPLIED
#fetchType (lazy|eager) #IMPLIED ---- ❌ not support. INFO _get() will not be
#                                        called if properties are defined in 
#                                        Object. So we couldn't find a proper
#                                        way to achieve this feature.
#>
func _deal_collection(item:GXMLItem, param: Dictionary, depth: int) -> GBatisCollection:
	var ret = GBatisCollection.new(item.attrs)
	for i in item.content:
		if i is GXMLItem:
			assert(["constructor", "id", "result", "association", "collection", 
			"discriminator"].has(i.name), "Invalid element %s in collection." % i.name)
			ret.push_element(_deal_element(i, param, depth+1))
	return ret
	
#<!ELEMENT association (constructor?,id*,result*,association*,collection*, discriminator?)>
#<!ATTLIST association
#property CDATA #REQUIRED ----------- property name
#column CDATA #IMPLIED -------------- associate column name. When using multiple 
#                                     resultset this attribute specifies the 
#                                     columns (separated by commas) that will be 
#                                     correlated with the foreignColumn to identify
#                                     the parent and the child of a relationship.
#                                     NOTICE column belongs to parent fetch.
#javaType CDATA #IMPLIED ------------ gdscript variant type or a class name, 
#                                     eg. int, String, SysDept, Dictionary
#jdbcType CDATA #IMPLIED ------------ ❌ not support
#select CDATA #IMPLIED -------------- auto fetch data by configured <select>'s 
#                                     id when needed. If this attr is set, then 
#                                     NRM(Nested Result Mapping) which uses 
#                                     some `JOIN`s will not work.
#resultMap CDATA #IMPLIED ----------- configured result map.
#typeHandler CDATA #IMPLIED --------- ❌ not support
#notNullColumn CDATA #IMPLIED ------- ❌ not support
#columnPrefix CDATA #IMPLIED -------- ❌ not support
#resultSet CDATA #IMPLIED ----------- ❌ not support
#foreignColumn CDATA #IMPLIED ------- Identifies the name of the columns that 
#                                     contains the foreign keys which values 
#                                     will be matched against the values of the 
#                                     columns specified in the column attibute 
#                                     of the parent type.
#                                     NOTICE foreignColumn belongs to child fetch.
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
#fetchType (lazy|eager) #IMPLIED ---- ❌ not support. INFO _get() will not be
#                                     called if properties are defined in 
#                                     Object. So we couldn't find a proper
#                                     way to achieve this lazy feature.
#
#                                     lazy: [default] fetch data when this 
#                                           property is getted;
#                                     eager: fetch data immediately.
#>
## 一对一关联
func _deal_association(item:GXMLItem, param: Dictionary, depth: int) -> GBatisAssociation:
	var ret = GBatisAssociation.new(item.attrs)
	for i in item.content:
		if i is GXMLItem:
			assert(["constructor", "id", "result", "association", "collection", 
			"discriminator"].has(i.name), "Invalid element %s in association." % i.name)
			ret.push_element(_deal_element(i, param, depth+1))
	return ret
	
#<!ELEMENT discriminator (case+)>
#<!ATTLIST discriminator
#column CDATA #REQUIRED
#javaType CDATA #REQUIRED ------------ gdscript variant type or a class name, 
#                                     eg. int, String, SysDept, Dictionary
#jdbcType CDATA #IMPLIED -------- ❌ not support
#typeHandler CDATA #IMPLIED ----- ❌ not support
#> 
func _deal_discriminator(item:GXMLItem, param: Dictionary, depth: int) -> GBatisDiscriminator:
	var ret = GBatisDiscriminator.new(item.attrs)
	var case_values = []
	for i in item.content:
		if i is GXMLItem:
			assert(i.name == "case", "Invalid element %s in discriminator." % i.name)
			var case_ret = _deal_case(i, param, depth+1)
			assert(not case_values.has(case_ret.value), 
				"Duplicate value of child element <case>.")
			ret.push_element(case_ret)
	return ret
	
#<!ELEMENT case (constructor?,id*,result*,association*,collection*, discriminator?)>
#<!ATTLIST case
#value CDATA #REQUIRED
#resultMap CDATA #IMPLIED
#resultType CDATA #IMPLIED
#>
func _deal_case(item:GXMLItem, param: Dictionary, depth: int) -> GBatisCase:
	var result_map_id = item.attrs.get("resultMap", "").strip_edges() as String
	var result_type = item.attrs.get("resultType", "").strip_edges() as String
	assert(result_map_id.is_empty() or result_type.is_empty(), 
		"In <case>, cannot set resultMap and resultType at the same time.")
		
	var value = _get_value(item.attrs.get("value").strip_edges(), param, depth)
	var conf = {
		"value": value,
		"id": result_map_id,
		"type": result_type
	}
	var ret = GBatisCase.new(conf)
	for i in item.content:
		if i is GXMLItem:
			assert(["constructor", "id", "result", "association", "collection", 
				"discriminator"].has(i.name), "Invalid element %s in case." % i.name)
			assert(not (result_map_id+result_type).is_empty(), 
				"Already set resultMap or resultType in <case>.")
			ret.push_element(_deal_element(i, param, depth+1))
	return ret
	
#<!ELEMENT property EMPTY>
#<!ATTLIST property
#name CDATA #REQUIRED
#value CDATA #REQUIRED
#> 
## @deprecated ❌ not support
@warning_ignore("unused_parameter")
func _deal_property(item:GXMLItem, param: Dictionary, depth: int):
	return ""
	
#<!ELEMENT typeAlias EMPTY>
#<!ATTLIST typeAlias
#alias CDATA #REQUIRED
#type CDATA #REQUIRED
#>
## @deprecated ❌ not support
@warning_ignore("unused_parameter")
func _deal_type_alias(item:GXMLItem, param: Dictionary, depth: int):
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
#fetchSize CDATA #IMPLIED
#timeout CDATA #IMPLIED
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
func _deal_select(item:GXMLItem, param: Dictionary, depth: int) -> GBatisSelect:
	var sql = ""
	var binded_param = []
	for i in item.content:
		if i is GXMLItem:
			assert(["include", "trim", "where", "set", "foreach", "choose", 
				"if", "bind"].has(i.name), "Invalid element %s in select." % i.name)
			_record_binded_param(i, binded_param)
			sql = _combine(sql, _deal_element(i, param, depth+1))
		else:
			sql = _combine_pcdata(sql, i, param, depth+1)
	_clear_binded_param(depth+1, binded_param, param)
	
	var ret = GBatisSelect.new(item.attrs)
	ret.set_sql(sql)
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
#keyProperty CDATA #IMPLIED ------------------------- ❌ not support
#useGeneratedKeys (true|false) #IMPLIED
#keyColumn CDATA #IMPLIED --------------------------- ❌ not support
#databaseId CDATA #IMPLIED
#lang CDATA #IMPLIED -------------------------------- ❌ not support
#> 
func _deal_insert(item:GXMLItem, param: Dictionary, depth: int) -> GBatisInsert:
	var sql = ""
	var binded_param = []
	for i in item.content:
		if i is GXMLItem:
			assert(["selectKey", "include", "trim", "where", "set", "foreach", 
			"choose", "if", "bind"].has(i.name), "Invalid element %s in insert." % i.name)
			_record_binded_param(i, binded_param)
			sql = _combine(sql, _deal_element(i, param, depth+1))
		else:
			sql = _combine_pcdata(sql, i, param, depth)
	_clear_binded_param(depth+1, binded_param, param)
	
	var ret = GBatisInsert.new(item.attrs)
	ret.set_sql(sql)
	return ret
	
# NOTICE mybatis原本不支持replace.
#<!ELEMENT replace (#PCDATA | selectKey | include | trim | where | set | foreach 
#| choose | if | bind)*>
#<!ATTLIST replace
#id CDATA #REQUIRED
#parameterMap CDATA #IMPLIED ------------------------ ❌ not support
#parameterType CDATA #IMPLIED ----------------------- ❌ not support
#timeout CDATA #IMPLIED ----------------------------- ❌ not support
#flushCache (true|false) #IMPLIED
#statementType (STATEMENT|PREPARED|CALLABLE) #IMPLIED ❌ not support
#keyProperty CDATA #IMPLIED ------------------------- ❌ not support
#useGeneratedKeys (true|false) #IMPLIED
#keyColumn CDATA #IMPLIED --------------------------- ❌ not support
#databaseId CDATA #IMPLIED
#lang CDATA #IMPLIED -------------------------------- ❌ not support
#>
func _deal_replace(item:GXMLItem, param: Dictionary, depth: int) -> GBatisReplace:
	var sql = ""
	var binded_param = []
	for i in item.content:
		if i is GXMLItem:
			assert(["selectKey", "include", "trim", "where", "set", "foreach", 
			"choose", "if", "bind"].has(i.name), "Invalid element %s in replace." % i.name)
			_record_binded_param(i, binded_param)
			sql = _combine(sql, _deal_element(i, param, depth+1))
		else:
			sql = _combine_pcdata(sql, i, param, depth)
	_clear_binded_param(depth+1, binded_param, param)
	
	var ret = GBatisReplace.new(item.attrs)
	ret.set_sql(sql)
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
func _deal_select_key(item:GXMLItem, param: Dictionary, depth: int):
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
func _deal_update(item:GXMLItem, param: Dictionary, depth: int) -> GBatisUpdate:
	var sql = ""
	var binded_param = []
	for i in item.content:
		if i is GXMLItem:
			assert(["selectKey", "include", "trim", "where", "set", "foreach", 
			"choose", "if", "bind"].has(i.name), 
			"Invalid element %s in the current context." % i.name)
			_record_binded_param(i, binded_param)
			sql = _combine(sql, _deal_element(i, param, depth+1))
		else:
			sql = _combine_pcdata(sql, i, param, depth)
	_clear_binded_param(depth+1, binded_param, param)
	
	var ret = GBatisUpdate.new(item.attrs)
	ret.set_sql(sql)
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
func _deal_delete(item:GXMLItem, param: Dictionary, depth: int) -> GBatisDelete:
	var sql = ""
	var binded_param = []
	for i in item.content:
		if i is GXMLItem:
			assert(["include", "trim", "where", "set", "foreach", "choose", 
			"if", "bind"].has(i.name), "Invalid element %s in delete." % i.name)
			_record_binded_param(i, binded_param)
			sql = _combine(sql, _deal_element(i, param, depth+1))
		else:
			sql = _combine_pcdata(sql, i, param, depth)
	_clear_binded_param(depth+1, binded_param, param)
	
	var ret = GBatisDelete.new(item.attrs)
	ret.set_sql(sql)
	return ret
	
#<!ELEMENT include (property+)?>
#<!ATTLIST include
#refid CDATA #REQUIRED
#>
func _deal_include(item:GXMLItem, param: Dictionary, depth: int) -> String:
	var ref_item = _get_item(item.attrs.get("refid").strip_edges())
	var ret = _deal_element(ref_item, param, depth+1)
	assert(typeof(ret) == TYPE_STRING or (typeof(ret) == TYPE_ARRAY and ret.size() == 2), 
		"Error occur.")
	if ret is Array:
		return ret[1]
	return ret
	
#<!ELEMENT bind EMPTY>
#<!ATTLIST bind
 #name CDATA #REQUIRED
 #value CDATA #REQUIRED
#>
func _deal_bind(item:GXMLItem, param: Dictionary, depth: int) -> String:
	var a_name = item.attrs.get("name").strip_edges() as String
	assert(not param.has(a_name), 
		"Please change your bind param name %s which is occupied by method's param." % a_name)
	for d in param[BIND]:
		assert(not param[BIND][d].has(a_name), "Already bind this parameter: %s." % a_name)
		
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
func _deal_sql(item:GXMLItem, param: Dictionary, depth: int) -> String:
	var ret = ""
	var binded_param = []
	for i in item.content:
		if i is GXMLItem:
			assert(["include", "trim", "where", "set", "foreach", "choose", 
			"if", "bind"].has(i.name), "Invalid element %s in sql." % i.name)
			_record_binded_param(i, binded_param)
			ret = _combine(ret, _deal_element(i, param, depth+1))
		else:
			ret = _combine_pcdata(ret, i, param, depth)
	_clear_binded_param(depth+1, binded_param, param)
	return ret
	
#<!ELEMENT trim (#PCDATA | include | trim | where | set | foreach | choose | if | bind)*>
#<!ATTLIST trim
#prefix CDATA #IMPLIED 表示在trim包裹的SQL语句前面添加的指定内容。
#prefixOverrides CDATA #IMPLIED 表示在trim包裹的SQL末尾添加指定内容
#suffix CDATA #IMPLIED 表示去掉（覆盖）trim包裹的SQL的指定首部内容
#suffixOverrides CDATA #IMPLIED 表示去掉（覆盖）trim包裹的SQL的指定尾部内容
#>
func _deal_trim(item:GXMLItem, param: Dictionary, depth: int) -> String:
	var ret = ""
	var binded_param = []
	for i in item.content:
		if i is GXMLItem:
			assert(["include", "trim", "where", "set", "foreach", "choose", 
			"if", "bind"].has(i.name), "Invalid element %s in trim." % i.name)
			_record_binded_param(i, binded_param)
			ret = _combine(ret, _deal_element(i, param, depth+1))
		else:
			ret = _combine_pcdata(ret, i, param, depth)
			
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
func _deal_where(item:GXMLItem, param: Dictionary, depth: int) -> String:
	var ret = ""
	var binded_param = []
	for i in item.content:
		if i is GXMLItem:
			assert(["include", "trim", "where", "set", "foreach", "choose", 
			"if", "bind"].has(i.name), "Invalid element %s in where." % i.name)
			_record_binded_param(i, binded_param)
			ret = _combine(ret, _deal_element(i, param, depth+1))
		else:
			ret = _combine_pcdata(ret, i, param, depth)
	if ret.countn("and", 0, 3) > 0:
		ret = ret.substr(3)
	elif ret.countn("or", 0, 2) > 0:
		ret = ret.substr(2)
	ret = _combine("where", ret)
	_clear_binded_param(depth+1, binded_param, param)
	return ret
	
#<!ELEMENT set (#PCDATA | include | trim | where | set | foreach | choose | if | bind)*>
func _deal_set(item:GXMLItem, param: Dictionary, depth: int) -> String:
	var ret = ""
	var binded_param = []
	for i in item.content:
		if i is GXMLItem:
			assert(["include", "trim", "where", "set", "foreach", "choose", 
			"if", "bind"].has(i.name), "Invalid element %s in set." % i.name)
			_record_binded_param(i, binded_param)
			ret = _combine(ret, _deal_element(i, param, depth+1))
		else:
			ret = _combine_pcdata(ret, i, param, depth)
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
func _deal_foreach(item:GXMLItem, param: Dictionary, depth: int) -> String:
	var ret = ""
	var binded_param = []
	var collection = _get_value(item.attrs.get("collection").strip_edges(), param, depth)
	assert(collection != null, "Not found collection: %s" % item.attrs.get("collection"))
	assert(typeof(collection) == TYPE_ARRAY or typeof(collection) == TYPE_DICTIONARY, 
		"collection must be an Array or a Dictionary.")
	var is_array = typeof(collection) == TYPE_ARRAY
	var e_item = item.attrs.get("item", "").strip_edges() as String
	var e_index = item.attrs.get("index", "").strip_edges() as String
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
				
			if i is GXMLItem:
				assert(["include", "trim", "where", "set", "foreach", "choose", 
				"if", "bind"].has(i.name), "Invalid element %s in foreach." % i.name)
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
func _deal_choose(item:GXMLItem, param: Dictionary, depth: int) -> String:
	var ret = ""
	for i in item.content:
		# 只能从里边取一个
		var otherwise_flag = false
		if i is GXMLItem:
			assert(["when", "otherwise"].has(i.name), "Invalid element %s in choose." % i.name)
			assert(not otherwise_flag, 
			"Otherwise element should be the last one element and can at most exist once.")
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
func _deal_when(item:GXMLItem, param: Dictionary, depth: int) -> Array:
	var test = _get_value(item.attrs.get("test"), param, depth)
	if not test:
		return [false, ""]
		
	var ret = ""
	var binded_param = []
	for i in item.content:
		if i is GXMLItem:
			assert(["include", "trim", "where", "set", "foreach", "choose", 
			"if", "bind"].has(i.name), "Invalid element %s in when." % i.name)
			_record_binded_param(i, binded_param)
			ret = _combine(ret, _deal_element(i, param, depth+1))
		else:
			ret = _combine_pcdata(ret, i, param, depth)
	_clear_binded_param(depth+1, binded_param, param)
	return [true, ret]
	
#<!ELEMENT otherwise (#PCDATA | include | trim | where | set | foreach | choose | if | bind)*>
func _deal_otherwise(item:GXMLItem, param: Dictionary, depth: int) -> Array:
	var ret = ""
	var binded_param = []
	for i in item.content:
		if i is GXMLItem:
			assert(["include", "trim", "where", "set", "foreach", "choose", 
			"if", "bind"].has(i.name), "Invalid element %s in otherwise." % i.name)
			_record_binded_param(i, binded_param)
			ret = _combine(ret, _deal_element(i, param, depth+1))
		else:
			ret = _combine_pcdata(ret, i, param, depth)
	_clear_binded_param(depth+1, binded_param, param)
	return ret
	
#<!ELEMENT if (#PCDATA | include | trim | where | set | foreach | choose | if | bind)*>
#<!ATTLIST if
#test CDATA #REQUIRED
#>
func _deal_if(item:GXMLItem, param: Dictionary, depth: int) -> String:
	var test = _get_value(item.attrs.get("test"), param, depth)
	if not test:
		return ""
		
	var ret = ""
	var binded_param = []
	for i in item.content:
		if i is GXMLItem:
			assert(["include", "trim", "where", "set", "foreach", "choose", 
			"if", "bind"].has(i.name), "Invalid element %s in if." % i.name)
			_record_binded_param(i, binded_param)
			ret = _combine(ret, _deal_element(i, param, depth+1))
		else:
			ret = _combine_pcdata(ret, i, param, depth)
	_clear_binded_param(depth+1, binded_param, param)
	return ret
	
func _combine(s1: String, s2: String) -> String:
	s2 = _cast_null(s2).strip_edges()
	if s1.is_empty():
		return s2
	if s2.is_empty():
		return s1
	return "%s %s" % [s1, s2]
	
## 拼接，但是会将s2中的占位符替换成真实数据. depth表示s2的深度
func _combine_pcdata(s1: String, s2: String, param: Dictionary, depth: int) -> String:
	s2 = _cast_null(s2).strip_edges()
	if s2.is_empty():
		return s1
	s2 = _replace_param(s2, param, depth)
	return "%s %s" % [s1, s2]
	
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
		for i in param:
			if i == BIND:
				for d in param[BIND]:
					if depth <= d:
						for n in param[BIND][d]:
							names.push_back(n)
							values.push_back(param[BIND][d][n])
			else:
				names.push_back(i)
				values.push_back(param[i])
		var value = GDSQLUtils.evaluate_command(null, prop, names, values)
		
		if k.begins_with("$"):
			s = s.replace(k, str(value))
		else:
			s = s.replace(k, var_to_str(value))
	return s
	
func _record_binded_param(item: GXMLItem, record_arr: Array):
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
	for i in param:
		if i == BIND:
			for d in param[BIND]:
				if depth <= d:
					for n in param[BIND][d]:
						names.push_back(n)
						values.push_back(param[BIND][d][n])
		else:
			names.push_back(i)
			values.push_back(param[i])
	return GDSQLUtils.evaluate_command(null, value_string, names, values)
	
