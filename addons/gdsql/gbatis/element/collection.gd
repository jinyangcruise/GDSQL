@tool
extends RefCounted
class_name GBatisCollection
#<!ELEMENT association (constructor?,id*,result*,association*,collection*, discriminator?)>
#<!ATTLIST association
#property CDATA #REQUIRED ----------- property name
#column CDATA #IMPLIED -------------- associate column name. When using multiple 
#                                     resultset this attribute specifies the 
#                                     columns (separated by commas) that will be 
#                                     correlated with the foreignColumn to identify
#                                     the parent and the child of a relationship.
#                                     NOTICE column belongs to parent fetch.
#javaType CDATA #IMPLIED ------------ Array or Dictionary ❌ not need
#ofType CDATA #IMPLIED -------------- 属性用于指定集合元素或关联对象的类型。
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

var property = ""
var column = ""
var javaType = ""
var ofType = ""
var select = ""
var resultMap = ""
var foreignColumn = ""
var autoMapping = ""
var result_embeded: GBatisResultMap

func _init(conf: Dictionary):
	property = conf.get("property", "").strip_edges()
	column = conf.get("column", "").strip_edges()
	javaType = conf.get("javaType", "").strip_edges()
	ofType = conf.get("ofType", "").strip_edges()
	select = conf.get("select", "").strip_edges()
	resultMap = conf.get("resultMap", "").strip_edges()
	foreignColumn = conf.get("foreignColumn", "").strip_edges()
	autoMapping = conf.get("autoMapping", "").strip_edges()
	
func push_element(element):
	if not result_embeded:
		result_embeded = GBatisResultMap.new({})
	result_embeded.push_back(element)
