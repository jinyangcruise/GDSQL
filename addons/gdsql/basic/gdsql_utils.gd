@tool
extends Object

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
	var expression = GDSQL.SQLExpression.new()
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
	
## 执行一个表达式，但使用我们自己的GDSQL.SQLExpression
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
	var expression = GDSQL.SQLExpression.EXPRESSION_CACHE.get_value(ex_key) # ALERT UNSAFE
	if not expression:
		expression = GDSQL.SQLExpression.new()
		expression.sql_mode = true
		expression.set_sql_input_names(sql_input_names)
		expression.set_nested_sql_queries(nested_subqueries)
		var error = expression.parse(command, variable_names, sql_static_inputs)
		if error != OK:
			push_error(expression.get_error_text())
			return null
		GDSQL.SQLExpression.EXPRESSION_CACHE.put_value(ex_key, expression)
		
	# 缺少一些表
	if not expression.get_lack_input_names().is_empty():
		if lacking_tables is Array:
			lacking_tables.append_array(expression.get_lack_input_names())
		return null
		
	var ret = expression.execute(variable_values, sql_varying_inputs, target, false)
	
	if expression.error_set:
		# 有可能expression自己有问题，清除缓存，否则就算改了代码也一直有问题
		GDSQL.SQLExpression.EXPRESSION_CACHE.remove_value(ex_key)
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
static func evalute_command_with_agg(target: GDSQL.AggregateFunctions, command: String, 
variable_names: Array = [], variable_values: Array = [], 
sql_input_names: Dictionary = {}, sql_static_inputs: Array = [], 
sql_varying_inputs: Dictionary = {}, nested_subqueries = {}):
	var ex_key = [command, variable_names, sql_input_names, sql_static_inputs, nested_subqueries]
	var expression = GDSQL.SQLExpression.EXPRESSION_CACHE.get_value(ex_key) # ALERT UNSAFE
	if not expression:
		expression = GDSQL.SQLExpression.new()
		expression.sql_mode = true
		expression.set_sql_input_names(sql_input_names)
		expression.set_nested_sql_queries(nested_subqueries)
		var error = expression.parse(command, variable_names, sql_static_inputs)
		if error != OK:
			push_error(expression.get_error_text())
			return null
		GDSQL.SQLExpression.EXPRESSION_CACHE.put_value(ex_key, expression)
		# TODO all const 可以缓存结果
	var ret = expression.execute(variable_values, sql_varying_inputs, target, true)
	
	if expression.error_set:
		# 有可能expression自己有问题，清除缓存，否则就算改了代码也一直有问题
		GDSQL.SQLExpression.EXPRESSION_CACHE.remove_value(ex_key)
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
	
## FileAccess.file_exists 不支持 install:// 路径，此函数先做路径转换再检查
static func file_exists(path: String) -> bool:
	return FileAccess.file_exists(globalize_path(path))
	
## 由于在导出的游戏中，ProjectSettings.globalize_path()函数不能正确处理"res://"(@see
## Godot Doc)，所以在这里统一处理。
static func globalize_path(path: String) -> String:
	if path.begins_with("install://"):
		return OS.get_executable_path().get_base_dir().path_join(path.substr("install://".length())).simplify_path()
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path(path).simplify_path()
	else:
		return path.simplify_path()
		
static func localize_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://") or path.begins_with("install://") or path.begins_with("uid://"):
		return path.simplify_path()
	if OS.has_feature("editor"):
		return ProjectSettings.localize_path(path)
	else:
		return path.simplify_path()
		
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
	
static func get_specific_extension_files(p_path: String, extension: String) -> Array[String]:
	var ret: Array[String] = []
	var dir = DirAccess.open(p_path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			# 子目录
			if dir.current_is_dir():
				# print("Found directory: " + file_name)
				pass # 不支持发现子目录里的数据，用户可自行把子目录创建为新的数据库即可
			# 文件
			else:
				if file_name.get_extension().to_lower() == extension:
					ret.push_back(file_name)
					
			file_name = dir.get_next()
		dir.list_dir_end()
	else:
		# 注意：git不能提交空目录，可能是因为这个导致clone下来的代码没有空目录
		# 这种情况下，请自己手动创建个空目录即可
		var msg = "Can not open the path: %s." % p_path
		if Engine.is_editor_hint():
			EditorInterface.get_editor_toaster().push_toast(msg, EditorToaster.SEVERITY_WARNING)
		push_warning(msg)
		
	return ret
	
## Compare two semver strings. Returns -1, 0, or 1.
static func cmp_version(a: String, b: String) -> int:
	var pa = a.split(".")
	var pb = b.split(".")
	for i in range(max(pa.size(), pb.size())):
		var va = int(pa[i]) if i < pa.size() else 0
		var vb = int(pb[i]) if i < pb.size() else 0
		if va < vb:
			return -1
		if va > vb:
			return 1
	return 0
	
## Parse upgrade_ranges from release body and return max version the current ver can reach.
## Format: upgrade_ranges: 0.5.0-0.5.99|0.6.0-999.999.999
static func parse_max_upgrade(body: String, current_ver: String) -> String:
	if body.is_empty():
		return ""
	var lines = body.split("\n")
	var range_line = ""
	for l in lines:
		var trimmed = l.trim_prefix(" ").trim_prefix("\t")
		if trimmed.begins_with("upgrade_ranges:"):
			range_line = trimmed.trim_prefix("upgrade_ranges:").strip_edges()
			break
	if range_line.is_empty():
		return ""
		
	var ranges = range_line.split("|")
	for r in ranges:
		var parts = r.split("-")
		if parts.size() != 2:
			continue
		var from_v = parts[0].strip_edges()
		var to_v = parts[1].strip_edges()
		if cmp_version(current_ver, from_v) >= 0 and cmp_version(current_ver, to_v) <= 0:
			return to_v
	return ""
	
## Convert Markdown/HTML text to BBCode for RichTextLabel display.
## Handles both HTML tags (from GitHub API) and Markdown syntax.
## Supported: headings, bold, italic, inline code, links, code blocks,
## ul/ol lists, tables (rendered in [code] monospace), horizontal rules.
static func markdown_to_bbcode(md: String) -> String:
	if md.is_empty():
		return ""

	# Step 0: Pre-escape bare [word] patterns before conversion
	var result = _pre_escape_brackets(md)

	# Pass 1: Convert HTML tags to BBCode (for content from GitHub that has HTML)
	result = _html_to_bbcode(result)

	# Pass 2: Process remaining Markdown syntax
	# Strip upgrade_ranges metadata line
	var lines = result.split("\n")
	var filtered: PackedStringArray = []
	for line in lines:
		if not line.strip_edges(true, false).begins_with("upgrade_ranges:"):
			filtered.append(line)
	lines = filtered

	var out: PackedStringArray = []
	var in_code_block = false
	var in_table = false
	var table_rows: PackedStringArray = []

	for line in lines:
		var trimmed = line.strip_edges()

		# Skip HTML comment remnants
		if trimmed.begins_with("<!--"):
			continue

		# Fenced code block start/end
		if trimmed.begins_with("```"):
			if in_code_block:
				out.append("[/code]")
				in_code_block = false
			else:
				out.append("[code]")
				in_code_block = true
			continue

		if in_code_block:
			out.append(line)
			continue

		# Table rows — detect pipe tables (even without leading |)
		if _is_table_row(trimmed):
			# Check if it's a separator row (---|---)
			var sep_check = trimmed.replace("|", "").strip_edges()
			if not sep_check.is_empty():
				var _is_sep = true
				for c in sep_check:
					if c not in ["-", ":", " "]:
						_is_sep = false
						break
				if _is_sep:
					continue
			if not in_table:
				in_table = true
				table_rows.clear()
			# Convert pipe separators to [cell] tags
			var cells = trimmed.split("|")
			var row = ""
			for cell in cells:
				var c = cell.strip_edges()
				if not c.is_empty():
					row += "[cell border=gray]" + c + "[/cell]"
			table_rows.append(row)
			continue
		else:
			if in_table:
				if table_rows.size() > 0:
					table_rows[0] = table_rows[0].replace("[cell border=gray]", "[cell border=gray][b]").replace("[/cell]", "[/b][/cell]")
				var _cols = (table_rows[0].count("[cell]") + table_rows[0].count("[cell ")) if table_rows.size() > 0 else 2
				out.append("\n[table=" + str(_cols) + "]\n" + "\n".join(table_rows) + "\n[/table]\n")
				in_table = false
				table_rows.clear()

		# Horizontal rule
		# Horizontal rule
		if trimmed == "---":
			out.append("\n[color=gray]" + "─".repeat(50) + "[/color]")
			continue

		# Headings with font size
		if trimmed.begins_with("### "):
			line = "[b][font_size=24]" + line.trim_prefix("### ") + "[/font_size][/b]"
		elif trimmed.begins_with("## "):
			line = "[b][font_size=28]" + line.trim_prefix("## ") + "[/font_size][/b]"
		elif trimmed.begins_with("# "):
			line = "[b][font_size=32]" + line.trim_prefix("# ") + "[/font_size][/b]"

		# Inline formatting: bold italic, bold, italic, code, links
		line = _replace_pair(line, "***", "***", "[b][i]", "[/i][/b]")
		line = _replace_pair(line, "**", "**", "[b]", "[/b]")
		line = _replace_pair(line, "*", "*", "[i]", "[/i]")
		line = _replace_pair(line, "`", "`", "[code]", "[/code]")
		line = _replace_links(line)

		out.append(line)

	# Flush remaining code block or table
	if in_code_block:
		out.append("[/code]")
	if in_table:
		if table_rows.size() > 0:
			table_rows[0] = table_rows[0].replace("[cell border=gray]", "[cell border=gray][b]").replace("[/cell]", "[/b][/cell]")
		var _cols = (table_rows[0].count("[cell]") + table_rows[0].count("[cell ")) if table_rows.size() > 0 else 2
		out.append("\n[table=" + str(_cols) + "]\n" + "\n".join(table_rows) + "\n[/table]\n")

	return "\n".join(out)


## Check if a line looks like a pipe table row (contains | with content on both sides).
static func _is_table_row(text: String) -> bool:
	var trimmed = text.strip_edges()
	if not trimmed.contains("|"):
		return false
	var parts = trimmed.split("|")
	# Need at least 2 columns with content
	if parts.size() < 2:
		return false
	var non_empty = 0
	for p in parts:
		if not p.strip_edges().is_empty():
			non_empty += 1
	return non_empty >= 2

## Escape [word] patterns BEFORE BBCode conversion.
## Standard Markdown has no BBCode tags, so bare [word] is literal text.
## Uses [lb]/[rb] so Godot renders them as literal brackets.
static func _pre_escape_brackets(text: String) -> String:
	var result = text
	var i = 0
	while i < result.length():
		if result[i] == "[":
			var close = result.find("]", i)
			if close == -1 or close - i > 50:
				i += 1
				continue
			# Skip Markdown links: [text](url)
			if close + 1 < result.length() and result[close + 1] == "(":
				i = close + 1
				continue
			# Skip Markdown images: ![alt](url)
			if i > 0 and result[i - 1] == "!":
				i = close + 1
				continue
			var tag_content = result.substr(i + 1, close - i - 1)
			if tag_content.is_empty():
				i += 1
				continue
			# Check if first char is a letter or /
			var check = tag_content[0]
			if check == "/" and tag_content.length() > 1:
				check = tag_content[1]
			if (check >= "a" and check <= "z") or (check >= "A" and check <= "Z"):
				# Escape: [word] -> [lb]word[rb]
				var escaped = result.substr(i + 1, close - i - 1)
				result = result.substr(0, i) + "[lb]" + escaped + "[rb]" + result.substr(close + 1)
				i = close + 5
				continue
		i += 1
	return result

## Convert HTML tags to BBCode equivalents.
static func _html_to_bbcode(text: String) -> String:
	var result = text

	# Decode HTML entities
	result = result.replace("&amp;", "&")
	result = result.replace("&lt;", "<")
	result = result.replace("&gt;", ">")
	result = result.replace("&quot;", "\"")
	result = result.replace("&#39;", "'")
	result = result.replace("&#x27;", "'")
	result = result.replace("&nbsp;", " ")

	# Remove HTML comments
	result = RegEx.create_from_string("<!--[\\s\\S]*?-->").sub(result, "", true)

	# Block-level tags — replace with newline-wrapped BBCode
	result = _replace_html_tag(result, "h1", "\n[b][font_size=32]", "[/font_size][/b]\n")
	result = _replace_html_tag(result, "h2", "\n[b][font_size=28]", "[/font_size][/b]\n")
	result = _replace_html_tag(result, "h3", "\n[b][font_size=24]", "[/font_size][/b]\n")
	result = _replace_html_tag(result, "h4", "\n[b]", "[/b]\n")
	result = _replace_html_tag(result, "h5", "\n[b]", "[/b]\n")
	result = _replace_html_tag(result, "h6", "\n[b]", "[/b]\n")

	# Lists
	result = _replace_html_tag_pair(result, "ul", "", "")
	result = _replace_html_tag_pair(result, "ol", "", "")
	result = _replace_html_tag_pair(result, "li", "[ul]", "[/ul]")

	# Paragraphs and divs
	result = _replace_html_tag_pair(result, "p", "", "\n")
	result = _replace_html_tag_pair(result, "div", "", "\n")

	# Horizontal rule
	result = result.replace("<hr />", "\n[color=gray]" + "─".repeat(50) + "[/color]\n")
	result = result.replace("<hr/>", "\n[color=gray]" + "─".repeat(50) + "[/color]\n")

	# Line breaks
	result = result.replace("<br />", "\n")
	result = result.replace("<br/>", "\n")
	result = result.replace("<br>", "\n")

	# Inline tags
	result = _replace_html_tag(result, "strong", "[b]", "[/b]")
	result = _replace_html_tag(result, "b", "[b]", "[/b]")
	result = _replace_html_tag(result, "em", "[i]", "[/i]")
	result = _replace_html_tag(result, "i", "[i]", "[/i]")
	result = _replace_html_tag(result, "u", "[u]", "[/u]")
	result = _replace_html_tag(result, "s", "[s]", "[/s]")
	result = _replace_html_tag(result, "del", "[s]", "[/s]")
	result = _replace_html_tag(result, "code", "[code]", "[/code]")
	result = _replace_html_tag(result, "kbd", "[kbd]", "[/kbd]")

	# Links
	result = _replace_html_links(result)

	# Tables
	result = _replace_html_tag_pair(result, "table", "
[table=2]", "[/table]
")
	result = _replace_html_tag_pair(result, "thead", "", "")
	result = _replace_html_tag_pair(result, "tbody", "", "")
	result = _replace_html_tag_pair(result, "tr", "", "
")
	result = _replace_html_tag(result, "th", "[cell border=gray]", "[/cell]")
	result = _replace_html_tag(result, "td", "[cell border=gray]", "[/cell]")

	# Images — show as alt text or placeholder
	result = _replace_html_img(result)

	# Strip any remaining HTML tags
	result = _strip_html_tags(result)

	return result


## Replace a specific HTML tag pair with BBCode equivalents.
## Handles <tag>content</tag> and <tag attr="val">content</tag>.
static func _replace_html_tag(text: String, tag: String, bb_open: String, bb_close: String) -> String:
	var result = text
	var open_prefix = "<" + tag
	var close_tag = "</" + tag + ">"
	var i = 0
	while i < result.length():
		var start = result.find(open_prefix, i)
		if start == -1:
			break
		# Make sure it's actually a tag (followed by >, space, /, or newline)
		var after = start + open_prefix.length()
		if after < result.length() and result[after] not in [">", " ", "/", "\t", "\n"]:
			i = start + 1
			continue
		var gt = result.find(">", start)
		if gt == -1:
			break
		# Self-closing tag — skip
		if gt > 0 and result[gt - 1] == "/":
			result = result.substr(0, start) + result.substr(gt + 1)
			i = start
			continue
		var end = result.find(close_tag, gt + 1)
		if end == -1:
			i = gt + 1
			continue
		var inner = result.substr(gt + 1, end - gt - 1)
		result = result.substr(0, start) + bb_open + inner + bb_close + result.substr(end + close_tag.length())
		i = start + bb_open.length() + inner.length() + bb_close.length()
	return result


## Replace a container tag pair, keeping content inside.
static func _replace_html_tag_pair(text: String, tag: String, bb_open: String, bb_close: String) -> String:
	var result = text
	var open_prefix = "<" + tag
	var close_tag = "</" + tag + ">"
	var i = 0
	while i < result.length():
		var start = result.find(open_prefix, i)
		if start == -1:
			break
		var after = start + open_prefix.length()
		if after < result.length() and result[after] not in [">", " ", "/", "\t", "\n"]:
			i = start + 1
			continue
		var gt = result.find(">", start)
		if gt == -1:
			break
		var end = result.find(close_tag, gt + 1)
		if end == -1:
			result = result.substr(0, start) + bb_open + result.substr(gt + 1)
			i = start + bb_open.length()
			continue
		var inner = result.substr(gt + 1, end - gt - 1)
		result = result.substr(0, start) + bb_open + inner + bb_close + result.substr(end + close_tag.length())
		i = start + bb_open.length() + inner.length() + bb_close.length()
	return result


## Convert <a href="url">text</a> to [url=url]text[/url].
static func _replace_html_links(text: String) -> String:
	var result = text
	var i = 0
	while i < result.length():
		var start = result.find("<a ", i)
		if start == -1:
			break
		var gt = result.find(">", start)
		if gt == -1:
			break
		var tag_html = result.substr(start, gt - start)
		# Extract href value
		var href_idx = tag_html.find("href=")
		if href_idx == -1:
			i = start + 1
			continue
		var val_start = href_idx + 5  # after "href="
		var quote_char = ""
		if val_start < tag_html.length() and tag_html[val_start] in ['"', "'"]:
			quote_char = tag_html[val_start]
			val_start += 1
		var href_end = tag_html.length()
		if not quote_char.is_empty():
			var qpos = tag_html.find(quote_char, val_start)
			if qpos != -1:
				href_end = qpos
		var href = tag_html.substr(val_start, href_end - val_start)
		var close = result.find("</a>", gt)
		if close == -1:
			i = start + 1
			continue
		var link_text = result.substr(gt + 1, close - gt - 1)
		var replacement = "[url=" + href + "]" + link_text + "[/url]"
		result = result.substr(0, start) + replacement + result.substr(close + 4)
		i = start + replacement.length()
	return result


## Convert <img src="url" alt="text"> to alt text or placeholder.
static func _replace_html_img(text: String) -> String:
	var result = text
	var i = 0
	while i < result.length():
		var start = result.find("<img ", i)
		if start == -1:
			break
		var gt = result.find(">", start)
		if gt == -1:
			break
		var tag_html = result.substr(start, gt - start)
		var alt = ""
		var alt_idx = tag_html.find("alt=")
		if alt_idx != -1:
			var av = alt_idx + 4
			if av < tag_html.length() and tag_html[av] in ['"', "'"]:
				var q = tag_html[av]
				var ae = tag_html.find(q, av + 1)
				if ae != -1:
					alt = tag_html.substr(av + 1, ae - av - 1)
		var replacement = alt if not alt.is_empty() else "[image]"
		result = result.substr(0, start) + replacement + result.substr(gt + 1)
		i = start + replacement.length()
	return result


## Strip specific single (non-pair) HTML tags.
static func _strip_single_tags(text: String, tags: Array[String]) -> String:
	var result = text
	for tag in tags:
		result = RegEx.create_from_string("<" + tag + "[^>]*>").sub(result, "", true)
	return result


## Strip all remaining HTML tags.
static func _strip_html_tags(text: String) -> String:
	return RegEx.create_from_string("<[^>]*>").sub(text, "", true)


## Replace a pair of delimiters with BBCode tags.
static func _replace_pair(text: String, open_delim: String, close_delim: String, bb_open: String, bb_close: String) -> String:
	var result = text
	var i = 0
	while i < result.length():
		var start = result.find(open_delim, i)
		if start == -1:
			break
		var end = result.find(close_delim, start + open_delim.length())
		if end == -1:
			break
		var inner = result.substr(start + open_delim.length(), end - start - open_delim.length())
		result = result.substr(0, start) + bb_open + inner + bb_close + result.substr(end + close_delim.length())
		i = start + bb_open.length() + inner.length() + bb_close.length()
	return result


## Convert Markdown links [text](url) to BBCode [url=url]text[/url].
static func _replace_links(text: String) -> String:
	var result = text
	var i = 0
	while i < result.length():
		var start = result.find("[", i)
		if start == -1:
			break
		var mid = result.find("](", start)
		if mid == -1 or mid - start > 300:
			i = start + 1
			continue
		var end = result.find(")", mid + 2)
		if end == -1 or end - mid > 500:
			i = mid + 2
			continue
		var link_text = result.substr(start + 1, mid - start - 1)
		var link_url = result.substr(mid + 2, end - mid - 2)
		var replacement = "[url=" + link_url + "]" + link_text + "[/url]"
		result = result.substr(0, start) + replacement + result.substr(end + 1)
		i = start + replacement.length()
	return result
