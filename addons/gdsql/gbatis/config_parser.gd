extends Resource
## 一个解析mapper xml的工具。解析规则参考:
## @see https://mybatis.org/mybatis-3/sqlmap-xml.html
## @see http://mybatis.org/dtd/mybatis-3-mapper.dtd
class_name GBatisConfigParser

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
		var validator = GBatisConfigValidator.new()
		validator.validate(config)
		if not validator.err.is_empty():
			push_error("\n".join(validator.err))
			
## TODO 等官方支持可变参数数量函数时，可以进行优化
## https://github.com/godotengine/godot/pull/82808
## btw: Ability to print and log script backtraces
## https://github.com/godotengine/godot/pull/91006
func query(method_id: String, param: Dictionary) -> QueryResult:
	param[BIND] = {}
	var item = get_item(method_id)
	assert(item, "not found this method: %s" % method_id)
	match item.name:
		"select":
			return deal_select(item, param, 0)
		"update":
			return deal_update(item, param, 0)
		"insert":
			return deal_insert(item, param, 0)
		"replace":
			return deal_replace(item, param, 0)
		"delete":
			return deal_delete(item, param, 0)
		_:
			assert(false, "method must be one of select, insert, update and delete.")
			return null
	
func get_item(id: String) -> GXMLItem:
	for i in config.root_item.content:
		if i is GXMLItem and (i as GXMLItem).attrs.get("id", "") == id:
			return i
	return null
	
func deal_element(item:GXMLItem, param: Dictionary, depth: int):
	if not item:
		return ""
	match item.name:
		"cache-ref":
			return deal_cache_ref(item, param, depth)
		"cache":
			return deal_cache(item, param, depth)
		"parameterMap":
			return deal_parameter_map(item, param, depth)
		"parameter":
			return deal_parameter(item, param, depth)
		"resultMap":
			return deal_result_map(item, param, depth)
		"id":
			return deal_id(item, param, depth)
		"result":
			return deal_result(item, param, depth)
		"idArg":
			return deal_id_arg(item, param, depth)
		"arg":
			return deal_arg(item, param, depth)
		"collection":
			return deal_collection(item, param, depth)
		"association":
			return deal_association(item, param, depth)
		"discriminator":
			return deal_discriminator(item, param, depth)
		"case":
			return deal_case(item, param, depth)
		"property":
			return deal_property(item, param, depth)
		"typeAlias":
			return deal_type_alias(item, param, depth)
		"select":
			#return deal_select(item, null)
			pass
		"insert":
			#return deal_insert(item, null)
			pass
		"replace":
			#return deal_replace(item, null)
			pass
		"selectKey":
			return deal_select_key(item, param, depth)
		"update":
			#return deal_update(item, null)
			pass
		"delete":
			#return deal_delete(item, null)
			pass
		"include":
			return deal_include(item, param, depth)
		"bind":
			return deal_bind(item, param, depth)
		"sql":
			return deal_sql(item, param, depth)
		"trim":
			return deal_trim(item, param, depth)
		"where":
			return deal_where(item, param, depth)
		"set":
			return deal_set(item, param, depth)
		"foreach":
			return deal_foreach(item, param, depth)
		"choose":
			return deal_choose(item, param, depth)
		"when":
			return deal_when(item, param, depth)
		"otherwise":
			return deal_otherwise(item, param, depth)
		"if":
			return deal_if(item, param, depth)
		_:
			return ""
			
#<!ELEMENT cache-ref EMPTY>
#<!ATTLIST cache-ref
#namespace CDATA #REQUIRED
#>
func deal_cache_ref(item:GXMLItem, param: Dictionary, depth: int):
	return ""
	
#<!ELEMENT cache (property*)>
#<!ATTLIST cache
#type CDATA #IMPLIED
#eviction CDATA #IMPLIED
#flushInterval CDATA #IMPLIED
#size CDATA #IMPLIED
#readOnly CDATA #IMPLIED
#blocking CDATA #IMPLIED
#>
func deal_cache(item:GXMLItem, param: Dictionary, depth: int):
	var ret = ""
	for i in item.content:
		if i is GXMLItem:
			assert(i.name == "property", "Invalid element %s in cache." % i.name)
			ret = combine(ret, deal_element(i, param, depth+1))
	return ret
		
#<!ELEMENT parameterMap (parameter+)?>
#<!ATTLIST parameterMap
#id CDATA #REQUIRED
#type CDATA #REQUIRED
#>
## @deprecated ❌ not support
func deal_parameter_map(item:GXMLItem, param: Dictionary, depth: int):
	var ret = ""
	for i in item.content:
		if i is GXMLItem:
			assert(i.name == "property", "Invalid element %s in parameterMap." % i.name)
			ret = combine(ret, deal_element(i, param, depth+1))
	return ret
	
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
func deal_parameter(item:GXMLItem, param: Dictionary, depth: int):
	return ""
	
#<!ELEMENT resultMap (constructor?,id*,result*,association*,collection*, discriminator?)>
#<!ATTLIST resultMap
#id CDATA #REQUIRED
#type CDATA #REQUIRED
#extends CDATA #IMPLIED
#autoMapping (true|false) #IMPLIED
#> TODO 
func deal_result_map(item:GXMLItem, param: Dictionary, depth: int):
	var ret = ""
	for i in item.content:
		if i is GXMLItem:
			assert(["constructor", "id", "result", "association", "collection", 
			"discriminator"].has(i.name), "Invalid element %s in resultMap." % i.name)
			ret = combine(ret, deal_element(i, param, depth+1))
	return ret
			
#<!ELEMENT id EMPTY>
#<!ATTLIST id
#property CDATA #IMPLIED
#javaType CDATA #IMPLIED
#column CDATA #IMPLIED
#jdbcType CDATA #IMPLIED
#typeHandler CDATA #IMPLIED
#> TODO
func deal_id(item:GXMLItem, param: Dictionary, depth: int):
	return ""
	
#<!ELEMENT result EMPTY>
#<!ATTLIST result
#property CDATA #IMPLIED
#javaType CDATA #IMPLIED
#column CDATA #IMPLIED
#jdbcType CDATA #IMPLIED
#typeHandler CDATA #IMPLIED
#> TODO
func deal_result(item:GXMLItem, param: Dictionary, depth: int):
	var ret = ""
	return ret
	
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
func deal_id_arg(item:GXMLItem, param: Dictionary, depth: int):
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
func deal_arg(item:GXMLItem, param: Dictionary, depth: int):
	var ret = ""
	return ret
	
#<!ELEMENT collection (constructor?,id*,result*,association*,collection*, discriminator?)>
#<!ATTLIST collection
#property CDATA #REQUIRED
#column CDATA #IMPLIED
#javaType CDATA #IMPLIED
#ofType CDATA #IMPLIED
#jdbcType CDATA #IMPLIED
#select CDATA #IMPLIED
#resultMap CDATA #IMPLIED
#typeHandler CDATA #IMPLIED
#notNullColumn CDATA #IMPLIED
#columnPrefix CDATA #IMPLIED
#resultSet CDATA #IMPLIED
#foreignColumn CDATA #IMPLIED
#autoMapping (true|false) #IMPLIED
#fetchType (lazy|eager) #IMPLIED
#> TODO
func deal_collection(item:GXMLItem, param: Dictionary, depth: int):
	# 不是返回字符串 WARNING
	var ret = ""
	for i in item.content:
		if i is GXMLItem:
			assert(["constructor", "id", "result", "association", "collection", 
			"discriminator"].has(i.name), "Invalid element %s in collection." % i.name)
			ret = combine(ret, deal_element(i, param, depth+1))
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
#javaType CDATA #IMPLIED ------------ gdscript variant type, eg. TYPE_INT
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
#autoMapping (true|false) #IMPLIED -- true: [default] automapp properties when 
#                                           related columns are selected but not 
#                                           configured;
#                                     false: do not automap columns to 
#                                            properties which are not configured.
#fetchType (lazy|eager) #IMPLIED ---- lazy: [default] fetch data when this 
#                                           property is getted;
#                                     eager: fetch data immediately.
#> TODO
func deal_association(item:GXMLItem, param: Dictionary, depth: int):
	var ret = ""
	for i in item.content:
		if i is GXMLItem:
			assert(["constructor", "id", "result", "association", "collection", 
			"discriminator"].has(i.name), "Invalid element %s in association." % i.name)
			ret = combine(ret, deal_element(i, param, depth+1))
	return ret
			
#<!ELEMENT discriminator (case+)>
#<!ATTLIST discriminator
#column CDATA #REQUIRED
#javaType CDATA #REQUIRED ------- actually means gdscript type eg. TYPE_INT, TYPE_STRING
#jdbcType CDATA #IMPLIED -------- not support
#typeHandler CDATA #IMPLIED ----- not support
#> 
func deal_discriminator(item:GXMLItem, param: Dictionary, depth: int) -> Dictionary:
	var column = item.attrs.get("column", "").strip_edges() as String
	var java_type = item.attrs.get("javaType", "").strip_edges() as String
	var ret = {}
	for i in item.content:
		if i is GXMLItem:
			assert(i.name == "case", "Invalid element %s in discriminator." % i.name)
			var case_ret = deal_element(i, param, depth+1)
			assert(not ret.has(case_ret.keys().front()), 
				"Duplicate value of child element <case>.")
			ret.merge(case_ret)
	return {
		"column": column,
		"type": java_type,
		"case": ret
	}
	
#<!ELEMENT case (constructor?,id*,result*,association*,collection*, discriminator?)>
#<!ATTLIST case
#value CDATA #REQUIRED
#resultMap CDATA #IMPLIED
#resultType CDATA #IMPLIED
#>
func deal_case(item:GXMLItem, param: Dictionary, depth: int) -> Dictionary:
	var result_map = item.attrs.get("resultMap", "").strip_edges() as String
	var result_type = item.attrs.get("resultType", "").strip_edges() as String
	assert(result_map.is_empty() or result_type.is_empty(), 
		"In <case>, cannot set resultMap and resultType at the same time.")
	var value = _get_value(item.attrs.get("value").strip_edges(), param, depth)
	var ret = result_map + result_type
	for i in item.content:
		if i is GXMLItem:
			assert(["constructor", "id", "result", "association", "collection", 
			"discriminator"].has(i.name), "Invalid element %s in case." % i.name)
			assert(not ret.is_empty(), "Already set resultMap or resultType in <case>.")
			ret = deal_element(i, param, depth+1)
	return {value: ret}
	
#<!ELEMENT property EMPTY>
#<!ATTLIST property
#name CDATA #REQUIRED
#value CDATA #REQUIRED
#> 
## @deprecated ❌ not support
func deal_property(item:GXMLItem, param: Dictionary, depth: int):
	return ""
	
#<!ELEMENT typeAlias EMPTY>
#<!ATTLIST typeAlias
#alias CDATA #REQUIRED
#type CDATA #REQUIRED
#>
## @deprecated ❌ not support
func deal_type_alias(item:GXMLItem, param: Dictionary, depth: int):
	return ""
	
#<!ELEMENT select (#PCDATA | include | trim | where | set | foreach | choose 
#| if | bind)*>
#<!ATTLIST select
#id CDATA #REQUIRED
#parameterMap CDATA #IMPLIED ------------------ not support
#parameterType CDATA #IMPLIED
#resultMap CDATA #IMPLIED
#resultType CDATA #IMPLIED
#resultSetType (FORWARD_ONLY | SCROLL_INSENSITIVE | SCROLL_SENSITIVE | DEFAULT) #IMPLIED
#statementType (STATEMENT|PREPARED|CALLABLE) #IMPLIED
#fetchSize CDATA #IMPLIED
#timeout CDATA #IMPLIED
#flushCache (true|false) #IMPLIED
#useCache (true|false) #IMPLIED
#databaseId CDATA #IMPLIED
#lang CDATA #IMPLIED
#resultOrdered (true|false) #IMPLIED
#resultSets CDATA #IMPLIED -------- Identifies the name of the result set where this complex type will be loaded from. eg. resultSets="blogs,authors"
#> TODO
func deal_select(item:GXMLItem, param: Dictionary, depth: int) -> QueryResult:
	var sql = ""
	var binded_param = []
	for i in item.content:
		if i is GXMLItem:
			assert(["include", "trim", "where", "set", "foreach", "choose", 
				"if", "bind"].has(i.name), "Invalid element %s in select." % i.name)
			_record_binded_param(i, binded_param)
			sql = combine(sql, deal_element(i, param, depth+1))
		else:
			sql = combine_pcdata(sql, i, param, depth+1)
			
	_clear_binded_param(depth+1, binded_param, param)
	var parameter_type = item.attrs.get("parameterType", 0)
	return null
	
#<!ELEMENT insert (#PCDATA | selectKey | include | trim | where | set | foreach 
#| choose | if | bind)*>
#<!ATTLIST insert
#id CDATA #REQUIRED
#parameterMap CDATA #IMPLIED
#parameterType CDATA #IMPLIED
#timeout CDATA #IMPLIED
#flushCache (true|false) #IMPLIED
#statementType (STATEMENT|PREPARED|CALLABLE) #IMPLIED
#keyProperty CDATA #IMPLIED
#useGeneratedKeys (true|false) #IMPLIED
#keyColumn CDATA #IMPLIED
#databaseId CDATA #IMPLIED
#lang CDATA #IMPLIED
#> TODO
func deal_insert(item:GXMLItem, param: Dictionary, depth: int):
	var ret = ""
	var binded_param = []
	for i in item.content:
		if i is GXMLItem:
			assert(["selectKey", "include", "trim", "where", "set", "foreach", 
			"choose", "if", "bind"].has(i.name), "Invalid element %s in insert." % i.name)
			_record_binded_param(i, binded_param)
			ret = combine(ret, deal_element(i, param, depth+1))
		else:
			ret = combine_pcdata(ret, i, param, depth)
	_clear_binded_param(depth+1, binded_param, param)
	return ret
	
# NOTICE mybatis原本不支持replace.
#<!ELEMENT replace (#PCDATA | selectKey | include | trim | where | set | foreach 
#| choose | if | bind)*>
#<!ATTLIST replace
#id CDATA #REQUIRED
#parameterMap CDATA #IMPLIED
#parameterType CDATA #IMPLIED
#timeout CDATA #IMPLIED
#flushCache (true|false) #IMPLIED
#statementType (STATEMENT|PREPARED|CALLABLE) #IMPLIED
#keyProperty CDATA #IMPLIED
#useGeneratedKeys (true|false) #IMPLIED
#keyColumn CDATA #IMPLIED
#databaseId CDATA #IMPLIED
#lang CDATA #IMPLIED
#> TODO
func deal_replace(item:GXMLItem, param: Dictionary, depth: int):
	var ret = ""
	var binded_param = []
	for i in item.content:
		if i is GXMLItem:
			assert(["selectKey", "include", "trim", "where", "set", "foreach", 
			"choose", "if", "bind"].has(i.name), "Invalid element %s in replace." % i.name)
			_record_binded_param(i, binded_param)
			ret = combine(ret, deal_element(i, param, depth+1))
		else:
			ret = combine_pcdata(ret, i, param, depth)
	_clear_binded_param(depth+1, binded_param, param)
	return ret
			
#<!ELEMENT selectKey (#PCDATA | include | trim | where | set | foreach | choose | if | bind)*>
#<!ATTLIST selectKey
#resultType CDATA #IMPLIED
#statementType (STATEMENT|PREPARED|CALLABLE) #IMPLIED
#keyProperty CDATA #IMPLIED
#keyColumn CDATA #IMPLIED
#order (BEFORE|AFTER) #IMPLIED
#databaseId CDATA #IMPLIED
#> TODO 自动填充自增主键
func deal_select_key(item:GXMLItem, param: Dictionary, depth: int):
	var ret = ""
	var binded_param = []
	for i in item.content:
		if i is GXMLItem:
			assert(["include", "trim", "where", "set", "foreach", "choose", 
			"if", "bind"].has(i.name), "Invalid element %s in selectKey." % i.name)
			_record_binded_param(i, binded_param)
			ret = combine(ret, deal_element(i, param, depth+1))
		else:
			ret = combine_pcdata(ret, i, param, depth)
	_clear_binded_param(depth+1, binded_param, param)
	return ret
			
#<!ELEMENT update 
#(#PCDATA | selectKey | include | trim | where | set | foreach | choose | if | bind)*>
#<!ATTLIST update
#id CDATA #REQUIRED
#parameterMap CDATA #IMPLIED
#parameterType CDATA #IMPLIED
#timeout CDATA #IMPLIED
#flushCache (true|false) #IMPLIED
#statementType (STATEMENT|PREPARED|CALLABLE) #IMPLIED
#keyProperty CDATA #IMPLIED
#useGeneratedKeys (true|false) #IMPLIED
#keyColumn CDATA #IMPLIED
#databaseId CDATA #IMPLIED
#lang CDATA #IMPLIED
#> TODO
func deal_update(item:GXMLItem, param: Dictionary, depth: int):
	var ret = ""
	var binded_param = []
	for i in item.content:
		if i is GXMLItem:
			assert(["selectKey", "include", "trim", "where", "set", "foreach", 
			"choose", "if", "bind"].has(i.name), 
			"Invalid element %s in the current context." % i.name)
			_record_binded_param(i, binded_param)
			ret = combine(ret, deal_element(i, param, depth+1))
		else:
			ret = combine_pcdata(ret, i, param, depth)
	_clear_binded_param(depth+1, binded_param, param)
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
#> TODO
func deal_delete(item:GXMLItem, param: Dictionary, depth: int):
	var ret = ""
	var binded_param = []
	for i in item.content:
		if i is GXMLItem:
			assert(["include", "trim", "where", "set", "foreach", "choose", 
			"if", "bind"].has(i.name), "Invalid element %s in delete." % i.name)
			_record_binded_param(i, binded_param)
			ret = combine(ret, deal_element(i, param, depth+1))
		else:
			ret = combine_pcdata(ret, i, param, depth)
	_clear_binded_param(depth+1, binded_param, param)
	return ret
	
#<!ELEMENT include (property+)?>
#<!ATTLIST include
#refid CDATA #REQUIRED
#>
func deal_include(item:GXMLItem, param: Dictionary, depth: int) -> String:
	var ref_item = get_item(item.attrs.get("refid").strip_edges())
	var ret = deal_element(ref_item, param, depth+1)
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
func deal_bind(item:GXMLItem, param: Dictionary, depth: int) -> String:
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
func deal_sql(item:GXMLItem, param: Dictionary, depth: int) -> String:
	var ret = ""
	var binded_param = []
	for i in item.content:
		if i is GXMLItem:
			assert(["include", "trim", "where", "set", "foreach", "choose", 
			"if", "bind"].has(i.name), "Invalid element %s in sql." % i.name)
			_record_binded_param(i, binded_param)
			ret = combine(ret, deal_element(i, param, depth+1))
		else:
			ret = combine_pcdata(ret, i, param, depth)
	_clear_binded_param(depth+1, binded_param, param)
	return ret
	
#<!ELEMENT trim (#PCDATA | include | trim | where | set | foreach | choose | if | bind)*>
#<!ATTLIST trim
#prefix CDATA #IMPLIED 表示在trim包裹的SQL语句前面添加的指定内容。
#prefixOverrides CDATA #IMPLIED 表示在trim包裹的SQL末尾添加指定内容
#suffix CDATA #IMPLIED 表示去掉（覆盖）trim包裹的SQL的指定首部内容
#suffixOverrides CDATA #IMPLIED 表示去掉（覆盖）trim包裹的SQL的指定尾部内容
#>
func deal_trim(item:GXMLItem, param: Dictionary, depth: int) -> String:
	var ret = ""
	var binded_param = []
	for i in item.content:
		if i is GXMLItem:
			assert(["include", "trim", "where", "set", "foreach", "choose", 
			"if", "bind"].has(i.name), "Invalid element %s in trim." % i.name)
			_record_binded_param(i, binded_param)
			ret = combine(ret, deal_element(i, param, depth+1))
		else:
			ret = combine_pcdata(ret, i, param, depth)
			
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
func deal_where(item:GXMLItem, param: Dictionary, depth: int) -> String:
	var ret = ""
	var binded_param = []
	for i in item.content:
		if i is GXMLItem:
			assert(["include", "trim", "where", "set", "foreach", "choose", 
			"if", "bind"].has(i.name), "Invalid element %s in where." % i.name)
			_record_binded_param(i, binded_param)
			ret = combine(ret, deal_element(i, param, depth+1))
		else:
			ret = combine_pcdata(ret, i, param, depth)
	if ret.countn("and", 0, 3) > 0:
		ret = ret.substr(3)
	elif ret.countn("or", 0, 2) > 0:
		ret = ret.substr(2)
	ret = combine("where", ret)
	_clear_binded_param(depth+1, binded_param, param)
	return ret
	
#<!ELEMENT set (#PCDATA | include | trim | where | set | foreach | choose | if | bind)*>
func deal_set(item:GXMLItem, param: Dictionary, depth: int) -> String:
	var ret = ""
	var binded_param = []
	for i in item.content:
		if i is GXMLItem:
			assert(["include", "trim", "where", "set", "foreach", "choose", 
			"if", "bind"].has(i.name), "Invalid element %s in set." % i.name)
			_record_binded_param(i, binded_param)
			ret = combine(ret, deal_element(i, param, depth+1))
		else:
			ret = combine_pcdata(ret, i, param, depth)
	if ret.ends_with(","):
		ret = ret.substr(0, ret.length()-1)
	ret = combine("set", ret)
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
func deal_foreach(item:GXMLItem, param: Dictionary, depth: int) -> String:
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
		ret = combine(ret, e_open)
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
				ret = combine(ret, deal_element(i, param, depth+1))
			else:
				ret = combine_pcdata(ret, i, param, depth)
				
			# 去掉临时的bind
			if not e_item.is_empty():
				param[BIND][depth+1].erase(e_item)
			if not e_index.is_empty():
				param[BIND][depth+1].erase(e_index)
				
			if index < collection.size() - 1:
				ret = combine(ret, e_separator)
		ret = combine(ret, e_close)
	_clear_binded_param(depth+1, binded_param, param)
	return ret
	
#<!ELEMENT choose (when* , otherwise?)>
func deal_choose(item:GXMLItem, param: Dictionary, depth: int) -> String:
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
			var info = deal_element(i, param, depth+1)
			if info and info[0]:
				ret = combine(ret, info[1])
				break
	return ret
			
#<!ELEMENT when (#PCDATA | include | trim | where | set | foreach | choose | if | bind)*>
#<!ATTLIST when
#test CDATA #REQUIRED
#>
func deal_when(item:GXMLItem, param: Dictionary, depth: int) -> Array:
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
			ret = combine(ret, deal_element(i, param, depth+1))
		else:
			ret = combine_pcdata(ret, i, param, depth)
	_clear_binded_param(depth+1, binded_param, param)
	return [true, ret]
	
#<!ELEMENT otherwise (#PCDATA | include | trim | where | set | foreach | choose | if | bind)*>
func deal_otherwise(item:GXMLItem, param: Dictionary, depth: int) -> Array:
	var ret = ""
	var binded_param = []
	for i in item.content:
		if i is GXMLItem:
			assert(["include", "trim", "where", "set", "foreach", "choose", 
			"if", "bind"].has(i.name), "Invalid element %s in otherwise." % i.name)
			_record_binded_param(i, binded_param)
			ret = combine(ret, deal_element(i, param, depth+1))
		else:
			ret = combine_pcdata(ret, i, param, depth)
	_clear_binded_param(depth+1, binded_param, param)
	return ret
	
#<!ELEMENT if (#PCDATA | include | trim | where | set | foreach | choose | if | bind)*>
#<!ATTLIST if
#test CDATA #REQUIRED
#>
func deal_if(item:GXMLItem, param: Dictionary, depth: int) -> String:
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
			ret = combine(ret, deal_element(i, param, depth+1))
		else:
			ret = combine_pcdata(ret, i, param, depth)
	_clear_binded_param(depth+1, binded_param, param)
	return ret
	
func combine(s1: String, s2: String) -> String:
	s2 = _cast_null(s2).strip_edges()
	if s1.is_empty():
		return s2
	if s2.is_empty():
		return s1
	return "%s %s" % [s1, s2]
	
## 拼接，但是会将s2中的占位符替换成真实数据. depth表示s2的深度
func combine_pcdata(s1: String, s2: String, param: Dictionary, depth: int) -> String:
	s2 = _cast_null(s2).strip_edges()
	if s2.is_empty():
		return s1
	s2 = replace_param(s2, param, depth)
	return "%s %s" % [s1, s2]
	
func _cast_null(value) -> String:
	return "" if typeof(value) == TYPE_NIL else value
	
## 替换占位符
func replace_param(s: String, param: Dictionary, depth: int) -> String:
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
			s.replace(k, str(value))
		else:
			s.replace(k, var_to_str(value))
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
				for n in param[BIND][d]:
					names.push_back(n)
					values.push_back(param[BIND][d][n])
		else:
			names.push_back(i)
			values.push_back(param[i])
	return GDSQLUtils.evaluate_command(null, value_string, names, values)
