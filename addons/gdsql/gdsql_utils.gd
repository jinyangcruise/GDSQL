extends Object
class_name GDSQLUtils

## 执行一个表达式
## target：环境对象。比如command里使用的一些函数、变量是在target里定义的
## command：表达式
## variable_names：参数名称列表
## variable_values：参数值列表
static func evaluate_command(target: Object, command: String, variable_names = [], variable_values = []):
	var expression = Expression.new()
	var error = expression.parse(command, variable_names)
	if error != OK:
		push_error(expression.get_error_text())
		return null
	var ret = expression.execute(variable_values, target, false)
	
	# 对于一些很简单的但Expression又不支持的写法，动态创建脚本
	if typeof(ret) == TYPE_NIL and target == null:
		var script = GDScript.new()
		var defines = []
		for i in variable_names.size():
			defines.push_back("var %s = str_to_var('%s')" % [variable_names[i], var_to_str(variable_values[i]).c_escape()])
		script.source_code = "extends Object\n%s\nvar value = (%s)\n" % ["\n".join(defines), command]
		var err = script.reload()
		if err != OK:
			push_error("err: %s" % error_string(err))
			return null
		var obj = script.new()
		ret = obj.value
		obj.free()
	return ret
