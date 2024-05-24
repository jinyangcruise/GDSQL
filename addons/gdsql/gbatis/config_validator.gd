extends RefCounted
## 验证一个配置是否正确配置
class_name GBatisConfigValidator

var err = []
const VALID_ELEMENTS_1 = ["include", "trim", "where", "set", "foreach", "choose", "if", "bind"]
const VALID_ELEMENTS_2 = ["id", "result", "association", "collection", "discriminator"]
const VALID_ELEMENTS_3 = ["selectKey", "include", "trim", "where", "set", 
"foreach", "choose", "if", "bind"]

func _assert(cond, msg: String):
	if not cond:
		err.push_back(msg)
		
func validate(item: GXML):
	_assert(item.root_item, "root item is empty!")
	_assert(item.root_item.name == "mapper", "root item name is not mapper!")
	_assert(item.root_item.attrs.has("namespace"), "root item does not have namespace!")
	for i in item.root_item.content:
		if i is GXMLItem:
			deal_element(i)
			
func deal_element(item: GXMLItem):
	match item.name:
		"cache-ref":
			deal_cache_ref(item)
		"cache":
			deal_cache(item)
		"parameterMap":
			deal_parameter_map(item)
		"parameter":
			deal_parameter(item)
		"resultMap":
			deal_result_map(item)
		"id":
			deal_id(item)
		"result":
			deal_result(item)
		"idArg":
			deal_id_arg(item)
		"arg":
			deal_arg(item)
		"collection":
			deal_collection(item)
		"association":
			deal_association(item)
		"discriminator":
			deal_discriminator(item)
		"case":
			deal_case(item)
		"property":
			deal_property(item)
		"typeAlias":
			deal_type_alias(item)
		"select":
			deal_select(item)
		"insert":
			deal_insert(item)
		"selectKey":
			deal_select_key(item)
		"update":
			deal_update(item)
		"delete":
			deal_delete(item)
		"include":
			deal_include(item)
		"bind":
			deal_bind(item)
		"sql":
			deal_sql(item)
		"trim":
			deal_trim(item)
		"where":
			deal_where(item)
		"set":
			deal_set(item)
		"foreach":
			deal_foreach(item)
		"choose":
			deal_choose(item)
		"when":
			deal_when(item)
		"otherwise":
			deal_otherwise(item)
		"if":
			deal_if(item)
		_:
			err.push_back("unrecognized element:%s" % item.name)
			
#<!ELEMENT cache-ref EMPTY>
#<!ATTLIST cache-ref
#namespace CDATA #REQUIRED
#>
func deal_cache_ref(item: GXMLItem):
	_assert(not item.attrs.get("namespace", "").strip_edges().is_empty(), "namespace is empty of cache-ref!")
	
#<!ELEMENT cache (property*)>
#<!ATTLIST cache
#type CDATA #IMPLIED
#eviction CDATA #IMPLIED
#flushInterval CDATA #IMPLIED
#size CDATA #IMPLIED
#readOnly CDATA #IMPLIED
#blocking CDATA #IMPLIED
#>
func deal_cache(item: GXMLItem):
	for i in item.content:
		_assert(i is GXMLItem and i.name == "property", "content of cache must be property!")
		
#<!ELEMENT parameterMap (parameter+)?>
#<!ATTLIST parameterMap
#id CDATA #REQUIRED
#type CDATA #REQUIRED
#>
func deal_parameter_map(item: GXMLItem):
	_assert(not item.attrs.get("id", "").strip_edges().is_empty(), "id is empty of parameterMap!")
	_assert(not item.attrs.get("type", "").strip_edges().is_empty(), "type is empty of parameterMap!")
	
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
func deal_parameter(item: GXMLItem):
	_assert(not item.attrs.get("property", "").strip_edges().is_empty(), "property is empty of parameter!")
	_assert(item.content.is_empty(), "parameter content should be empty!")
	
#<!ELEMENT resultMap (constructor?,id*,result*,association*,collection*, discriminator?)>
#<!ATTLIST resultMap
#id CDATA #REQUIRED
#type CDATA #REQUIRED
#extends CDATA #IMPLIED
#autoMapping (true|false) #IMPLIED
#>
func deal_result_map(item: GXMLItem):
	_assert(not item.attrs.get("id", "").strip_edges().is_empty(), "id is empty of result map!")
	_assert(not item.attrs.get("type", "").strip_edges().is_empty(), "type is empty of result map!")
	for i in item.content:
		if i is GXMLItem:
			_assert(VALID_ELEMENTS_2.has(i.name), 
			"not support %s in resultMap" % i.name)
			deal_element(i)
			
#<!ELEMENT id EMPTY>
#<!ATTLIST id
#property CDATA #IMPLIED
#javaType CDATA #IMPLIED
#column CDATA #IMPLIED
#jdbcType CDATA #IMPLIED
#typeHandler CDATA #IMPLIED
#>
func deal_id(item: GXMLItem):
	_assert(item.content.is_empty(), "id content should be empty!")
	
#<!ELEMENT result EMPTY>
#<!ATTLIST result
#property CDATA #IMPLIED
#javaType CDATA #IMPLIED
#column CDATA #IMPLIED
#jdbcType CDATA #IMPLIED
#typeHandler CDATA #IMPLIED
#>
func deal_result(item: GXMLItem):
	_assert(item.content.is_empty(), "result content should be empty!")
	
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
func deal_id_arg(item:GXMLItem):
	_assert(item.content.is_empty(), "idArg content should be empty!")
	
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
func deal_arg(item:GXMLItem):
	_assert(item.content.is_empty(), "arg content should be empty!")
	
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
#>
func deal_collection(item:GXMLItem):
	_assert(not item.attrs.get("property", "").strip_edges().is_empty(), "property is empty of colletion!")
	for i in item.content:
		if i is GXMLItem:
			_assert(VALID_ELEMENTS_2.has(i.name), "not support %s in collection" % i.name)
			deal_element(i)
			
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
#>
func deal_association(item:GXMLItem):
	_assert(not item.attrs.get("property", "").strip_edges().is_empty(), "property is empty of association!")
	for i in item.content:
		if i is GXMLItem:
			_assert(VALID_ELEMENTS_2.has(i.name), "not support %s in association" % i.name)
			deal_element(i)
			
#<!ELEMENT discriminator (case+)>
#<!ATTLIST discriminator
#column CDATA #REQUIRED
#javaType CDATA #REQUIRED
#jdbcType CDATA #IMPLIED
#typeHandler CDATA #IMPLIED
#>
func deal_discriminator(item:GXMLItem):
	_assert(not item.attrs.get("column", "").strip_edges().is_empty(), "column is empty of discriminator!")
	_assert(not item.attrs.get("javaType", "").strip_edges().is_empty(), "javaType is empty of discriminator!")
	_assert(not item.content.is_empty(), "content of discriminator is empty!")
	for i in item.content:
		_assert(i is GXMLItem and i.name == "case", "content of discriminator must be case!")
		
#<!ELEMENT case (constructor?,id*,result*,association*,collection*, discriminator?)>
#<!ATTLIST case
#value CDATA #REQUIRED
#resultMap CDATA #IMPLIED
#resultType CDATA #IMPLIED
#>
func deal_case(item:GXMLItem):
	_assert(not item.attrs.get("value", "").strip_edges().is_empty(), "value is empty of case!")
	for i in item.content:
		if i is GXMLItem:
			_assert(VALID_ELEMENTS_2.has(i.name), "not support %s in case" % i.name)
			deal_element(i)
	
#<!ELEMENT property EMPTY>
#<!ATTLIST property
#name CDATA #REQUIRED
#value CDATA #REQUIRED
#>
func deal_property(item:GXMLItem):
	_assert(not item.attrs.get("name", "").strip_edges().is_empty(), "name is empty of property!")
	_assert(not item.attrs.get("value", "").strip_edges().is_empty(), "value is empty of property!")
	_assert(item.content.is_empty(), "property content should be empty!")
	
#<!ELEMENT typeAlias EMPTY>
#<!ATTLIST typeAlias
#alias CDATA #REQUIRED
#type CDATA #REQUIRED
#>
func deal_type_alias(item:GXMLItem):
	_assert(not item.attrs.get("alias", "").strip_edges().is_empty(), "alias is empty of typeAlias!")
	_assert(not item.attrs.get("type", "").strip_edges().is_empty(), "type is empty of typeAlias!")
	_assert(item.content.is_empty(), "typeAlias content should be empty!")
	
#<!ELEMENT select (#PCDATA | include | trim | where | set | foreach | choose | if | bind)*>
#<!ATTLIST select
#id CDATA #REQUIRED
#parameterMap CDATA #IMPLIED
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
#>
func deal_select(item:GXMLItem):
	_assert(not item.attrs.get("id", "").strip_edges().is_empty(), "id is empty of select!")
	for i in item.content:
		if i is GXMLItem:
			_assert(VALID_ELEMENTS_1.has(i.name), "not support %s in select" % i.name)
			deal_element(i)
			
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
#>
func deal_insert(item:GXMLItem):
	_assert(not item.attrs.get("id", "").strip_edges().is_empty(), "id is empty of insert!")
	for i in item.content:
		if i is GXMLItem:
			_assert(VALID_ELEMENTS_3.has(i.name), "not support %s in insert" % i.name)
			deal_element(i)
			
#<!ELEMENT selectKey (#PCDATA | include | trim | where | set | foreach | choose | if | bind)*>
#<!ATTLIST selectKey
#resultType CDATA #IMPLIED
#statementType (STATEMENT|PREPARED|CALLABLE) #IMPLIED
#keyProperty CDATA #IMPLIED
#keyColumn CDATA #IMPLIED
#order (BEFORE|AFTER) #IMPLIED
#databaseId CDATA #IMPLIED
#>
func deal_select_key(item:GXMLItem):
	for i in item.content:
		if i is GXMLItem:
			_assert(VALID_ELEMENTS_1.has(i.name), "not support %s in selectKey" % i.name)
			deal_element(i)
			
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
#>
func deal_update(item:GXMLItem):
	_assert(not item.attrs.get("id", "").strip_edges().is_empty(), "id is empty of update!")
	for i in item.content:
		if i is GXMLItem:
			_assert(VALID_ELEMENTS_3.has(i.name), "not support %s in update" % i.name)
			deal_element(i)
			
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
func deal_delete(item:GXMLItem):
	_assert(not item.attrs.get("id", "").strip_edges().is_empty(), "id is empty of delete!")
	for i in item.content:
		if i is GXMLItem:
			_assert(VALID_ELEMENTS_1.has(i.name), "not support %s in delete" % i.name)
			deal_element(i)
			
#<!ELEMENT include (property+)?>
#<!ATTLIST include
#refid CDATA #REQUIRED
#>
func deal_include(item:GXMLItem):
	_assert(not item.attrs.get("refid", "").strip_edges().is_empty(), "refid is empty of include!")
	for i in item.content:
		_assert(i is GXMLItem and i.name == "property", "content of include must be property!")
		
#<!ELEMENT bind EMPTY>
#<!ATTLIST bind
 #name CDATA #REQUIRED
 #value CDATA #REQUIRED
#>
func deal_bind(item:GXMLItem):
	_assert(not item.attrs.get("name", "").strip_edges().is_empty(), "name is empty of bind!")
	_assert(not item.attrs.get("value", "").strip_edges().is_empty(), "value is empty of bind!")
	
#<!ELEMENT sql (#PCDATA | include | trim | where | set | foreach | choose | if | bind)*>
#<!ATTLIST sql
#id CDATA #REQUIRED
#lang CDATA #IMPLIED
#databaseId CDATA #IMPLIED
#>
func deal_sql(item:GXMLItem):
	_assert(not item.attrs.get("id", "").strip_edges().is_empty(), "id is empty of sql!")
	for i in item.content:
		if i is GXMLItem:
			_assert(VALID_ELEMENTS_1.has(i.name), "not support %s in sql" % i.name)
			deal_element(i)
			
#<!ELEMENT trim (#PCDATA | include | trim | where | set | foreach | choose | if | bind)*>
#<!ATTLIST trim
#prefix CDATA #IMPLIED
#prefixOverrides CDATA #IMPLIED
#suffix CDATA #IMPLIED
#suffixOverrides CDATA #IMPLIED
#>
func deal_trim(item:GXMLItem):
	for i in item.content:
		if i is GXMLItem:
			_assert(VALID_ELEMENTS_1.has(i.name), "not support %s in trim" % i.name)
			deal_element(i)
			
#<!ELEMENT where (#PCDATA | include | trim | where | set | foreach | choose | if | bind)*>
func deal_where(item:GXMLItem):
	for i in item.content:
		if i is GXMLItem:
			_assert(VALID_ELEMENTS_1.has(i.name), "not support %s in where" % i.name)
			deal_element(i)
			
#<!ELEMENT set (#PCDATA | include | trim | where | set | foreach | choose | if | bind)*>
func deal_set(item:GXMLItem):
	for i in item.content:
		if i is GXMLItem:
			_assert(VALID_ELEMENTS_1.has(i.name), "not support %s in set" % i.name)
			deal_element(i)
			
#<!ELEMENT foreach (#PCDATA | include | trim | where | set | foreach | choose | if | bind)*>
#<!ATTLIST foreach
#collection CDATA #REQUIRED
#item CDATA #IMPLIED
#index CDATA #IMPLIED
#open CDATA #IMPLIED
#close CDATA #IMPLIED
#separator CDATA #IMPLIED
#>
func deal_foreach(item:GXMLItem):
	_assert(not item.attrs.get("collection", "").strip_edges().is_empty(), "collection is empty of foreach!")
	for i in item.content:
		if i is GXMLItem:
			_assert(VALID_ELEMENTS_1.has(i.name), "not support %s in foreach" % i.name)
			deal_element(i)
			
#<!ELEMENT choose (when* , otherwise?)>
func deal_choose(item:GXMLItem):
	for i in item.content:
		if i is GXMLItem:
			_assert(["when", "otherwise"].has(i.name), "not support %s in choose" % i.name)
			deal_element(i)
			
#<!ELEMENT when (#PCDATA | include | trim | where | set | foreach | choose | if | bind)*>
#<!ATTLIST when
#test CDATA #REQUIRED
#>
func deal_when(item:GXMLItem):
	_assert(not item.attrs.get("test", "").strip_edges().is_empty(), "test is empty of when!")
	for i in item.content:
		if i is GXMLItem:
			_assert(VALID_ELEMENTS_1.has(i.name), "not support %s in when" % i.name)
			deal_element(i)
			
#<!ELEMENT otherwise (#PCDATA | include | trim | where | set | foreach | choose | if | bind)*>
func deal_otherwise(item:GXMLItem):
	for i in item.content:
		if i is GXMLItem:
			_assert(VALID_ELEMENTS_1.has(i.name), "not support %s in otherwise" % i.name)
			deal_element(i)
	
#<!ELEMENT if (#PCDATA | include | trim | where | set | foreach | choose | if | bind)*>
#<!ATTLIST if
#test CDATA #REQUIRED
#>
func deal_if(item:GXMLItem):
	_assert(not item.attrs.get("test", "").strip_edges().is_empty(), "test is empty of if!")
	for i in item.content:
		if i is GXMLItem:
			_assert(VALID_ELEMENTS_1.has(i.name), "not support %s in if" % i.name)
			deal_element(i)
