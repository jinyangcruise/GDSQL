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
	if typeof(ret) == TYPE_NIL:# and target == null:
		var target_class_name = "Object"
		if target and target.get_script() and target.get_script().get_global_name() != "":
			target_class_name = target.get_script().get_global_name()
		var script = GDScript.new()
		var defines = []
		for i in variable_names.size():
			defines.push_back("var %s = str_to_var('%s')" % [variable_names[i], var_to_str(variable_values[i]).c_escape()])
		script.source_code = "extends %s\n%s\nvar value = (%s)\n" % [target_class_name, "\n".join(defines), command]
		var err = script.reload()
		if err != OK:
			push_error("err: %s" % error_string(err))
			return null
		var obj = script.new()
		ret = obj.value
		if not obj is RefCounted:
			obj.free()
	return ret
	
## 用聚合对象执行一个表达式
## target：聚合对象。比如command里使用的一些函数、变量是在target里定义的
## command：表达式
## variable_names：参数名称列表
## variable_values：参数值列表
static func evalute_command_with_agg(target: AggregateFunctions, command: String, variable_names = [], variable_values = []):
	var expression = Expression.new()
	var error = expression.parse(command, variable_names)
	if error != OK:
		push_error(expression.get_error_text())
		return null
	var ret = expression.execute(variable_values, target, false)
	
	# 对于一些很简单的但Expression又不支持的写法，动态创建脚本
	if typeof(ret) == TYPE_NIL:
		var target_class_name = "Object"
		if target:
			target_class_name = "AggregateFunctionsProxy"
		var script = GDScript.new()
		var defines = []
		for i in variable_names.size():
			defines.push_back("var %s = str_to_var('%s')" % [variable_names[i], var_to_str(variable_values[i]).c_escape()])
		script.source_code = "extends %s\n%s\nvar value\nfunc ______e_v_a_l_u_a_t_e():\n\tvalue = (%s)\n" % [target_class_name, "\n".join(defines), command]
		var err = script.reload()
		if err != OK:
			push_error("err: %s" % error_string(err))
			return null
		var obj
		if target:
			obj = script.new(target.id)
		else:
			obj = script.new()
		obj.______e_v_a_l_u_a_t_e()
		ret = obj.value
		if not obj is RefCounted:
			obj.free()
	return ret
	
## 执行一个表达式，直接通过script方式
## target：环境对象。比如command里使用的一些函数、变量是在target里定义的
## command：表达式
## variable_names：参数名称列表
## variable_values：参数值列表
static func evaluate_command_script(command: String, variable_names = [], variable_values = []):
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
	var ret = obj.value
	obj.free()
	return ret
	
## 由于在导出的游戏中，ProjectSettings.globalize_path()函数不能正确处理"res://"(@see 
## Godot Doc)，所以在这里统一处理。如果是res:开头，或实际指向程序内资源，则返回一个res:开头
## 的目录
static func globalize_path(path: String) -> String:
	if path.begins_with("res://"):
		return path.simplify_path()
	if OS.has_feature("editor"):
		var res_path = ProjectSettings.globalize_path("res://")
		if path.begins_with(res_path):
			return ("res://" + path.substr(res_path.length())).simplify_path()
		return ProjectSettings.globalize_path(path).simplify_path()
	return path
