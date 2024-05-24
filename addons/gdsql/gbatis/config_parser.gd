extends Resource
## 一个解析mapper xml的工具。解析规则参考http://mybatis.org/dtd/mybatis-3-mapper.dtd。
class_name GBatisConfigParser

const BIND = "__bind__"

static var re_placeholder: RegEx = RegEx.new()
static var re_split: RegEx = RegEx.new()

static func _static_init() -> void:
	# deal #{ roleId } ${   rrrr} #   { user . roleId } ${list[0} ${bea.abc[ 33 ]} ${map[a]}
	#re_placeholder.compile(r'(?is)(#\s*\{\s*|\$\s*\{\s*)([a-zA-Z_][a-zA-Z0-9_]*\s*\.?\s*[a-zA-Z0-9_]*\s*)\s*(\}\s*|\s*\})')
	#re_placeholder.compile(r'(?is)(#\s*\{\s*|\$\s*\{\s*)([a-zA-Z_][a-zA-Z0-9_]*(\s*[\.\s]*[a-zA-Z0-9_]*|\s*[\[\s]*[0-9]*[\s]*\])*)\s*(\}\s*|\s*\})')
	re_placeholder.compile(r'(?is)(#\s*\{\s*|\$\s*\{\s*)([a-zA-Z_][a-zA-Z0-9_]*((\s*[\.\s]*[a-zA-Z0-9_]*|\s*[\[\s]*[a-zA-Z0-9_]*[\s]*\])*)*)\s*(\}\s*|\s*\})')
	re_split.compile(r'(?is)[^\.\[\]]+')
	
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
			return deal_select(item, param)
		"update":
			return deal_update(item, param)
		"insert":
			return deal_insert(item, param)
		"replace":
			return deal_replace(item, param)
		"delete":
			return deal_delete(item, param)
		_:
			assert(false, "method must be one of select, insert, update and delete.")
			return null
	
func get_item(id: String) -> GXMLItem:
	for i in config.root_item.content:
		if i is GXMLItem and (i as GXMLItem).attrs.get("id", "") == id:
			return i
	return null
	
func deal_element(item: GXMLItem, param):
	if not item:
		return ""
	match item.name:
		"cache-ref":
			return deal_cache_ref(item, param)
		"cache":
			return deal_cache(item, param)
		"parameterMap":
			return deal_parameter_map(item, param)
		"parameter":
			return deal_parameter(item, param)
		"resultMap":
			return deal_result_map(item, param)
		"id":
			return deal_id(item, param)
		"result":
			return deal_result(item, param)
		"idArg":
			return deal_id_arg(item, param)
		"arg":
			return deal_arg(item, param)
		"collection":
			return deal_collection(item, param)
		"association":
			return deal_association(item, param)
		"discriminator":
			return deal_discriminator(item, param)
		"case":
			return deal_case(item, param)
		"property":
			return deal_property(item, param)
		"typeAlias":
			return deal_type_alias(item, param)
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
			return deal_select_key(item, param)
		"update":
			#return deal_update(item, null)
			pass
		"delete":
			#return deal_delete(item, null)
			pass
		"include":
			return deal_include(item, param)
		"bind":
			return deal_bind(item, param)
		"sql":
			return deal_sql(item, param)
		"trim":
			return deal_trim(item, param)
		"where":
			return deal_where(item, param)
		"set":
			return deal_set(item, param)
		"foreach":
			return deal_foreach(item, param)
		"choose":
			return deal_choose(item, param)
		"when":
			return deal_when(item, param)
		"otherwise":
			return deal_otherwise(item, param)
		"if":
			return deal_if(item, param)
		_:
			return ""
			
#<!ELEMENT cache-ref EMPTY>
#<!ATTLIST cache-ref
#namespace CDATA #REQUIRED
#>
func deal_cache_ref(item: GXMLItem, param):
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
func deal_cache(item: GXMLItem, param):
	var ret = ""
	for i in item.content:
		if i is GXMLItem:
			assert(i.name == "property", "Invalid element %s in cache." % i.name)
			ret = combine(ret, deal_element(i, param))
	return ret
		
#<!ELEMENT parameterMap (parameter+)?>
#<!ATTLIST parameterMap
#id CDATA #REQUIRED
#type CDATA #REQUIRED
#>
## @deprecated
func deal_parameter_map(item: GXMLItem, param):
	var ret = ""
	for i in item.content:
		if i is GXMLItem:
			assert(i.name == "property", "Invalid element %s in parameterMap." % i.name)
			ret = combine(ret, deal_element(i, param))
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
## @deprecated
func deal_parameter(item: GXMLItem, param):
	return ""
	
#<!ELEMENT resultMap (constructor?,id*,result*,association*,collection*, discriminator?)>
#<!ATTLIST resultMap
#id CDATA #REQUIRED
#type CDATA #REQUIRED
#extends CDATA #IMPLIED
#autoMapping (true|false) #IMPLIED
#> TODO 
func deal_result_map(item: GXMLItem, param):
	var ret = ""
	for i in item.content:
		if i is GXMLItem:
			assert(["constructor", "id", "result", "association", "collection", 
			"discriminator"].has(i.name), "Invalid element %s in resultMap." % i.name)
			ret = combine(ret, deal_element(i, param))
	return ret
			
#<!ELEMENT id EMPTY>
#<!ATTLIST id
#property CDATA #IMPLIED
#javaType CDATA #IMPLIED
#column CDATA #IMPLIED
#jdbcType CDATA #IMPLIED
#typeHandler CDATA #IMPLIED
#> TODO
func deal_id(item: GXMLItem, param):
	return ""
	
#<!ELEMENT result EMPTY>
#<!ATTLIST result
#property CDATA #IMPLIED
#javaType CDATA #IMPLIED
#column CDATA #IMPLIED
#jdbcType CDATA #IMPLIED
#typeHandler CDATA #IMPLIED
#> TODO
func deal_result(item: GXMLItem, param):
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
## @deprecated
func deal_id_arg(item:GXMLItem, param):
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
## @deprecated
func deal_arg(item:GXMLItem, param):
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
func deal_collection(item:GXMLItem, param):
	# 不是返回字符串 WARNING
	var ret = ""
	for i in item.content:
		if i is GXMLItem:
			assert(["constructor", "id", "result", "association", "collection", 
			"discriminator"].has(i.name), "Invalid element %s in collection." % i.name)
			ret = combine(ret, deal_element(i, param))
	return ret
			
#<!ELEMENT association (constructor?,id*,result*,association*,collection*, discriminator?)>
#<!ATTLIST association
#property CDATA #REQUIRED
#column CDATA #IMPLIED
#javaType CDATA #IMPLIED
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
func deal_association(item:GXMLItem, param):
	var ret = ""
	for i in item.content:
		if i is GXMLItem:
			assert(["constructor", "id", "result", "association", "collection", 
			"discriminator"].has(i.name), "Invalid element %s in association." % i.name)
			ret = combine(ret, deal_element(i, param))
	return ret
			
#<!ELEMENT discriminator (case+)>
#<!ATTLIST discriminator
#column CDATA #IMPLIED
#javaType CDATA #REQUIRED
#jdbcType CDATA #IMPLIED
#typeHandler CDATA #IMPLIED
#> TODO not return string
func deal_discriminator(item:GXMLItem, param):
	var ret = ""
	for i in item.content:
		if i is GXMLItem:
			assert(i.name == "case", "Invalid element %s in discriminator." % i.name)
			ret = combine(ret, deal_element(i, param))
	return ret
		
#<!ELEMENT case (constructor?,id*,result*,association*,collection*, discriminator?)>
#<!ATTLIST case
#value CDATA #REQUIRED
#resultMap CDATA #IMPLIED
#resultType CDATA #IMPLIED
#> TODO 
func deal_case(item:GXMLItem, param):
	var ret = ""
	for i in item.content:
		if i is GXMLItem:
			assert(["constructor", "id", "result", "association", "collection", 
			"discriminator"].has(i.name), "Invalid element %s in case." % i.name)
			ret = combine(ret, deal_element(i, param))
	return ret
	
#<!ELEMENT property EMPTY>
#<!ATTLIST property
#name CDATA #REQUIRED
#value CDATA #REQUIRED
#> 
## @deprecated
func deal_property(item:GXMLItem, param):
	return ""
	
#<!ELEMENT typeAlias EMPTY>
#<!ATTLIST typeAlias
#alias CDATA #REQUIRED
#type CDATA #REQUIRED
#>
## @deprecated
func deal_type_alias(item:GXMLItem, param):
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
#resultSets CDATA #IMPLIED 
#> TODO
func deal_select(item:GXMLItem, param) -> QueryResult:
	var sql = ""
	for i in item.content:
		if i is GXMLItem:
			assert(["include", "trim", "where", "set", "foreach", "choose", 
				"if", "bind"].has(i.name), "Invalid element %s in select." % i.name)
			sql += deal_element(i, param)
		else:
			sql += i
			
	var parameter_type = item.attrs.get("parameterType", {})
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
func deal_insert(item:GXMLItem, param):
	var ret = ""
	for i in item.content:
		if i is GXMLItem:
			assert(["selectKey", "include", "trim", "where", "set", "foreach", 
			"choose", "if", "bind"].has(i.name), "Invalid element %s in insert." % i.name)
			ret = combine(ret, deal_element(i, param))
		else:
			ret = combine(ret, i)
	return ret
			
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
func deal_replace(item:GXMLItem, param):
	var ret = ""
	for i in item.content:
		if i is GXMLItem:
			assert(["selectKey", "include", "trim", "where", "set", "foreach", 
			"choose", "if", "bind"].has(i.name), "Invalid element %s in replace." % i.name)
			ret = combine(ret, deal_element(i, param))
		else:
			ret = combine(ret, i)
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
func deal_select_key(item:GXMLItem, param):
	var ret = ""
	for i in item.content:
		if i is GXMLItem:
			assert(["include", "trim", "where", "set", "foreach", "choose", 
			"if", "bind"].has(i.name), "Invalid element %s in selectKey." % i.name)
			ret = combine(ret, deal_element(i, param))
		else:
			ret = combine(ret, i)
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
func deal_update(item:GXMLItem, param):
	var ret = ""
	for i in item.content:
		if i is GXMLItem:
			assert(["selectKey", "include", "trim", "where", "set", "foreach", 
			"choose", "if", "bind"].has(i.name), 
			"Invalid element %s in the current context." % i.name)
			ret = combine(ret, deal_element(i, param))
		else:
			ret = combine(ret, i)
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
func deal_delete(item:GXMLItem, param):
	var ret = ""
	for i in item.content:
		if i is GXMLItem:
			assert(["include", "trim", "where", "set", "foreach", "choose", 
			"if", "bind"].has(i.name), "Invalid element %s in delete." % i.name)
			ret = combine(ret, deal_element(i, param))
		else:
			ret = combine(ret, i)
	return ret
	
#<!ELEMENT include (property+)?>
#<!ATTLIST include
#refid CDATA #REQUIRED
#>
func deal_include(item:GXMLItem, param):
	return deal_element(get_item(item.attrs.get("refid")), param)
		
#<!ELEMENT bind EMPTY>
#<!ATTLIST bind
 #name CDATA #REQUIRED
 #value CDATA #REQUIRED
#>
func deal_bind(item:GXMLItem, param):
	var a_name = item.attrs.get("name")
	var a_value = item.attrs.get("value")
	assert(not param.get(BIND).has(a_name) or param.get(BIND).get(a_name) == a_value, 
		"Already bind this parameter: %s to another property:%s." % \
		[a_name, param.get(BIND).get(a_name, "")])
	assert(param.has(a_name), "Not found %s in param, cannot bind." % a_name)
	#elif param.origin is Object:
		#assert(typeof((param.origin as Object).get(a_name)) == TYPE_NIL, 
		#"Not found property %s in Object %s" % [a_name, param.origin])
	#param.bind[a_name] = a_value
	# TODO
	return ""
	
#<!ELEMENT sql (#PCDATA | include | trim | where | set | foreach | choose | if | bind)*>
#<!ATTLIST sql
#id CDATA #REQUIRED
#lang CDATA #IMPLIED -----------X
#databaseId CDATA #IMPLIED ----------X
#>
func deal_sql(item:GXMLItem, param):
	var ret = ""
	for i in item.content:
		if i is GXMLItem:
			assert(["include", "trim", "where", "set", "foreach", "choose", 
			"if", "bind"].has(i.name), "Invalid element %s in sql." % i.name)
			ret = combine(ret, deal_element(i, param))
		else:
			ret = combine(ret, i)
	return ret
	
#<!ELEMENT trim (#PCDATA | include | trim | where | set | foreach | choose | if | bind)*>
#<!ATTLIST trim
#prefix CDATA #IMPLIED 表示在trim包裹的SQL语句前面添加的指定内容。
#prefixOverrides CDATA #IMPLIED 表示在trim包裹的SQL末尾添加指定内容
#suffix CDATA #IMPLIED 表示去掉（覆盖）trim包裹的SQL的指定首部内容
#suffixOverrides CDATA #IMPLIED 表示去掉（覆盖）trim包裹的SQL的指定尾部内容
#>
func deal_trim(item:GXMLItem, param):
	var ret = ""
	for i in item.content:
		if i is GXMLItem:
			assert(["include", "trim", "where", "set", "foreach", "choose", 
			"if", "bind"].has(i.name), "Invalid element %s in trim." % i.name)
			ret = combine(ret, deal_element(i, param))
		else:
			ret = combine(ret, i)
			
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
	return ret
	
#<!ELEMENT where (#PCDATA | include | trim | where | set | foreach | choose | if | bind)*>
func deal_where(item:GXMLItem, param):
	var ret = ""
	for i in item.content:
		if i is GXMLItem:
			assert(["include", "trim", "where", "set", "foreach", "choose", 
			"if", "bind"].has(i.name), "Invalid element %s in where." % i.name)
			ret = combine(ret, deal_element(i, param))
		else:
			ret = combine(ret, i)
	if ret.countn("and", 0, 3) > 0:
		ret = ret.substr(3)
	elif ret.countn("or", 0, 2) > 0:
		ret = ret.substr(2)
	ret = combine("where", ret)
	return ret
	
#<!ELEMENT set (#PCDATA | include | trim | where | set | foreach | choose | if | bind)*>
func deal_set(item:GXMLItem, param):
	var ret = ""
	for i in item.content:
		if i is GXMLItem:
			assert(["include", "trim", "where", "set", "foreach", "choose", 
			"if", "bind"].has(i.name), "Invalid element %s in set." % i.name)
			ret = combine(ret, deal_element(i, param))
		else:
			ret = combine(ret, i)
	if ret.ends_with(","):
		ret = ret.substr(0, ret.length()-1)
	ret = combine("set", ret)
	return ret
	
#<!ELEMENT foreach (#PCDATA | include | trim | where | set | foreach | choose | if | bind)*>
#<!ATTLIST foreach
#collection CDATA #REQUIRED 指定要遍历的集合或数组的变量名称，
#但是当名称为'list'和'map'时，首先会找原参数中名为list或map的属性，
#找不到时，如果原参数正好是一个Array或一个字典，就直接用原参数
#item CDATA #IMPLIED 设置每次迭代变量的名称
#index CDATA #IMPLIED 若遍历的是list，index代表下标；若遍历的是map，index代表键
#open CDATA #IMPLIED 设置循环体的开始内容
#close CDATA #IMPLIED 设置循环体的结束内容
#separator CDATA #IMPLIED 设置每一次循环之间的分隔符
#>
func deal_foreach(item:GXMLItem, param):
	var ret = ""
	for i in item.content:
		if i is GXMLItem:
			assert(["include", "trim", "where", "set", "foreach", "choose", 
			"if", "bind"].has(i.name), "Invalid element %s in foreach." % i.name)
			ret = combine(ret, deal_element(i, param))
		else:
			ret = combine(ret, i)
	return ret
			
#<!ELEMENT choose (when* , otherwise?)>
func deal_choose(item:GXMLItem, param):
	var ret = ""
	for i in item.content:
		if i is GXMLItem:
			assert(["when", "otherwise"].has(i.name), "Invalid element %s in choose." % i.name)
			ret = combine(ret, deal_element(i, param))
		else:
			ret = combine(ret, i)
	return ret
			
#<!ELEMENT when (#PCDATA | include | trim | where | set | foreach | choose | if | bind)*>
#<!ATTLIST when
#test CDATA #REQUIRED
#>
func deal_when(item:GXMLItem, param):
	var ret = ""
	for i in item.content:
		if i is GXMLItem:
			assert(["include", "trim", "where", "set", "foreach", "choose", 
			"if", "bind"].has(i.name), "Invalid element %s in when." % i.name)
			ret = combine(ret, deal_element(i, param))
		else:
			ret = combine(ret, i)
	return ret
			
#<!ELEMENT otherwise (#PCDATA | include | trim | where | set | foreach | choose | if | bind)*>
func deal_otherwise(item:GXMLItem, param):
	var ret = ""
	for i in item.content:
		if i is GXMLItem:
			assert(["include", "trim", "where", "set", "foreach", "choose", 
			"if", "bind"].has(i.name), "Invalid element %s in otherwise." % i.name)
			ret = combine(ret, deal_element(i, param))
		else:
			ret = combine(ret, i)
	return ret
	
#<!ELEMENT if (#PCDATA | include | trim | where | set | foreach | choose | if | bind)*>
#<!ATTLIST if
#test CDATA #REQUIRED
#>
func deal_if(item:GXMLItem, param):
	var ret = ""
	for i in item.content:
		if i is GXMLItem:
			assert(["include", "trim", "where", "set", "foreach", "choose", 
			"if", "bind"].has(i.name), "Invalid element %s in if." % i.name)
			ret = combine(ret, deal_element(i, param))
		else:
			ret = combine(ret, i)
	return ret
	
func combine(s1: String, s2: String) -> String:
	s2 = _cast_null(s2).strip_edges()
	if s1.is_empty():
		return s2
	return "%s %s" % [s1, s2]
	
func _cast_null(value) -> String:
	return "" if typeof(value) == TYPE_NIL else value
	
## 替换占位符
func replace_param(s: String, param: Dictionary) -> String:
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
		var value = null # 被替换的值
		var prop = (unique_matches[k] as RegExMatch).get_string(2).strip_edges()
		if prop.contains(".") or prop.contains("["):
			assert(not prop.ends_with("."), "Error near: %s" % prop)
			assert(not prop.ends_with("[]"), "Error near: %s" % prop)
			assert(prop.count("[") == prop.count("]"), "`[` and `]` not match. Near: %s" % prop)
			prop = prop.replace("\t", "").replace(" ", "")
			assert(not prop.contains(".["), "Error near: %s" % prop)
			var splits_matches = re_split.search_all(prop)
			var splits = []
			for i in splits_matches:
				var key = i.get_string().strip_edges()
				if not key.is_empty():
					splits.push_back(key)
			var param_name = splits[0]
			assert(param.has(param_name), "Not found param: %s." % param_name)
			value = param[param_name]
			var index = 0
			while splits.size() > index:
				index += 1
				var key = splits[index] as String
				if value is Dictionary:
					if value.has(key):
						value = value.get(key)
					elif str(key.to_float()) == key and value.has(key.to_float()):
						value = value.get(key.to_float())
					elif str(key.to_int()) == key and value.has(key.to_int()):
						value = value.get(key.to_int())
					else:
						assert(false, "Invalid index: %s of %s" % [prop, param_name])
				elif value is Object:
					assert(key.is_valid_identifier(), "Invalid index: %s of %s" % [prop, param_name])
					value = value.get(key)
				elif value is Array:
					assert(str(key.to_int()) == key, "Invalid index: %s of %s" % [prop, param_name])
					value = value[key]
				else:
					assert(false, "Invalid index: %s of %s" % [prop, param_name])
		else:
			if param.get(BIND).has(prop):
				value = param.get(BIND).get(prop)
			else:
				assert(param.size() == 2, "Please specify the owner of property: %s" % prop)
				for key in param:
					if key != BIND:
						assert(param.get(key).has(prop), "Invalid index: %s of %s" % [prop, key])
						value = param[key][prop]
						break
						
		if k.begins_with("$"):
			s.replace(k, str(value))
		else:
			s.replace(k, "'%s'" % str(value).c_escape())# FIXME
	return ""
