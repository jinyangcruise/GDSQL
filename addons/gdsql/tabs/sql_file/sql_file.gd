@tool
extends VSplitContainer

signal request_open_file(path: String)
signal change_tab_title(page: Control, title: String)

@onready var _code_edit: CodeEdit = %CodeEdit
@onready var button_commit: Button = %ButtonCommit
@onready var button_rollback: Button = %ButtonRollback
@onready var button_auto_commit: Button = %ButtonAutoCommit
@onready var button_continue_run: Button = %ButtonContinueRun
@onready var results_tab: TabContainer = %ResultsTab
@onready var v_split_container: VSplitContainer = %VSplitContainer


var code_edit: CodeEdit:
	get:
		return _code_edit
		
var mgr: GDSQL.WorkbenchManagerClass:
	get: return GDSQL.WorkbenchManager
		
func _ready() -> void:
	button_commit.disabled = button_auto_commit.button_pressed
	button_rollback.disabled = button_auto_commit.button_pressed
	
	var sb3: StyleBoxFlat = get_theme_stylebox(&"panel", &"TabContainer").duplicate()
	sb3.corner_radius_top_left = 5
	sb3.corner_radius_top_right = 0
	sb3.corner_radius_bottom_left = 5
	sb3.corner_radius_bottom_right = 0
	results_tab.add_theme_stylebox_override(&"panel", sb3)
	results_tab.set_theme_type_variation("TabContainerInner")
	
func _on_button_auto_commit_toggled(button_pressed: bool) -> void:
	button_commit.disabled = button_pressed
	button_rollback.disabled = button_pressed
	
func _on_button_open_pressed() -> void:
	EditorInterface.popup_quick_open(func(path: String):
		if not path.is_empty():
			request_open_file.emit(path)
	, [&"GDSQLText"])
	
func _on_button_save_pressed() -> void:
	# 本身就是一个已经保存的文件，就直接保存
	if get_meta("is_file"):
		var config = GDSQL.ImprovedConfigFile.new()
		config.set_value("data", "content", code_edit.text)
		config.save(get_meta("file_path"))
		change_tab_title.emit(self, get_meta("file_name").get_basename())
		if GDSQL.GDSQLUtils.localize_path(get_meta("file_path")).begins_with("res://"):
			EditorInterface.get_resource_filesystem().update_file(GDSQL.GDSQLUtils.localize_path(get_meta("file_path")))
		return
		
	_on_button_save_as_pressed()
	
func _on_button_save_as_pressed():
	var editor_file_dialog = EditorFileDialog.new()
	editor_file_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	editor_file_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	editor_file_dialog.add_filter("*.gdsqltext", "GDSQL Text File")
	editor_file_dialog.file_selected.connect(func(path: String):
		var config = GDSQL.ImprovedConfigFile.new()
		config.set_value("data", "content", code_edit.text)
		config.save(path)
		var file_name = path.get_file()
		change_tab_title.emit(self, file_name.get_basename())
		set_meta("type", "sql_file")
		set_meta("is_file", true)
		set_meta("file_name", file_name)
		set_meta("file_path", path)
		if GDSQL.GDSQLUtils.localize_path(get_meta("file_path")).begins_with("res://"):
			EditorInterface.get_resource_filesystem().update_file(GDSQL.GDSQLUtils.localize_path(get_meta("file_path")))
	)
	add_child(editor_file_dialog)
	editor_file_dialog.popup_centered_ratio(0.7)
	editor_file_dialog.close_requested.connect(editor_file_dialog.queue_free)
	
func _on_code_edit_text_changed() -> void:
	if get_meta("is_file"):
		change_tab_title.emit(self, get_meta("file_name").get_basename() + "*")
		
func load_sql_file(path: String):
	var config = GDSQL.ImprovedConfigFile.new()
	config.load(path)
	var content = config.get_value("data", "content", "")
	code_edit.text = content
	
	set_meta("type", "sql_file")
	set_meta("is_file", true)
	set_meta("file_path", path)
	set_meta("file_name", path.get_file())
	
func _on_button_run_all_pressed() -> void:
	# 清理旧的标签页
	var children = results_tab.get_children()
	for child in children:
		results_tab.remove_child(child)
		child.queue_free()
		
	# 1. 有选中的，执行选中的部分；2. 没有选中的，执行全部
	var text_to_run: String
	if code_edit.has_selection(0):
		text_to_run = code_edit.get_selected_text(0)
	else:
		text_to_run = code_edit.text
		
	if text_to_run.strip_edges().is_empty():
		return
		
	# 去掉注释后，按分号拆分为多条SQL语句
	var statements = _split_sql_statements(text_to_run)
	if statements.is_empty():
		return
		
	var index = 0
	var _continue_on_error = button_continue_run.button_pressed
	for sql in statements:
		if sql.strip_edges().is_empty():
			continue

		var dao = GDSQL.SQLParser.parse_to_dao(sql)
		if dao == null:
			mgr.add_log_history.emit("Err", Time.get_unix_time_from_system(), sql, "Parse failed")
			if not _continue_on_error:
				break
			continue

		var action = dao.get_query_cmd()
		var begin_time = Time.get_unix_time_from_system()
		var query_ret: GDSQL.QueryResult = await _deal_query_need_enter_password(dao, begin_time, action)
		if query_ret == null:
			mgr.add_log_history.emit("Err", begin_time, action, "something wrong")
			if not _continue_on_error:
				break
			continue

		if not query_ret.ok():
			mgr.add_log_history.emit("Err", begin_time, action, query_ret.get_err(), query_ret.get_cost_time())
			if not _continue_on_error:
				break
			continue
			
		index += 1
		var ret: GDSQL.QueryResult = null
		if dao.get_cmd().begins_with("select"):
			ret = query_ret
		else:
			var gen_dict = func(s):
				return {"select_name": s, "Column Name": s, "field_as": s,
					"is_field": false, "table_alias": "", "db_path": "",
					"table_name": "", "hint": PROPERTY_HINT_NONE,
					"Hint String": "", "Data Type": TYPE_NIL,
					"Default(Expression)": ""}
			ret = GDSQL.QueryResult.new()
			ret._has_head = true
			ret._data = [
				["err", "affected_rows", "warnings", "last_insert_id", "generated_keys", "cost_time"]
					.map(gen_dict),
				[
					query_ret.get_err(),
					query_ret.get_affected_rows(),
					query_ret.get_warnings(),
					query_ret.get_last_insert_id(),
					query_ret.get_generated_keys(),
					query_ret.get_cost_time(),
				]
			]
			
		var table_node = gen_table_node(ret.get_head(), ret.get_data(), dao.is_union_all(), dao.get_left_join_conds())
		table_node.name = tr("Result") + " " + str(index)
		table_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		table_node.size_flags_vertical = Control.SIZE_EXPAND_FILL
		results_tab.add_child(table_node, true)
		results_tab.show()
		
		if dao.get_cmd().begins_with("select"):
			mgr.add_log_history.emit("OK", begin_time, action,
				"%d row(s) returned" % (query_ret.get_data().size()),
				ret.get_cost_time())
		else:
			mgr.add_log_history.emit("OK", begin_time, action,
				"%d row(s) affected" % (query_ret.get_affected_rows()),
				query_ret.get_cost_time())
				
## 将SQL文本去掉注释后，按分号拆分为独立的语句数组。
## 分号在字符串字面量内不会被当作分隔符。
func _split_sql_statements(text: String) -> Array[String]:
	var pos_map: Array[int] = []
	var clean_text = _strip_sql_comments(text, pos_map)
	
	var statements: Array[String] = []
	var stmt_start = 0
	var in_sq = false
	var in_dq = false
	var i = 0
	while i < clean_text.length():
		var ch = clean_text[i]
		if ch == "'" and not in_dq:
			in_sq = not in_sq
		elif ch == '"' and not in_sq:
			in_dq = not in_dq
		elif ch == ";" and not in_sq and not in_dq:
			var stmt = clean_text.substr(stmt_start, i - stmt_start).strip_edges()
			if not stmt.is_empty():
				statements.push_back(stmt)
			stmt_start = i + 1
		i += 1
		
	# 最后一段（末尾没有分号的情况）
	var last_stmt = clean_text.substr(stmt_start).strip_edges()
	if not last_stmt.is_empty():
		statements.push_back(last_stmt)
		
	return statements

func _on_button_run_edit_pressed() -> void:
	# 清理旧的标签页
	var children = results_tab.get_children()
	for child in children:
		results_tab.remove_child(child)
		child.queue_free()
		
	# 已知sql语句是用分号来进行划分的，在一行中，如果出现 -- （两个减号 + 空格）或 # 或 /*  */，
	# 则表示注释内容。
	# 我们的目标是：找出光标所在行的单个sql语句。这个sql语句可能跨行了，在光标所在行的上方或下方，都有可能。
	# 另外，光标所在行还有可能存在多个sql语句，那么就要考虑光标的column是处于哪个sql语句了。此外，还要
	# 把注释部分去掉。
	var sql = _get_sql_at_cursor()
	if sql.strip_edges().is_empty():
		return
		
	var dao = GDSQL.SQLParser.parse_to_dao(sql)
	if dao == null:
		mgr.add_log_history.emit("Err", Time.get_unix_time_from_system(), sql, "Parse failed")
		return
		
	var action = dao.get_query_cmd()
	var begin_time = Time.get_unix_time_from_system()
	var query_ret: GDSQL.QueryResult = await _deal_query_need_enter_password(dao, begin_time, action)
	if query_ret == null:
		mgr.add_log_history.emit("Err", begin_time, action, "something wrong")
		return
		
	if not query_ret.ok():
		mgr.add_log_history.emit("Err", begin_time, action, query_ret.get_err(), query_ret.get_cost_time())
		return
		
	var ret: GDSQL.QueryResult = null
	if dao.get_cmd().begins_with("select"):
		ret = query_ret
	else:
		var gen_dict = func(s):
			return {"select_name": s, "Column Name": s, "field_as": s, 
				"is_field": false, "table_alias": "", "db_path": "", 
				"table_name": "", "hint": PROPERTY_HINT_NONE, 
				"Hint String": "", "Data Type": TYPE_NIL,
				"Default(Expression)": ""}
		ret = GDSQL.QueryResult.new()
		ret._has_head = true
		ret._data = [
			["err", "affected_rows", "warnings", "last_insert_id", "generated_keys", "cost_time"]
				.map(gen_dict),
			[
				query_ret.get_err(),
				query_ret.get_affected_rows(),
				query_ret.get_warnings(),
				query_ret.get_last_insert_id(),
				query_ret.get_generated_keys(),
				query_ret.get_cost_time(),
			]
		]
		
	var table_node = gen_table_node(ret.get_head(), ret.get_data(), dao.is_union_all(), dao.get_left_join_conds())
	table_node.name = "Result"
	table_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table_node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	results_tab.add_child(table_node, true)
	results_tab.show()
	
	if dao.get_cmd().begins_with("select"):
		mgr.add_log_history.emit("OK", begin_time, action, 
			"%d row(s) returned" % (query_ret.get_data().size()), 
			ret.get_cost_time()) # 去掉表头
	else:
		mgr.add_log_history.emit("OK", begin_time, action, 
			"%d row(s) affected" % (query_ret.get_affected_rows()), 
			query_ret.get_cost_time())
			
func _deal_query_need_enter_password(dao: GDSQL.BaseDao, begin_time, action):
	var ret
	var reach_max = false
	for i in 100:
		reach_max = i == 99
		ret = dao.query()
		if dao.need_user_enter_password():
			var password_ret = [null]
			mgr.request_curr_password(password_ret)
			while true:
				await get_tree().process_frame
				if password_ret[0] != null:
					break
			if password_ret[0]:
				continue
			else:
				mgr.add_log_history.emit("Err", begin_time, action, 
					"Missing password : [%s%s]!" % mgr.get_password_request_table())
		break
	if reach_max and dao.need_user_enter_password():
		mgr.add_log_history.emit("Err", begin_time, action, "Too many tables need enter password!")
	return ret
	
## 获取光标所在的单个SQL语句（去掉注释）
func _get_sql_at_cursor() -> String:
	var caret_line = code_edit.get_caret_line(0)
	var caret_column = code_edit.get_caret_column(0)
	var full_text = code_edit.text
	var lines = full_text.split("\n")
	
	# 去掉注释，并建立清理后文本到原始文本的位置映射
	var pos_map: Array[int] = []
	var clean_text = _strip_sql_comments(full_text, pos_map)
	
	# 计算光标在原始文本中的偏移量
	var cursor_offset = 0
	for i in caret_line:
		cursor_offset += lines[i].length() + 1  # +1 for \n
	cursor_offset += caret_column
	
	# 通过二分查找得到光标在清理后文本中的位置
	var clean_cursor = _bisect_right(pos_map, cursor_offset)
	
	# 在清理后的文本中扫描分号，定位语句边界
	var stmt_start = 0
	var in_sq = false
	var in_dq = false
	var j = 0
	while j < clean_text.length():
		var ch = clean_text[j]
		if ch == "'" and not in_dq:
			in_sq = not in_sq
		elif ch == "\"" and not in_sq:
			in_dq = not in_dq
		elif ch == ";" and not in_sq and not in_dq:
			var stmt = clean_text.substr(stmt_start, j - stmt_start).strip_edges()
			if not stmt.is_empty():
				# 找到结束位置并检查光标是否在语句范围内
				var s = stmt_start
				while s < j and clean_text[s] in " \t\r\n":
					s += 1
				var e = j - 1
				while e > s and clean_text[e] in " \t\r\n":
					e -= 1
				if clean_cursor >= s and clean_cursor <= e + 1:
					var os = pos_map[s] if s < pos_map.size() else 0
					var oe = pos_map[e] if e < pos_map.size() else 0
					return full_text.substr(os, oe - os + 1).strip_edges()
				if clean_cursor < s:
					# 光标在当前语句之前，取最近的语句
					if not stmt.is_empty():
						var os = pos_map[s] if s < pos_map.size() else 0
						var oe = pos_map[e] if e < pos_map.size() else 0
						return full_text.substr(os, oe - os + 1).strip_edges()
			stmt_start = j + 1
		j += 1
		
	# 处理最后一段（末尾没有分号的情况）
	var last_stmt = clean_text.substr(stmt_start).strip_edges()
	if not last_stmt.is_empty():
		var s = stmt_start
		while s < clean_text.length() and clean_text[s] in " \t\r\n":
			s += 1
		var e = clean_text.length() - 1
		while e > s and clean_text[e] in " \t\r\n":
			e -= 1
		if clean_cursor >= s:
			var os = pos_map[s] if s < pos_map.size() else 0
			var oe = pos_map[e] if e < pos_map.size() else 0
			return full_text.substr(os, oe - os + 1).strip_edges()
			
	# 回退：找最近的非空语句
	var best = ""
	var best_dist = 999999999
	stmt_start = 0
	in_sq = false
	in_dq = false
	j = 0
	while j < clean_text.length():
		var ch = clean_text[j]
		if ch == "'" and not in_dq:
			in_sq = not in_sq
		elif ch == "\"" and not in_sq:
			in_dq = not in_dq
		elif ch == ";" and not in_sq and not in_dq:
			var stmt = clean_text.substr(stmt_start, j - stmt_start).strip_edges()
			if not stmt.is_empty():
				var s = stmt_start
				while s < j and clean_text[s] in " \t\r\n":
					s += 1
				var e = j - 1
				while e > s and clean_text[e] in " \t\r\n":
					e -= 1
				var mid = (s + e) / 2.0
				var dist = absi(clean_cursor - mid)
				if dist < best_dist:
					best_dist = dist
					var os = pos_map[s] if s < pos_map.size() else 0
					var oe = pos_map[e] if e < pos_map.size() else 0
					best = full_text.substr(os, oe - os + 1).strip_edges()
			stmt_start = j + 1
		j += 1
		
	var last_stmt2 = clean_text.substr(stmt_start).strip_edges()
	if not last_stmt2.is_empty():
		var s = stmt_start
		while s < clean_text.length() and clean_text[s] in " \t\r\n":
			s += 1
		var e = clean_text.length() - 1
		while e > s and clean_text[e] in " \t\r\n":
			e -= 1
		var mid = (s + e) / 2.0
		var dist = absi(clean_cursor - mid)
		if dist < best_dist:
			var os = pos_map[s] if s < pos_map.size() else 0
			var oe = pos_map[e] if e < pos_map.size() else 0
			best = full_text.substr(os, oe - os + 1).strip_edges()
	return best
	
## 去掉SQL注释（-- 、#、/* */），保留字符串字面量。
## 同时构建 pos_map：clean_text[i] 对应原始文本中的 pos_map[i]。
func _strip_sql_comments(text: String, pos_map: Array[int]) -> String:
	var result = ""
	var i = 0
	var t_len = text.length()
	while i < t_len:
		var ch = text[i]
		# 单引号字符串字面量
		if ch == "'":
			result += ch
			pos_map.push_back(i)
			i += 1
			while i < t_len:
				result += text[i]
				pos_map.push_back(i)
				if text[i] == "'":
					i += 1
					break
				i += 1
			continue
		# 双引号标识符
		if ch == '"':
			result += ch
			pos_map.push_back(i)
			i += 1
			while i < t_len:
				result += text[i]
				pos_map.push_back(i)
				if text[i] == '"':
					i += 1
					break
				i += 1
			continue
		# 行注释：-- （两个减号）
		if ch == "-" and i + 1 < t_len and text[i + 1] == "-":
			while i < t_len and text[i] != "\n":
				i += 1
			continue
		# 行注释：#
		if ch == "#":
			while i < t_len and text[i] != "\n":
				i += 1
			continue
		# 块注释：/* ... */
		if ch == "/" and i + 1 < t_len and text[i + 1] == "*":
			i += 2
			while i < t_len:
				if text[i] == "*" and i + 1 < t_len and text[i + 1] == "/":
					i += 2
					break
				i += 1
			continue
		result += ch
		pos_map.push_back(i)
		i += 1
	return result
	
## 类似 Python 的 bisect_right：返回 pos_map 中第一个 > val 的索引
func _bisect_right(arr: Array[int], val: int) -> int:
	var lo = 0
	var hi = arr.size()
	while lo < hi:
		var mid = (lo + hi) / 2.0
		if arr[mid] <= val:
			lo = mid + 1
		else:
			hi = mid
	return lo
	
func gen_table_node(columns: Array, table_datas: Array, is_union_all: bool, join_conds: Array) -> MarginContainer:
#region 每列的属性名称要重新定义
	var single_table_query = join_conds.is_empty() # 是否为单表查询
	var hint = {} # 每列的hint
	var map_table_path_index = {} # 临时变量：记录每个表分组的序号
	var last_table_path = "" # 临时变量：记录上一列的表路径
	var last_prefix = "" # 临时变量：记录上一列使用的名称前缀
	var dealed_columns = {} # 临时变量：记录已经处理过的真实列名
	var real_col_name_name = {} # 临时变量：记录列名对应的真实列名
	var new_column_prop_name = [] # 保存包含用于分组的属性和数据列的所有属性
	var table_primary_index = {} # 保存每个表的主键在new_column_prop_name中的序号
	var table_col_index = {} # 保存每个表的键在new_column_prop_name中的序号
	var table_alias_fields = {} # 临时变量：记录所有的t.xxx及其第一次出现时的序号（序号是columns中的序号）
	var uneditable_index = [] # 保存不能被编辑的列序号（假设值不是null）（序号是columns中的序号）
	
	# 联表查询不能修改主键和关联字段，找到这些字段
	if not single_table_query:
		for i in columns.size():
			if columns[i]["is_field"]:
				var ta = columns[i]["table_alias"] + "." + columns[i]["Column Name"]
				if not table_alias_fields.has(ta): # 重复的不记录是因为重复的本来就不可编辑
					table_alias_fields[ta] = i
				if columns[i]["PK"]:
					uneditable_index.push_back(i) # 不考虑用户select重复的主键了，不影响效果
					
		# 找到join_conds中的t.xxx
		var regex_field = RegEx.new()
		regex_field.compile("([a-zA-Z_]+[0-9a-zA-Z_]*\\.[a-zA-Z_]+[0-9a-zA-Z_]*)")
		for i in join_conds:
			var matches = regex_field.search_all(i)
			for a_match in matches:
				var s = a_match.get_string(0)
				if not s.is_empty() and table_alias_fields.has(s):
					uneditable_index.push_back(table_alias_fields[s]) # 就不去重了，不影响效果
					
	for j in columns.size():
		var table_path
		# 表中的字段
		if columns[j]["is_field"]:
			table_path = columns[j]["db_name"] + " " + columns[j]["table_name"].get_basename() # 实际上用的是数据库名称（而不是路径）+表名（去后缀）
			if not table_primary_index.has(columns[j]["db_path"].path_join(columns[j]["table_name"])): # 这里用的是数据库的路径+表名
				table_primary_index[columns[j]["db_path"].path_join(columns[j]["table_name"])] = -1
		else:
			table_path = "ComputingData"
			
		# 分组名称
		var prefix
		if table_path == last_table_path:
			prefix = last_prefix
		else:
			prefix = table_path
			if map_table_path_index.has(table_path):
				prefix += "@" + str(map_table_path_index[table_path])
				map_table_path_index[table_path] += 1
			else:
				map_table_path_index[table_path] = 2 # 可以使未来重复的分组名称后缀从2开始命名
			new_column_prop_name.push_back({"type": "group", "prop": prefix})
			hint[prefix] = {"hint_string": prefix + " ", "usage": PROPERTY_USAGE_GROUP} # 如此，检查器就可以省略属性的prefix
			
		last_table_path = table_path
		last_prefix = prefix
		
		# 属性名称
		var real_column_name = table_path + " " + columns[j]["Column Name"]
		if dealed_columns.has(real_column_name):
			var col_name = prefix + " " + columns[j]["Column Name"] + " (Copy" + str(dealed_columns[real_column_name]) + ")"
			new_column_prop_name.push_back({"type": j, "prop": col_name, "col_name": columns[j]["Column Name"],
				"table_path": columns[j]["db_path"].path_join(columns[j]["table_name"])}) # 记录j列数据的属性名称等信息
			hint[col_name] = {"link": real_col_name_name[real_column_name]}
			dealed_columns[real_column_name] += 1
		else:
			var col_name = prefix + " " + columns[j]["Column Name"]
			new_column_prop_name.push_back({"type": j, "prop": col_name, "col_name": columns[j]["Column Name"],
				"table_path": columns[j]["db_path"].path_join(columns[j]["table_name"])}) # 记录j列数据的属性名称等信息
			if columns[j]["is_field"]:
				hint[col_name] = {"hint": columns[j]["Hint"], 
					"hint_string": columns[j]["Hint String"], "type": columns[j]["Data Type"]}
				# 记录键位置信息
				table_col_index[col_name] = new_column_prop_name.size() - 1
				# 记录主键信息
				if columns[j]["PK"]:
					table_primary_index[columns[j]["db_path"].path_join(columns[j]["table_name"])] = table_col_index[col_name] # 主键位置
			else:
				hint[col_name] = {"usage": PROPERTY_USAGE_READ_ONLY | PROPERTY_USAGE_EDITOR}
			real_col_name_name[real_column_name] = col_name
			dealed_columns[real_column_name] = 2 # 可以使未来重复的变量名称后缀从2开始命名
#endregion
			
#region table UI
	var margin_container = MarginContainer.new()
	margin_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin_container.add_theme_constant_override("margin_top", 10)
	margin_container.add_theme_constant_override("margin_bottom", 10)
	
	var vbox = VBoxContainer.new()
	margin_container.add_child(vbox)
	
	var hsplit = HSplitContainer.new()
	hsplit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hsplit.add_theme_constant_override("autohide", 0)
	vbox.add_child(hsplit)
	
	var table: Control = load("res://addons/gdsql/table/table.tscn").instantiate()
	table.show_frame = true
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	table.size_flags_stretch_ratio = 0.1 * columns.size()
	hsplit.add_child(table)
	table.set_meta("columns", columns)
	table.column_tips = columns.map(func(v): 
		return type_string(v["Data Type"]) if v.has("Data Type") else "")
	table.columns = columns.map(func(v): return v["field_as"])
	
	var dummy = Control.new()
	dummy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hsplit.add_child(dummy)
	
	var flow_container = HFlowContainer.new()
	flow_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow_container.alignment = FlowContainer.ALIGNMENT_END
	
	var btn_export = Button.new()
	btn_export.text = tr("export")
	btn_export.pressed.connect(func():
		var _columns = table.get_meta("columns")
		mgr.open_select_data_export_tab.emit(_columns, table.datas.map(extract_table_data_call.bind(_columns)))
	)
	flow_container.add_child(btn_export)
	vbox.add_child(flow_container)
#endregion
	
	# 非unionall就可以编辑。
	table.editable = not is_union_all
	table.show_menu = true
	table.support_multi_rows_selected = true # 支持批量操作
	# 只有单表查询才支持右键删除。联表查询无法知道用户想删除哪个表的数据，即便能勾选要执行的命令，也容易误操作
	table.support_delete_row = single_table_query
	
	if not table.editable:
		table.datas = table_datas
		table.support_delete_row = false
	else:
		# 用于把修改数据按照表路径做归类
		# return：{
			#"res://src/config/c_skill.gsql": {
				#"PK_key": "id",
				#"PK_value_new": 7,
				#"PK_value_old": 6,
				#"modified": {
					#"id": {
						#"new": 7,
						#"old": 6
					#}
				#}
			#}
		#}
		var group_modified_data_call = func(data: GDSQL.DictionaryObject) -> Dictionary:
			var tables = {} # 更新数据可能涉及多个表，所以把modified_data按表分类
			var modified_data = data.get_modified_value()
			var all_data = data.get_visible_data()
			for prop in all_data:
				# Skip props which are not field, possible are ComputingData
				if not table_col_index.has(prop):
					continue
				var col_info = new_column_prop_name[table_col_index[prop]]
				var table_path = col_info["table_path"]
				if not tables.has(table_path):
					tables[table_path] = {}
					var primary_index = table_primary_index[table_path]
					var primary_key
					var primary_value_new
					var primary_value_old
					if primary_index != -1:
						var primary_info = new_column_prop_name[primary_index]
						primary_key = primary_info["col_name"]
						primary_value_new = data._get(primary_info["prop"])
						primary_value_old = primary_value_new \
							if not modified_data.has(primary_info["prop"]) \
							else modified_data[primary_info["prop"]]["old"]
					tables[table_path]["PK_key"] = primary_key
					tables[table_path]["PK_value_new"] = primary_value_new
					tables[table_path]["PK_value_old"] = primary_value_old
					tables[table_path]["modified"] = {}
					tables[table_path]["all"] = {}
				tables[table_path]["all"][col_info["col_name"]] = all_data[prop]
				if modified_data.has(prop):
					tables[table_path]["modified"][col_info["col_name"]] = modified_data[prop] # {"new":xx, "old":xx}
			return tables
			
		# 更新apply和revert两个按钮状态
		var btn_ref: Array[Button] = []
		btn_ref.resize(2)
		var update_btn_disable_status = func(_prop, _new_val, _old_val):
			if not table:
				EditorInterface.get_editor_toaster().push_toast(
					"Please re-select your data in the table.", EditorToaster.SEVERITY_WARNING)
				return
			# 如果有删除的行，btn_revert肯定需要激活，不用再检查表中的数据了
			if not table.get_meta("deleted_datas", {}).is_empty():
				return
				
			for j: GDSQL.DictionaryObject in table.datas:
				if not j.get_modified_new_value().is_empty():
					if btn_ref and btn_ref.size() == 2 and is_instance_valid(btn_ref[0]) and is_instance_valid(btn_ref[1]):
						btn_ref[0].disabled = false
						btn_ref[1].disabled = false
					return
			if btn_ref and btn_ref.size() == 2 and is_instance_valid(btn_ref[0]) and is_instance_valid(btn_ref[1]):
				btn_ref[0].disabled = true
				btn_ref[1].disabled = true
				
		# 加俩按钮:1.新建一条数据；2.应用
		var btn_apply = Button.new()
		btn_ref[0] = btn_apply
		btn_apply.text = tr("apply")
		btn_apply.disabled = true
		btn_apply.pressed.connect(func():
			var daos: Array[GDSQL.BaseDao] = []
			# 整条被删的数据。【WARNING】规定联表查询时禁止删除操作（屏蔽右键删除功能）
			var deleted_datas = table.get_meta("deleted_datas", {})
			for i in deleted_datas:
				var data: GDSQL.DictionaryObject = deleted_datas[i]
				var grouped_modified_data = group_modified_data_call.call(data)
				for table_path: String in grouped_modified_data:
					var base_dao = GDSQL.BaseDao.new()
					base_dao.use_db(table_path.get_base_dir()).delete_from(table_path.get_file())
					if grouped_modified_data[table_path]["PK_key"] == null:
						base_dao.set_meta("lackWhere", true)
					else:
						base_dao.where("%s == %s" % [grouped_modified_data[table_path]["PK_key"], 
							var_to_str(grouped_modified_data[table_path]["PK_value_old"])])
					base_dao.set_meta("dict_obj_id", data.get_instance_id())
					daos.push_back(base_dao)
					
			# 要更新部分字段的数据
			for i: GDSQL.DictionaryObject in table.datas:
				var grouped_modified_data = group_modified_data_call.call(i)
				for table_path: String in grouped_modified_data:
					var modified_data = grouped_modified_data[table_path]
					if modified_data["modified"].is_empty():
						continue
						
					var db_path = table_path.get_base_dir()
					var table_name = table_path.get_file()
					# 新增（用户在联表查询结果中new新数据时，在new的这行数据中对联表旧数据进行修改的可能性不大，所以逻辑中忽略这种奇怪的操作）
					var insert_call = func():
						# 把该表设置过的所有字段取出
						var values = {}
						for col_name in modified_data["modified"]:
							values[col_name] = modified_data["modified"][col_name]["new"]
						var base_dao = GDSQL.BaseDao.new()
						base_dao.use_db(db_path).insert_into(table_name).values(values)
						base_dao.set_meta("dict_obj_id", i.get_instance_id())
						daos.push_back(base_dao)
						
					if i.has_meta("new"):
						# 单表查询时，由用户自己负责
						if single_table_query:
							insert_call.call()
						# 联表查询时，修改数据若包含主键，那可以先检查一下（主键）是不是在数据库已经存在，如果存在就不需要新增了。
						# 实际上，联表查询时，用户输入了主键如果在数据库里存在，则提示用户有误。如果不存在，就算新增数据。
						# 新增数据如果没有包含主键呢？可能一：主键自增，用户可以不设置；可能二：需要用户填写主键但未填，那么query时会报错。
						else:
							var primary_key = modified_data["PK_key"]
							var primary_value = modified_data["PK_value_new"]
							if primary_key != null and modified_data["modified"].has(primary_key):
								if await exist_callable(db_path, table_name, primary_key, primary_value):
									continue
									
							insert_call.call()
					# 非新增，也就是更新（用户联表查询时，有产生新增数据的可能性，比如修改全为null值的表，所以要考虑这种情况）
					else:
						var primary_key = modified_data["PK_key"]
						var primary_value = modified_data["PK_value_old"]
						var update_call = func():
							var data = {}
							for key in modified_data["modified"]:
								data[key] = modified_data["modified"][key]["new"]
							var base_dao = GDSQL.BaseDao.new().use_db(db_path).update(table_name).sets(data)
							if primary_key == null:
								base_dao.set_meta("lackWhere", true)
							else:
								base_dao.where("%s == %s" % [primary_key, var_to_str(primary_value)])
							base_dao.set_meta("dict_obj_id", i.get_instance_id())
							daos.push_back(base_dao)
							
						# 单表查询时的所有情况
						if single_table_query:# or primary_key == null or not modified_data["modified"].has(primary_key):
							update_call.call()
						# 联表查询涉及主键修改的情况。只有一种被允许的情况，那就是该主键的旧值为null（实际上该主键所属表的其他字段都是null）。
						# 这样的话，用户修改该主键的值，只能是新建一条数据。
						# 其他情况涉及逻辑冲突，所以禁止用户在联表查询中进行修改主键和关联键的行为（通过hint的usage禁止）。
						# TODO 如果用户需要删除关联，考虑右键菜单加入删除关联。
						else:
							if primary_key == null or primary_value == null or modified_data["modified"].has(primary_key):
								insert_call.call()
							# 更新非主键字段、非关联键字段
							else:
								update_call.call()
						
			# 弹对话框让用户选择更新哪些数据
			var arr: Array[Array] = [["Please confirm:"]]
			var table_2 = load("res://addons/gdsql/table/table.tscn").instantiate()
			table_2.ratios = [15.0, 0.4, 2.0, 4.0, 8.0] as Array[float]
			table_2.columns = ["#", tr("Action"), tr("Extra info"), tr("Do"), tr("Status")]
			table_2.column_tips = ["", "", "If necessary.", "Only execute checked actions.", "Execute status."]
			var check_all_btn = CheckBox.new()
			check_all_btn.text = tr("Check all")
			check_all_btn.button_pressed = true
			check_all_btn.toggled.connect(func(toggled_on):
				for row in table_2.datas:
					if not (row[3] as CheckBox).disabled:
						(row[3] as CheckBox).button_pressed = toggled_on
			)
			var datas = []
			var k = 0
			for i: GDSQL.BaseDao in daos:
				var row = [k+1, i.get_query_cmd()]
				if i.has_meta("lackWhere"):
					var line_edit = LineEdit.new()
					line_edit.placeholder_text = "Conditions for this action if necessary."
					row.push_back(line_edit)
				else:
					row.push_back("")
					
				var cb = CheckBox.new()
				cb.button_pressed = true
				cb.set_meta("index", k)
				cb.toggled.connect(func(toggled_on):
					if toggled_on:
						for a_row in table_2.datas:
							if not (a_row[3] as CheckBox).disabled:
								if not (a_row[3] as CheckBox).button_pressed:
									check_all_btn.set_pressed_no_signal(false)
									return
						check_all_btn.set_pressed_no_signal(true)
					else:
						check_all_btn.set_pressed_no_signal(false)
				)
				row.push_back(cb)
				
				var pb = ProgressBar.new()
				row.push_back(pb)
				datas.push_back(row)
				k += 1
			table_2.datas = datas
			table_2.show_menu = true
			table_2.support_delete_row = false
			table_2.ready.connect(func():
				table_2.get_parent_control().size_flags_vertical = Control.SIZE_EXPAND_FILL
			, CONNECT_ONE_SHOT)
			arr.push_back([table_2])
			arr.push_back([check_all_btn])
			
			# 只执行用户勾选的项目。执行成功的项目标绿进度100%；执行失败的项目标红。
			# 可以多次执行，直到没有可勾选的项目。
			var dialog_ref: Array[ConfirmationDialog] = []
			var confirmed = func():
				# 该按钮名称是关闭，则直接关闭，否则执行命令
				if dialog_ref[0].ok_button_text == "close":
					# 更新按钮状态
					update_btn_disable_status.call("", 0, 0) # 随便传几个参数
					return [false, false] # 不涉及defered函数，所以第二个参数传的没什么意义
					
				# sql query
				var index = -1
				for i: GDSQL.BaseDao in daos:
					index += 1
					if not (table_2.datas[index][3] as CheckBox).button_pressed:
						continue
					if (table_2.datas[index][4] as ProgressBar).value == 100:
						continue
					var begin_time = Time.get_unix_time_from_system()
					var ret = i.query() # 修改的表都是前面已经请求过密码的，所以不需要再请求了
					if ret != null:
						if ret.ok():
							var dict_obj_id = i.get_meta("dict_obj_id")
							var dict_obj = instance_from_id(dict_obj_id) as GDSQL.DictionaryObject
							
							# remove deleted data
							if i.get_cmd().to_lower().contains("delete"):
								var key = table.get_meta("deleted_datas", {}).find_key(dict_obj)
								if key != null:
									table.get_meta("deleted_datas").erase(key)
									
							else:
								# commit data of modified row
								dict_obj.commit()
								
								# remove meta of new-created row
								if dict_obj.has_meta("new"):
									dict_obj.remove_meta("new")
								
							# log and UI
							mgr.add_log_history.emit("OK", begin_time, i.get_query_cmd(), 
								"%d row(s) affected" % ret.get_affected_rows(), ret.get_cost_time())
							(table_2.datas[index][4] as ProgressBar).value = 100
							(table_2.datas[index][4] as ProgressBar).modulate = Color.GREEN
							(table_2.datas[index][3] as CheckBox).button_pressed = false
							(table_2.datas[index][3] as CheckBox).disabled = true
						else:
							mgr.add_log_history.emit("Err", begin_time, i.get_query_cmd(), 
								ret.get_err(), ret.get_cost_time())
							(table_2.datas[index][4] as ProgressBar).modulate = Color.RED
					else:
						mgr.add_log_history.emit("Err", begin_time, i.get_query_cmd(), "something wrong")
						(table_2.datas[index][4] as ProgressBar).modulate = Color.RED
						
				var can_execute = false
				for row in table_2.datas:
					if not (row[3] as CheckBox).disabled:
						can_execute = true
						break
						
				# 不能再执行时，把按钮名称改为“关闭”，这样下次用户点击该按钮时，对话框就可以关闭了
				if not can_execute:
					dialog_ref[0].ok_button_text = "close"
					
				# true：让该页面不关闭
				return [true, false] # 不涉及defered函数，所以第二个参数传的没什么意义
				
			# 对话框关闭时要执行的方法
			var defered = func(_confirmed, _dummy):
				update_btn_disable_status.call("", 0, 0) # 刷新按钮状态。参数随便传。
				table_2.queue_free()
				check_all_btn.queue_free()
				
			var dialog = mgr.create_custom_dialog(arr, confirmed, Callable(), defered, 0.5)
			dialog_ref.push_back(dialog)
			dialog.ok_button_text = "execute"
			var btn_close_refresh = dialog.add_button("close and refresh", true, "close_and_refresh")
			btn_close_refresh.tooltip_text = tr("Refresh the table. Actions that not have been executed will be discarded.")
			if btn_close_refresh.disabled:
				btn_close_refresh.tooltip_text += "\n" + tr("[Tip]This button is disabled because this Result-node is not connected to a Select-node or the Select-node is not enabled.")
			dialog.custom_action.connect(func(action):
				if action == "close_and_refresh":
					update_btn_disable_status.call("", 0, 0)
					var onclose = func ():
						table.remove_meta("deleted_datas")
						# TODO 再次执行
						#for node in get_from_nodes(graph_node, "Select"):
							#await on_select_node_query(node, true)
						mgr._clear_custom_dialog(dialog)
						
					if btn_apply.disabled:
						onclose.call()
					else:
						mgr.create_confirmation_dialog(split_for_long_content(tr(
							"You have unsaved changes. Refreshing will discard all current edits. Are you sure you want to refresh the table?"
						)), onclose)
			)
		)
		
		var btn_revert = Button.new()
		btn_ref[1] = btn_revert
		btn_revert.text = tr("revert")
		btn_revert.disabled = true
		btn_revert.pressed.connect(func():
			var old_datas: Array = []
			# 恢复被修改的数据
			for i: GDSQL.DictionaryObject in table.datas:
				if not i.has_meta("new"):
					i.revert()
					old_datas.push_back(i)
			# 恢复被删除的数据
			var deleted_datas = table.get_meta("deleted_datas", {})
			table.remove_meta("deleted_datas")
			for i in deleted_datas:
				#old_datas.insert(i, deleted_datas[i]) # 注意：前提是新建的数据都是放在最后面的，不影响数据回到原来的位置。
				(deleted_datas[i] as GDSQL.DictionaryObject).revert()
				table.insert_data(i, deleted_datas[i]) # 注意：前提是新建的数据都是放在最后面的，不影响数据回到原来的位置。
			#table.datas = old_datas
			# 删除新建的数据
			for i in range(table.datas.size()-1, -1, -1):
				if table.datas[i].has_meta("new"):
					table.remove_data_at(i, true)
			btn_apply.disabled = true
			btn_revert.disabled = true
		)
		
		table.row_deleted.connect(func(datas):
			var deleted_datas = table.get_meta("deleted_datas", {}) as Dictionary
			
			# 找到最小行号
			var min_index = 9999999999
			for i in datas:
				min_index = min(datas[i].get_meta("index"), min_index)
				
			# 最小行号前面有几个被删除了
			var offset = 0
			for i in deleted_datas:
				if deleted_datas[i].get_meta("index") < min_index:
					offset += 1
					
			for i in datas:
				var data = datas[i]
				if data.has_meta("new"):
					return
				deleted_datas[i + offset] = data
				
			# 提取字典的键到数组中
			var keys = deleted_datas.keys()
			keys.sort()
			var sorted_dict = {}
			for key in keys:
				sorted_dict[key] = deleted_datas[key]
				
			# 排序后存入
			table.set_meta("deleted_datas", sorted_dict)
			btn_apply.disabled = false
			btn_revert.disabled = false
		)
		
		var btn_new = Button.new()
		btn_new.text = tr("New Row")
		btn_new.tooltip_text = tr("Press 'Ctrl' to add 10 new row.")
		btn_new.pressed.connect(func():
			var num = 1
			if Input.is_key_pressed(KEY_CTRL):
				num = 10
			for i in num:
				# 构造一个默认新数据
				var new_data = {}
				for j in new_column_prop_name:
					if j["type"] is String and j["type"] == "group":
						new_data[j["prop"]] = "" # for group
					else:
						var col_def = columns.filter(func(v):
							return v["Column Name"] == j["col_name"]
						).front()
						if (col_def["Default(Expression)"] as String).strip_edges().is_empty():
							new_data[j["prop"]] = GDSQL.DataTypeDef.DEFUALT_VALUES[col_def["Data Type"]]
						else:
							new_data[j["prop"]] = GDSQL.GDSQLUtils.evaluate_command(null, col_def["Default(Expression)"])
							
							
				var dict_obj = GDSQL.DictionaryObject.new(new_data, hint, false)
				dict_obj.set_meta("new", true)
				if table.datas.is_empty():
					dict_obj.set_meta("index", 0)
				else:
					dict_obj.set_meta("index", table.datas.back().get_meta("index") + 1)
				dict_obj._get_property_list() # NOTICE trigger ENUM text possibly
				dict_obj.value_changed.connect(update_btn_disable_status)
				table.append_data(dict_obj)
				table.row_grab_focus(table.datas.size() - 1)
		)
		
		flow_container.add_child(btn_new)
		flow_container.add_child(btn_apply)
		flow_container.add_child(btn_revert)
		flow_container.get_child(0).move_to_front() # move export button to last
		
		# 每行数据转成一个GDSQL.DictionaryObject
		var new_table_datas = []
		for i in table_datas:
			var data = {}
			var new_hint = hint
			for j in new_column_prop_name:
				if j["type"] is String and j["type"] == "group":
					data[j["prop"]] = "" # for group
				else:
					data[j["prop"]] = i[j["type"]]
					# 联表时，主键和关联键禁止修改，除键值为null。而且就算修改，也不能使用已存在的键值（null说明原本就跟已存在的键值没关联）
					if i[j["type"]] != null and uneditable_index.has(j["type"]):
						if new_hint == hint:
							new_hint = hint.duplicate(true)
						new_hint[j["prop"]]["usage"] = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY
						# TODO 不能使用已存在的键值
						
			var dict_obj = GDSQL.DictionaryObject.new(data, new_hint, false)
			dict_obj.value_changed.connect(update_btn_disable_status)
			dict_obj.set_meta("index", new_table_datas.size()) # 为了revert删除的数据时判断前后位置
			dict_obj._get_property_list() # NOTICE trigger ENUM text possibly
			new_table_datas.push_back(dict_obj)
		table.datas = new_table_datas
		table.support_delete_row = true
		
	return margin_container
	
func extract_table_data_call(v, columns):
	if v is GDSQL.DictionaryObject:
		var arr = []
		for i in columns.size():
			arr.push_back(v._get_by_index(i))
		return arr
	return v
	
## 检查是否存在某主键
func exist_callable(db_path, table_name, field_name, field_value) -> bool:
	var dao = GDSQL.BaseDao.new().use_db(db_path).select(field_name, false).from(table_name)\
		.where("%s == %s" % [field_name, var_to_str(field_value)])
	var ret = await _deal_query_need_enter_password(dao, Time.get_unix_time_from_system(), "check primary key exist")
	if ret == null or not ret.ok():
		push_warning("Something weired. Check this.")
		return true # 报错了，不知道具体啥情况，视为true
	# 数据库有该条数据
	if not ret.get_data().is_empty():
		return true
	return false
	
func split_for_long_content(content: String) -> String:
	const l = 70
	var total_l = content.length()
	if total_l <= l:
		return content
	var arr = []
	var start = 0
	while true:
		arr.push_back(content.substr(start, l))
		if start + l >= total_l:
			break
		start += l
	return "\n".join(arr)
