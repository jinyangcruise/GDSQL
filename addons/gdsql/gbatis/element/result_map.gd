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
var id: String
var type: String
var _extends: String
var auto_mapping: String

var result_embeded: Array

func _init(conf: Dictionary) -> void:
	id = conf.get("id", "").strip_edges()
	type = conf.get("type", "").strip_edges()
	_extends = conf.get("extends", "").strip_edges()
	auto_mapping = conf.get("autoMapping", "").strip_edges()
	
func push_element(element):
	result_embeded.push_back(element)
