@icon("res://addons/gdsql/gbatis/img/GBatisMapper.png")
@tool
extends Resource
## 数据访问类
class_name GBatisMapper

## mapper对应的xml配置
@export var mapper_xml: GXML

## autoMapping level.
## 全局自动映射等级。
## NONE - 禁用自动映射。仅对手动映射的属性进行映射。
## PARTIAL -对除在内部定义了嵌套结果映射（也就是连接的属性）以外的属性进行映射。
##          也就是对复杂属性以外的属性进行映射。复杂属性是指属性指向了一个对象（非Resource）。
@export_enum("NONE", "PARTIAL")
var auto_mapping_level: String = "PARTIAL"

## 如果mapper中的函数没有定义返回值类型，但是，GBatis该如何返回数据。
## - ALWAYS_ARRAY: 总是返回一个数组
@export_enum("ALWAYS_ARRAY", "ARRAY_WHEN_NECESSARY")
var return_type_undefined_behavior: String = "ALWAYS_ARRAY"

## 子类调用该函数实现自动执行sql命令。sql命令定义在xml中。
## NOTICE 子类method函数请勿使用`__bind__`作为形参名称
## TODO 等官方支持可变参数数量函数时，可以进行优化
## https://github.com/godotengine/godot/pull/82808
## btw: Ability to print and log script backtraces
## https://github.com/godotengine/godot/pull/91006
func query(method: String, arg1 = null, arg2 = null, arg3 = null, arg4 = null,
arg5 = null, arg6 = null, arg7 = null, arg8 = null, arg9 = null):
	assert(mapper_xml != null, "Not set mapper_xml.")
	var methods = get_method_list()
	var args = null
	var ret_info = null
	for m in methods:
		if m.name == method:
			args = m.args
			ret_info = m["return"]
			break
	assert(args != null, "Not found method %s" % method)
	var params = {}
	var arg_list = [arg9, arg8, arg7, arg6, arg5, arg4, arg3, arg2, arg1]
	for i in args:
		assert(i.name != "__bind__", 
			"Please change your param's name. `__bind__` is a reserved keyword.")
		params[i.name] = arg_list.pop_back()
		
	var mapper_parser = GBatisMapperParser.new()
	mapper_parser.config = mapper_xml
	mapper_parser.method_return_info = ret_info
	mapper_parser.auto_mapping_level = auto_mapping_level
	mapper_parser.return_type_undefined_behavior = return_type_undefined_behavior
	return mapper_parser.query(method, params)
