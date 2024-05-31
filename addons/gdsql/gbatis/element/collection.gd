@tool
extends RefCounted
class_name GBatisCollection
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

var property = ""
var column = ""
var java_type = ""
var of_type = ""
var select = ""
var result_map = ""
var foreign_column = ""
var auto_mapping = ""
var result_embeded: GBatisResultMap
var mapper_parser_ref: WeakRef: set = set_mapper_parser_ref

# --------- 内部使用 ----------
var _result_map: GBatisResultMap # 把association当作一个resultMap来用

func _init(conf: Dictionary):
	property = conf.get("property", "").strip_edges()
	column = conf.get("column", "").strip_edges()
	java_type = conf.get("javaType", "").strip_edges()
	of_type = conf.get("ofType", "").strip_edges()
	select = conf.get("select", "").strip_edges()
	result_map = conf.get("resultMap", "").strip_edges()
	foreign_column = conf.get("foreignColumn", "").strip_edges()
	auto_mapping = conf.get("autoMapping", "").strip_edges()
	
func clean():
	if result_embeded != null:
		result_embeded.clean()
	result_embeded = null
	mapper_parser_ref = null
	_result_map = null
	
func set_mapper_parser_ref(mapper_parser):
	mapper_parser_ref = mapper_parser
	
func push_element(element):
	if not result_embeded:
		result_embeded = GBatisResultMap.new({})
	result_embeded.push_back(element)
	
## 每处理一条数据需要调用一下
func prepare_deal(head: Array, data: Array):
	if _result_map != null:
		return
		
	_result_map = result_embeded
	if _result_map == null:
		if not result_map.is_empty():
			_result_map = mapper_parser_ref.get_ref().get_element(result_map)
			assert(_result_map != null, "Not found <resultMap> of id %s" % result_map)
			assert(_result_map is GBatisResultMap, "Not found <resultMap> of id %s" % result_map)
		elif select.is_empty():
			_result_map = GBatisResultMap.new({})
			_result_map.type = java_type
			
	if _result_map != null:
		_result_map.prepare_deal(head, data)
		
## 每处理一条数据后需要调用一下
func reset():
	# 如果有鉴别器，则返回值不稳定，需要重置
	if _result_map and _result_map.discriminator != null:
		_result_map.reset()
		_result_map = null
