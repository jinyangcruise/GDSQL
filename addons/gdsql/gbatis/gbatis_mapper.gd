@tool
extends Resource
## 数据访问类
class_name GBatisMapper

## mapper对应的xml配置
@export var mapper_xml: GXML

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
	for m in methods:
		if m.name == method:
			args = m.args
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
	return mapper_parser.query(method, params)
