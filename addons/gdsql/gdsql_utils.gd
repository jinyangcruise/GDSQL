@tool
extends Object
class_name GDSQLUtils

## gdscript共享单例。GDScript resources are never removed due to extra reference in 
## GDScriptCache。为了避免过多的内存泄漏，我们用一个共享的单例来限制泄漏数量。
## @see https://github.com/godotengine/godot/issues/77513
## @see https://github.com/godotengine/godot/issues/99169
static var gdscript = GDScript.new()

## 执行一个表达式
## target：环境对象。比如command里使用的一些函数、变量是在target里定义的
## command：表达式
## variable_names：参数名称列表
## variable_values：参数值列表
static func evaluate_command(target: Object, command: String, variable_names = [], variable_values = []):
	var expression = GDSQLExpression.new()
	var error = expression.parse(command, variable_names)
	if error != OK:
		push_error(command, "\n", expression.get_error_text())
		return null
	var ret = expression.execute(variable_values, {}, target)
	
	# 对于一些很简单的但Expression又不支持的写法，动态创建脚本
	if typeof(ret) == TYPE_NIL:# and target == null:
		var target_class_name = "Object"
		if target and target.get_script() and target.get_script().get_global_name() != "":
			target_class_name = target.get_script().get_global_name()
		var defines = []
		for i in variable_names.size():
			defines.push_back("var %s = str_to_var('%s')" % [variable_names[i], var_to_str(variable_values[i]).c_escape()])
		gdscript.source_code = "extends %s\n%s\nvar value = (%s)\n" % [target_class_name, "\n".join(defines), command]
		var err = gdscript.reload()
		if err != OK:
			push_error("err: %s" % error_string(err))
			return null
		var obj = gdscript.new()
		ret = obj.value
		if not obj is RefCounted:
			obj.free()
	return ret
	
## 执行一个表达式，但使用我们自己的GDSQLExpression
## target：环境对象。比如command里使用的一些函数、变量是在target里定义的
## command：表达式
## variable_names：参数名称列表
## variable_values：参数值列表
## nested_subqueries: 嵌套的子查询
static func evaluate_command_with_sql_expression(target: Object, command: String, 
variable_names: Array = [], variable_values: Array = [], 
sql_input_names: Dictionary = {}, sql_static_inputs: Array = [], 
sql_varying_inputs: Dictionary = {}, nested_subqueries: Dictionary = {}, 
lacking_tables = null):
	var ex_key = [command, variable_names, sql_input_names, sql_static_inputs, nested_subqueries]
	var expression = GDSQLExpression.EXPRESSION_CACHE.get_value(ex_key) # ALERT UNSAFE
	if not expression:
		expression = GDSQLExpression.new()
		expression.sql_mode = true
		expression.set_sql_input_names(sql_input_names)
		expression.set_nested_sql_queries(nested_subqueries)
		var error = expression.parse(command, variable_names, sql_static_inputs)
		if error != OK:
			push_error(expression.get_error_text())
			return null
		GDSQLExpression.EXPRESSION_CACHE.put_value(ex_key, expression)
		
	# 缺少一些表
	if not expression.get_lack_input_names().is_empty():
		if lacking_tables:
			lacking_tables.append_array(expression.get_lack_input_names())
		return null
		
	var ret = expression.execute(variable_values, sql_varying_inputs, target, false)
	
	if expression.error_set:
		# 有可能expression自己有问题，清除缓存，否则就算改了代码也一直有问题
		GDSQLExpression.EXPRESSION_CACHE.remove_value(ex_key)
		push_error(expression.get_error_text())
		assert(false, expression.get_error_text())
		return null
		
	# 对于一些很简单的但Expression又不支持的写法，动态创建脚本
	#if typeof(ret) == TYPE_NIL:# and target == null:
		#var target_class_name = "Object"
		#if target and target.get_script() and target.get_script().get_global_name() != "":
			#target_class_name = target.get_script().get_global_name()
		#var defines = []
		#for i in variable_names.size():
			#defines.push_back("var %s = str_to_var('%s')" % [variable_names[i], var_to_str(variable_values[i]).c_escape()])
		#gdscript.source_code = "extends %s\n%s\nvar value = (%s)\n" % [target_class_name, "\n".join(defines), command]
		#var err = gdscript.reload()
		#if err != OK:
			#push_error("err: %s" % error_string(err))
			#return null
		#var obj = gdscript.new()
		#ret = obj.value
		#if not obj is RefCounted:
			#obj.free()
	return ret
	
## 用聚合对象执行一个表达式
## target：聚合对象。比如command里使用的一些函数、变量是在target里定义的
## command：表达式
## variable_names：参数名称列表
## variable_values：参数值列表
static func evalute_command_with_agg(target: AggregateFunctions, command: String, 
variable_names: Array = [], variable_values: Array = [], 
sql_input_names: Dictionary = {}, sql_static_inputs: Array = [], 
sql_varying_inputs: Dictionary = {}, nested_subqueries = {}):
	var ex_key = [command, variable_names, sql_input_names, sql_static_inputs, nested_subqueries]
	var expression = GDSQLExpression.EXPRESSION_CACHE.get_value(ex_key) # ALERT UNSAFE
	if not expression:
		expression = GDSQLExpression.new()
		expression.sql_mode = true
		expression.set_sql_input_names(sql_input_names)
		expression.set_nested_sql_queries(nested_subqueries)
		var error = expression.parse(command, variable_names, sql_static_inputs)
		if error != OK:
			push_error(expression.get_error_text())
			return null
		GDSQLExpression.EXPRESSION_CACHE.put_value(ex_key, expression)
		# TODO all const 可以缓存结果
	var ret = expression.execute(variable_values, sql_varying_inputs, target, true)
	
	if expression.error_set:
		# 有可能expression自己有问题，清除缓存，否则就算改了代码也一直有问题
		GDSQLExpression.EXPRESSION_CACHE.remove_value(ex_key)
		push_error(expression.get_error_text())
		assert(false, expression.get_error_text())
		return null
		
	## 对于一些很简单的但Expression又不支持的写法，动态创建脚本
	#if typeof(ret) == TYPE_NIL:
		#var target_class_name = "Object"
		#if target:
			#target_class_name = "AggregateFunctionsProxy"
		#var script = gdscript
		#var defines = []
		#for i in variable_names.size():
			#defines.push_back("var %s = str_to_var('%s')" % [variable_names[i], var_to_str(variable_values[i]).c_escape()])
		#script.source_code = "extends %s\n%s\nvar value\nfunc ______e_v_a_l_u_a_t_e():\n\tvalue = (%s)\n" % [target_class_name, "\n".join(defines), command]
		#var err = script.reload()
		#if err != OK:
			#push_error("err: %s" % error_string(err))
			#return null
		#var obj
		#if target:
			#obj = script.new(target.id)
		#else:
			#obj = script.new()
		#obj.______e_v_a_l_u_a_t_e()
		#ret = obj.value
		#if not obj is RefCounted:
			#obj.free()
	return ret
	
## 执行一个表达式，直接通过script方式
## target：环境对象。比如command里使用的一些函数、变量是在target里定义的
## command：表达式
## variable_names：参数名称列表
## variable_values：参数值列表
static func evaluate_command_script(command: String, variable_names = [], variable_values = []):
	var defines = []
	for i in variable_names.size():
		defines.push_back("var %s = str_to_var('%s')" % [variable_names[i], var_to_str(variable_values[i]).c_escape()])
	gdscript.source_code = "extends Object\n%s\nvar value = (%s)\n" % ["\n".join(defines), command]
	var err = gdscript.reload()
	if err != OK:
		push_error("err: %s" % error_string(err))
		return null
	var obj = gdscript.new()
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
	
## 找字符串中某个符号的位置。处于引号、括号内的符号不会计算在内。
## 返回数组的子元素是一个长度为2的数组，分别为开始位置和结束位置。
## 不支持符号是单引号或双引号或斜杠\。支持\s：looking_for = '\\s'
static func search_symbol(text: String, looking_for: String = ',', allow_empty: bool = true) -> Array:
	if looking_for == '\\s':
		if not (text.contains(" ") or text.contains("\t") or text.contains("\n")):
			return []
	elif not text.contains(looking_for):
		return []
		
	var stack = []  # 用于跟踪当前处理的引号层级
	var quote_types = {'"': '"', "'": "'", '(': ')', '[': ']', '{': '}'}
	var quote_types_values = quote_types.values()
	var in_quote = false  # 标记当前是否在引号内
	var real_quote = ["'", '"']
	var in_real_quote = [] # 标记当前是否在'或"里
	
	var str_ofs = -1
	var quote_start = []
	var ret = []
	while str_ofs < text.length() - 1:
		str_ofs += 1
		var a_char = text[str_ofs]
		# 转义了的引号是普通字符
		if a_char == '\\' and str_ofs + 1 < text.length() and text[str_ofs + 1] in real_quote:
			str_ofs += 1
			continue
			
		if a_char in quote_types or a_char in quote_types_values:
			if not in_quote and a_char in quote_types:  # 如果不在引号内，遇到引号则开始记录
				stack.append(a_char)  # 记录引号类型
				quote_start.append(str_ofs) # 记录引号开始位置
				in_quote = true
				if a_char == '"' or a_char == "'":
					in_real_quote.append(true)
			elif in_quote:  # 已在引号内，遇到相同类型的引号结束记录
				if quote_types[stack.back()] == a_char:
					var q = stack.pop_back()  # 移除栈顶的引号类型
					if q == '"' or q == "'":
						in_real_quote.pop_back()
					quote_start.pop_back()
					in_quote = not stack.is_empty()
				else:
					# 遇到新引号（不在'或"内）
					if in_real_quote.is_empty():
						if a_char in quote_types:
							stack.push_back(a_char)
							quote_start.push_back(str_ofs)
						elif a_char in quote_types_values:
							push_error("Error: Unmatched quote found in the text: %s" % text)
			else:
				push_error("Error: Unmatched quote found in the text: %s" % text)
		else:
			if not in_quote:
				if looking_for == '\\s':
					for i in [' ', '\n', '\t']:
						if text.count(i, str_ofs - i.length() + 1, str_ofs + 1) > 0:
							ret.push_back([str_ofs - i.length() + 1, str_ofs + 1])
							break
				elif text.count(looking_for, str_ofs - looking_for.length() + 1, str_ofs + 1) > 0:
					ret.push_back([str_ofs - looking_for.length() + 1, str_ofs + 1])
				
	# 如果栈不为空，说明有开始引号没有匹配的结束引号
	if stack.size() > 0:
		push_error("Error: Unmatched quote found in the text: %s" % text)
		
	if not allow_empty and ret.size() > 1:
		var remove = []
		var ofs = -1
		while ofs < ret.size() - 1:
			ofs += 1
			if ret.size() > ofs + 1:
				if ret[ofs][1] == ret[ofs + 1][0]:
					remove.push_back(ofs + 1)
					var j = ofs
					while j >= 0:
						if ret[j][1] == ret[ofs + 1][0]:
							ret[j][1] = ret[ofs + 1][1]
							j -= 1
						else:
							break
		if not remove.is_empty():
			remove.reverse()
			for i in remove:
				ret.remove_at(i)
	return ret
	
static func extract_outer_quotes(text: String):
	var stack = []  # 用于跟踪当前处理的引号层级
	var result = []  # 存储提取的引号内容
	var quote_types = {'"': '"', "'": "'", '(': ')', '[': ']', '{': '}'}
	var quote_types_values = quote_types.values()
	var in_quote = false  # 标记当前是否在引号内
	var real_quote = ["'", '"']
	var in_real_quote = [] # 标记当前是否在'或"里
	
	var str_ofs = -1
	var quote_start = []
	while str_ofs < text.length() - 1:
		str_ofs += 1
		var a_char = text[str_ofs]
		# 转义了的引号是普通字符
		if a_char == '\\' and str_ofs + 1 < text.length() and text[str_ofs + 1] in real_quote:
			str_ofs += 1
			continue
			
		if a_char in quote_types or a_char in quote_types_values:
			if not in_quote and a_char in quote_types:  # 如果不在引号内，遇到引号则开始记录
				stack.append(a_char)  # 记录引号类型
				quote_start.append(str_ofs) # 记录引号开始位置
				in_quote = true
				if a_char == '"' or a_char == "'":
					in_real_quote.append(true)
			elif in_quote:  # 已在引号内，遇到相同类型的引号结束记录
				if quote_types[stack.back()] == a_char:
					var q = stack.pop_back()  # 移除栈顶的引号类型
					if q == '"' or q == "'":
						in_real_quote.pop_back()
					if stack.is_empty():
						result.append(text.substr(quote_start[stack.size()], str_ofs - quote_start[stack.size()] + 1))  # 保存内容
					quote_start.pop_back()
					in_quote = not stack.is_empty()
				else:
					# 遇到新引号（不在'或"内）
					if in_real_quote.is_empty():
						if a_char in quote_types:
							stack.push_back(a_char)
							quote_start.push_back(str_ofs)
						elif a_char in quote_types_values:
							push_error("Error: Unmatched quote found in the text: %s" % text)
			else:
				push_error("Error: Unmatched quote found in the text: %s" % text)
	# 如果栈不为空，说明有开始引号没有匹配的结束引号
	if stack.size() > 0:
		push_error("Error: Unmatched quote found in the text: %s" % text)
		
	result.sort_custom(func(a, b): return a.length() > b.length())
	return result
	
static func extract_outer_bracket(text: String):
	var stack = []  # 用于跟踪当前处理的引号层级
	var result = []  # 存储提取的引号内容
	var quote_types = {'"': '"', "'": "'", '(': ')', '[': ']', '{': '}'}
	var quote_types_values = quote_types.values()
	var in_quote = false  # 标记当前是否在引号内
	var real_quote = ["'", '"']
	var in_real_quote = [] # 标记当前是否在'或"里
	
	var str_ofs = -1
	var quote_start = []
	while str_ofs < text.length() - 1:
		str_ofs += 1
		var a_char = text[str_ofs]
		# 转义了的引号是普通字符
		if a_char == '\\' and str_ofs + 1 < text.length() and text[str_ofs + 1] in real_quote:
			str_ofs += 1
			continue
			
		if a_char in quote_types or a_char in quote_types_values:
			if not in_quote and a_char in quote_types:  # 如果不在引号内，遇到引号则开始记录
				stack.append(a_char)  # 记录引号类型
				quote_start.append(str_ofs) # 记录引号开始位置
				in_quote = true
				if a_char == '"' or a_char == "'":
					in_real_quote.append(true)
			elif in_quote:  # 已在引号内，遇到相同类型的引号结束记录
				if quote_types[stack.back()] == a_char:
					var q = stack.pop_back()  # 移除栈顶的引号类型
					if q == '"' or q == "'":
						in_real_quote.pop_back()
					if stack.is_empty() and text.substr(quote_start[stack.size()], 1) == "(":
						result.append(text.substr(quote_start[stack.size()], str_ofs - quote_start[stack.size()] + 1))  # 保存内容
					quote_start.pop_back()
					in_quote = not stack.is_empty()
				else:
					# 遇到新引号（不在'或"内）
					if in_real_quote.is_empty():
						if a_char in quote_types:
							stack.push_back(a_char)
							quote_start.push_back(str_ofs)
						elif a_char in quote_types_values:
							push_error("Error: Unmatched quote found in the text: %s" % text)
			else:
				push_error("Error: Unmatched quote found in the text: %s" % text)
	# 如果栈不为空，说明有开始引号没有匹配的结束引号
	if stack.size() > 0:
		push_error("Error: Unmatched quote found in the text: %s" % text)
		
	result.sort_custom(func(a, b): return a.length() > b.length())
	return result
