@tool
extends CodeEdit

@export var button_run_edit: Button

var in_run_edit = false
var in_run_edit_shortcut_feedback = false

# 自定义补全面板（非弹窗，不会抢焦点）
var _completion_panel: PanelContainer
var _completion_list: ItemList
var _completion_matches: Array[Dictionary] = []
var _completion_word_start: int = 0
var _completion_word_end: int = 0
var _completion_inserting: bool = false
var _completion_dot_mode: bool = false
var _completion_selected_idx: int = 0

# 补全图标
var _icon_db: Texture2D
var _icon_table: Texture2D
var _icon_column: Texture2D
var _icon_keyword: Texture2D

const SQL_KEYWORDS: Array[String] = [
	"select", "insert", "update", "delete", "replace",
	"from", "where", "set", "into", "values",
	"join", "left", "right", "inner", "outer", "cross", "on",
	"group", "by", "order", "having", "limit", "offset",
	"union", "all", "distinct", "as", "between", "in", "like",
	"exists", "case", "when", "then", "else", "end",
	"create", "drop", "alter", "table", "database", "index",
	"primary", "foreign", "references", "unique", "default",
	"autoincrement", "not", "null", "if", "cascade", "restrict",
	"add", "column", "rename", "to", "ignore", "duplicate", "key",
	"begin", "commit", "rollback", "transaction", "savepoint",
	"and", "or", "not", "is", "asc", "desc",
	"count", "sum", "avg", "min", "max", "abs", "round",
	"ceil", "floor", "length", "trim", "upper", "lower",
	"substr", "coalesce", "ifnull", "nullif", "cast", "typeof",
	"int", "integer", "float", "real", "double", "decimal",
	"varchar", "char", "text", "blob", "boolean", "bool",
	"date", "datetime", "timestamp",
	"true", "false",
]

var mgr: GDSQL.WorkbenchManagerClass:
	get: return GDSQL.WorkbenchManager

func _ready() -> void:
	syntax_highlighter = _create_sql_highlighter()

	# 加载补全图标
	_icon_db = load("res://addons/gdsql/img/icon_db.svg")
	_icon_table = load("res://addons/gdsql/img/document_table.svg")
	_icon_column = load("res://addons/gdsql/img/circle_dot.svg")
	_icon_keyword = get_theme_icon("Keyword", "EditorIcons") if has_theme_icon("Keyword", "EditorIcons") else load("res://addons/gdsql/img/link.svg")

	# 创建补全面板（非弹窗，不抢焦点）
	_completion_panel = PanelContainer.new()
	_completion_panel.visible = false
	_completion_panel.z_index = 100
	_completion_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_completion_panel)

	_completion_list = ItemList.new()
	_completion_list.max_columns = 1
	_completion_list.fixed_column_width = 0
	_completion_list.same_column_width = true
	_completion_list.focus_mode = Control.FOCUS_NONE
	_completion_list.mouse_filter = Control.MOUSE_FILTER_PASS
	_completion_list.custom_minimum_size = Vector2(280, 0)
	_completion_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_completion_panel.add_child(_completion_list)
	_completion_list.item_selected.connect(_on_completion_selected)
	_completion_panel.custom_minimum_size = Vector2(280, 0)

	text_changed.connect(_on_text_changed)


## 创建 SQL 语法高亮器
func _create_sql_highlighter() -> CodeHighlighter:
	var h = CodeHighlighter.new()

	# 从编辑器主题获取颜色（带默认回退值）
	var es = EditorInterface.get_editor_settings()
	var keyword_color: Color = es.get_setting("text_editor/theme/highlighting/keyword_color")
	var comment_color: Color = es.get_setting("text_editor/theme/highlighting/comment_color")
	var string_color: Color = es.get_setting("text_editor/theme/highlighting/string_color")
	var number_color: Color = es.get_setting("text_editor/theme/highlighting/number_color")
	var symbol_color: Color = es.get_setting("text_editor/theme/highlighting/symbol_color")
	var function_color: Color = es.get_setting("text_editor/theme/highlighting/function_color")
	var type_color: Color = es.get_setting("text_editor/theme/highlighting/engine_type_color")
	var constant_color: Color = es.get_setting("text_editor/theme/highlighting/comment_color")
	var text_color: Color = es.get_setting("text_editor/theme/highlighting/text_color")

	h.number_color = number_color
	h.symbol_color = symbol_color
	h.function_color = function_color
	h.member_variable_color = text_color

	# 注释区域
	h.add_color_region("--", "", comment_color, true)
	h.add_color_region("#", "", comment_color, true)
	h.add_color_region("/*", "*/", comment_color, false)

	# 字符串（单引号）
	h.add_color_region("'", "'", string_color, false)

	# DML 关键字
	var dml_keywords = [
		"select", "insert", "update", "delete", "replace",
		"from", "where", "set", "into", "values",
		"join", "left", "right", "inner", "outer", "cross", "on",
		"group", "by", "order", "having", "limit", "offset",
		"union", "all", "distinct", "as", "between", "in", "like",
		"exists", "case", "when", "then", "else", "end",
		"ignore", "duplicate", "key",
	]
	for kw in dml_keywords:
		h.add_keyword_color(kw, keyword_color)

	# DDL / 结构关键字
	var ddl_keywords = [
		"create", "drop", "alter", "table", "database", "index",
		"primary", "foreign", "references", "unique", "default",
		"autoincrement", "not", "null", "if", "cascade", "restrict",
		"add", "column", "rename", "to",
	]
	for kw in ddl_keywords:
		h.add_keyword_color(kw, keyword_color)

	# 事务关键字
	var txn_keywords = [
		"begin", "commit", "rollback", "transaction", "savepoint",
	]
	for kw in txn_keywords:
		h.add_keyword_color(kw, keyword_color)

	# 数据类型
	var data_types = [
		"int", "integer", "float", "real", "double", "decimal",
		"varchar", "char", "text", "blob", "boolean", "bool",
		"date", "datetime", "timestamp",
	]
	for kw in data_types:
		h.add_keyword_color(kw, type_color)

	# 内置函数
	var functions = [
		"count", "sum", "avg", "min", "max",
		"abs", "round", "ceil", "floor",
		"length", "trim", "upper", "lower", "substr", "replace",
		"coalesce", "ifnull", "nullif",
		"cast", "typeof", "list",
	]
	for kw in functions:
		h.add_keyword_color(kw, function_color)

	# 常量
	var constants = ["true", "false", "null"]
	for kw in constants:
		h.add_keyword_color(kw, constant_color)

	# 逻辑运算符
	var operators = ["and", "or", "not", "is", "asc", "desc"]
	for kw in operators:
		h.add_keyword_color(kw, keyword_color)

	return h


# ==================== 代码补全 ====================

func _on_text_changed() -> void:
	if _completion_inserting:
		return
	_update_completion()


func _update_completion() -> void:
	if _is_cursor_in_string_or_comment():
		_hide_popup()
		return

	var line_idx = get_caret_line(0)
	var caret_col = get_caret_column(0)
	var before: String = get_line(line_idx).substr(0, caret_col)
	var word = _get_word_before_cursor(before)

	var matches: Array[Dictionary] = []
	_completion_dot_mode = false

	# 检查 "xxx." 模式（数据库名、表名、或别名后跟点号）
	var stripped = before.strip_edges()
	var dot_pos = stripped.rfind(".")
	if dot_pos >= 0:
		var after_dot = stripped.substr(dot_pos + 1)
		var before_dot = stripped.substr(0, dot_pos)
		if before.length() == stripped.length() and (after_dot.is_empty() or after_dot == word):
			var prefix = before_dot.get_slice(" ", before_dot.get_slice_count(" ") - 1).strip_edges()
			if prefix != "":
				# 用全文提取别名，支持光标在行中间时也能解析后面的 FROM 子句
				var aliases = _extract_table_aliases(text)
				var resolved = aliases.get(prefix.to_lower(), prefix)
				matches = _get_dot_completions(resolved, word)
				_completion_dot_mode = true

	# 通用候选词
	if matches.is_empty() and not _completion_dot_mode:
		if word.length() < 2:
			_hide_popup()
			return

		var all_candidates: Array[Dictionary] = []
		for kw in SQL_KEYWORDS:
			all_candidates.push_back({"text": kw, "display": kw, "type": "keyword"})
		if mgr and mgr.databases:
			for db_name in mgr.databases:
				var db_display = mgr.databases[db_name].get("display_name", db_name)
				if db_display == "" or db_display == db_name:
					db_display = db_name
				all_candidates.push_back({"text": db_name, "display": db_display, "type": "database"})
			for db_name in mgr.databases:
				for table_name in mgr.databases[db_name].get("tables", {}):
					var tbl_display = mgr.databases[db_name]["tables"][table_name].get("display_name", table_name)
					if tbl_display == "":
						tbl_display = table_name
					all_candidates.push_back({"text": table_name, "display": tbl_display, "type": "table"})
			# 字段名推荐：有引用表时缩小范围，否则列出所有表的字段
			var referenced_tables = _extract_referenced_tables(before)
			var column_added: Dictionary = {}  # 去重
			if referenced_tables.size() > 0:
				# 仅从已引用表中取字段
				for t_name in referenced_tables:
					for db_name in mgr.databases:
						var tables = mgr.databases[db_name].get("tables", {})
						var matched_table = _find_key_ci(tables, t_name)
						if matched_table != "":
							for column in tables[matched_table].get("columns", []):
								var col_name = column["Column Name"]
								if not column_added.has(col_name):
									column_added[col_name] = true
									all_candidates.push_back({"text": col_name, "display": col_name, "type": "column"})
			else:
				# 未引用任何表，列出所有表的所有字段
				for db_name in mgr.databases:
					for table_name in mgr.databases[db_name].get("tables", {}):
						for column in mgr.databases[db_name]["tables"][table_name].get("columns", []):
							var col_name = column["Column Name"]
							if not column_added.has(col_name):
								column_added[col_name] = true
								all_candidates.push_back({"text": col_name, "display": col_name, "type": "column"})
		matches = _filter_and_sort(all_candidates, word)

	if matches.is_empty():
		_hide_popup()
		return

	# 记录当前词的起止位置
	_completion_word_end = caret_col
	_completion_word_start = caret_col - word.length()
	_completion_matches = matches
	_show_popup()


func _show_popup() -> void:
	_completion_list.clear()
	for i in range(_completion_matches.size()):
		var m = _completion_matches[i]
		var display_text = m.get("display", m["text"])
		var icon: Texture2D = null
		match m["type"]:
			"keyword": icon = _icon_keyword
			"database": icon = _icon_db
			"table": icon = _icon_table
			"column": icon = _icon_column
		_completion_list.add_item(display_text, icon)

	_completion_selected_idx = 0
	if _completion_list.item_count > 0:
		_completion_list.select(0)

	# 定位到光标下方
	var caret_draw_pos = get_caret_draw_pos(0)
	# 用主题字体的实际像素高度和间距计算行高
	# 遍历候选词累加实际像素高度
	var font = _completion_list.get_theme_font("font")
	var font_size = _completion_list.get_theme_font_size("font_size")
	var v_sep = _completion_list.get_theme_constant("v_separation")
	var list_sb = _completion_list.get_theme_stylebox("panel")
	var total_h = 0.0
	var max_width = 280
	if font:
		for i in _completion_list.item_count:
			var string_size = font.get_string_size(_completion_list.get_item_text(i), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			total_h += string_size.y
			max_width = max(max_width, string_size.x)
	else:
		total_h = _completion_list.item_count * 32.0
	total_h += list_sb.get_margin(SIDE_TOP) + list_sb.get_margin(SIDE_BOTTOM) + v_sep * (_completion_list.item_count - 1)
	max_width += list_sb.get_margin(SIDE_LEFT) + list_sb.get_margin(SIDE_RIGHT)
	var list_h = clampi(int(total_h), 32, 300)
	# 读取面板 stylebox 边距
	var panel_sb = _completion_panel.get_theme_stylebox("panel")
	if panel_sb:
		list_h += int(panel_sb.get_margin(SIDE_TOP) + panel_sb.get_margin(SIDE_BOTTOM))
		max_width += panel_sb.get_margin(SIDE_LEFT) + list_sb.get_margin(SIDE_RIGHT)
	max_width += max(_icon_db.get_width(), _icon_table.get_width(), _icon_column.get_width(), _icon_keyword.get_width())
	_completion_list.custom_minimum_size = Vector2(max_width, list_h)
	_completion_list.size.y = list_h
	_completion_panel.custom_minimum_size = Vector2(280, list_h)
	_completion_panel.size = Vector2(max_width, list_h)
	_completion_panel.position = Vector2(caret_draw_pos.x, caret_draw_pos.y + 4)
	_completion_panel.visible = true

func _hide_popup() -> void:
	_completion_panel.visible = false
	_completion_list.clear()
	_completion_matches.clear()
	_completion_dot_mode = false


func _on_completion_selected(index: int) -> void:
	if index < 0 or index >= _completion_matches.size():
		return
	var candidate = _completion_matches[index]
	var s_insert_text: String = candidate.get("display", candidate["text"])
	_completion_inserting = true
	var line_idx = get_caret_line(0)
	var line_text = get_line(line_idx)
	var new_line = line_text.substr(0, _completion_word_start) + s_insert_text + line_text.substr(_completion_word_end)
	set_line(line_idx, new_line)
	set_caret_column(_completion_word_start + s_insert_text.length())
	_completion_inserting = false
	_hide_popup()


## 尝试生成表名/列名补全候选（xxx. 之后）。成功返回候选列表。
## 大小写不敏感查找字典键，返回匹配的实际键名，未找到返回空字符串
func _find_key_ci(dict: Dictionary, key: String) -> String:
	if dict.has(key):
		return key
	var key_lower = key.to_lower()
	for k in dict:
		if (k as String).to_lower() == key_lower:
			return k
	return ""


func _get_dot_completions(db_prefix: String, word_filter: String) -> Array[Dictionary]:
	if not (mgr and mgr.databases):
		return []
	var databases = mgr.databases

	# 大小写不敏感匹配数据库名
	var matched_db = _find_key_ci(databases, db_prefix)
	if matched_db != "":
		var tables: Dictionary = databases[matched_db].get("tables", {})
		var candidates: Array[Dictionary] = []
		for t_name in tables:
			var tbl_display = tables[t_name].get("display_name", t_name)
			if tbl_display == "":
				tbl_display = t_name
			candidates.push_back({"text": t_name, "display": tbl_display, "type": "table"})
		return _filter_and_sort(candidates, word_filter) if word_filter != "" else candidates

	# 大小写不敏感匹配表名，补全列名
	for db_name in databases:
		var tables: Dictionary = databases[db_name].get("tables", {})
		var matched_table = _find_key_ci(tables, db_prefix)
		if matched_table != "":
			var cols = tables[matched_table].get("columns", [])
			var candidates: Array[Dictionary] = []
			for column in cols:
				candidates.push_back({"text": column["Column Name"], "display": column["Column Name"], "type": "column"})
			return _filter_and_sort(candidates, word_filter) if word_filter != "" else candidates

	return []


## 从SQL文本中提取 FROM / JOIN 后面的表名及别名映射
## 返回 {alias_lower: table_name}，无别名时 {table_name_lower: table_name}
func _extract_table_aliases(sql_text: String) -> Dictionary:
	var aliases: Dictionary = {}
	var re = RegEx.new()
	re.compile(r"(?i)(?:from|join)\s+([a-zA-Z_][a-zA-Z0-9_]*)(?:\.([a-zA-Z_][a-zA-Z0-9_]*))?(?:\s+(?:as\s+)?([a-zA-Z_][a-zA-Z0-9_]*))?")
	for m in re.search_all(sql_text):
		var db_or_table = m.get_string(1)
		var table = m.get_string(2) if m.get_group_count() >= 2 and m.get_string(2) != "" else ""
		var alias = m.get_string(3) if m.get_group_count() >= 3 and m.get_string(3) != "" else ""
		var actual_table = table if table != "" else db_or_table
		if alias != "" and alias.to_lower() not in ["where", "on", "set", "left", "right", "inner", "outer", "cross", "join", "group", "order", "having", "limit", "union", "values"]:
			aliases[alias.to_lower()] = actual_table
		else:
			aliases[actual_table.to_lower()] = actual_table
	return aliases


## 从SQL文本中提取 FROM / JOIN 后面引用的表名（兼容别名）
func _extract_referenced_tables(sql_text: String) -> Array[String]:
	var alias_map = _extract_table_aliases(sql_text)
	var tables: Array[String] = []
	for v in alias_map.values():
		if not tables.has(v):
			tables.push_back(v)
	return tables


## 获取光标前的单词（标识符）
func _get_word_before_cursor(before: String) -> String:
	var i = before.length() - 1
	while i >= 0:
		var ch = before[i]
		if ch.is_valid_int() or ch.to_lower() != ch.to_upper() or ch == "_":
			i -= 1
		else:
			break
	return before.substr(i + 1)


## 模糊匹配过滤并排序候选词
func _filter_and_sort(candidates: Array[Dictionary], prefix: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var prefix_lower = prefix.to_lower()
	for c in candidates:
		var score = _fuzzy_match_score(c["text"], prefix_lower)
		var display = c.get("display", c["text"])
		if display != c["text"]:
			var display_score = _fuzzy_match_score(display, prefix_lower)
			score = maxi(score, display_score)
		if score > 0:
			var entry = c.duplicate()
			entry["score"] = score
			result.push_back(entry)
	result.sort_custom(func(a, b):
		if a["score"] != b["score"]:
			return a["score"] > b["score"]
		return a.get("display", a["text"]).to_lower() < b.get("display", b["text"]).to_lower()
	)
	return result


## 计算模糊匹配得分，0 表示不匹配
func _fuzzy_match_score(candidate: String, prefix_lower: String) -> int:
	var lower = candidate.to_lower()

	# 完全匹配
	if lower == prefix_lower:
		return 1000

	# 前缀匹配
	if lower.begins_with(prefix_lower):
		return 500 + (100 - candidate.length())

	# 子序列匹配（如 "slt" 匹配 "select"）
	var pi = 0
	for ci in range(lower.length()):
		if pi < prefix_lower.length() and lower[ci] == prefix_lower[pi]:
			pi += 1
	if pi >= prefix_lower.length():
		return 100 + int(_similarity_ratio(lower, prefix_lower) * 50)

	# 包含匹配
	if lower.contains(prefix_lower):
		return 200

	return 0


## 计算两个字符串的相似度 (0.0 ~ 1.0)
func _similarity_ratio(a: String, b: String) -> float:
	if a.is_empty() and b.is_empty():
		return 1.0
	var max_len = maxi(a.length(), b.length())
	if max_len == 0:
		return 1.0
	var matches = 0
	var min_len = mini(a.length(), b.length())
	for i in range(min_len):
		if a[i] == b[i]:
			matches += 1
	return float(matches) / float(max_len)


## 检测光标是否在字符串或注释内
func _is_cursor_in_string_or_comment() -> bool:
	var line_text = get_line(get_caret_line(0))
	var col = get_caret_column(0)
	var in_sq = false
	var in_dq = false
	var in_block_comment = false
	var i = 0
	while i < col and i < line_text.length():
		var ch = line_text[i]
		if in_block_comment:
			if ch == "*" and i + 1 < line_text.length() and line_text[i + 1] == "/":
				in_block_comment = false
				i += 1
		elif in_sq:
			if ch == "'":
				in_sq = false
		elif in_dq:
			if ch == '"':
				in_dq = false
		else:
			if ch == "-" and i + 1 < line_text.length() and line_text[i + 1] == "-":
				return true
			if ch == "#":
				return true
			if ch == "/" and i + 1 < line_text.length() and line_text[i + 1] == "*":
				in_block_comment = true
				i += 1
			elif ch == "'":
				in_sq = true
			elif ch == '"':
				in_dq = true
		i += 1
	return in_sq or in_dq or in_block_comment


## 获取补全项的颜色
func _get_completion_color(type: String) -> Color:
	var es = EditorInterface.get_editor_settings()
	match type:
		"keyword":
			return es.get_setting("text_editor/theme/highlighting/keyword_color")
		"database":
			return es.get_setting("text_editor/theme/highlighting/engine_type_color")
		"table":
			return es.get_setting("text_editor/theme/highlighting/function_color")
		"column":
			return es.get_setting("text_editor/theme/highlighting/text_color")
	return Color.WHITE

func _can_drop_data(_position, data):
	# { "type": "files", "files": ["res://src/dao/t_hero.gdmappergraph"], "from": @Tree@6840:<Tree#603409380691> }
	if data is Dictionary:
		if data.has("type") and data.has("files") and data.get("type") == "files":
			for i in data.get("files"):
				if i is String:
					if i.ends_with(".gdsqltext") or i.ends_with(".gdsqlgraph") or i.ends_with(".gdmappergraph"):
						return true
	return false
	
func _drop_data(_position, data):
	for i in data.get("files"):
		if i is String:
			if i.ends_with(".gdsqltext"):
				GDSQL.WorkbenchManager.open_sql_text_file_tab.emit(i)
			elif i.ends_with(".gdsqlgraph"):
				GDSQL.WorkbenchManager.open_sql_graph_file_tab.emit(i)
			elif i.ends_with(".gdmappergraph"):
				GDSQL.WorkbenchManager.open_mapper_graph_file_tab.emit(i)
				
func _gui_input(event: InputEvent) -> void:
	# 补全弹窗键盘导航
	if _completion_panel.visible and event is InputEventKey and event.is_pressed():
		var count = _completion_list.item_count
		match event.keycode:
			KEY_UP:
				if _completion_selected_idx > 0:
					_completion_selected_idx -= 1
				else:
					_completion_selected_idx = count - 1
				_completion_list.select(_completion_selected_idx)
				_completion_list.ensure_current_is_visible()
				accept_event()
				return
			KEY_DOWN:
				if _completion_selected_idx < count - 1:
					_completion_selected_idx += 1
				else:
					_completion_selected_idx = 0
				_completion_list.select(_completion_selected_idx)
				_completion_list.ensure_current_is_visible()
				accept_event()
				return
			KEY_TAB, KEY_ENTER, KEY_KP_ENTER:
				_on_completion_selected(_completion_selected_idx)
				accept_event()
				return
			KEY_ESCAPE:
				_hide_popup()
				accept_event()
				return

	# 点击补全面板外部时关闭
	if _completion_panel.visible and event is InputEventMouseButton and event.is_pressed():
		var mouse_pos = get_global_mouse_position()
		var panel_rect = Rect2(_completion_panel.global_position, _completion_panel.size)
		if not panel_rect.has_point(mouse_pos):
			_hide_popup()

	if in_run_edit_shortcut_feedback:
		if event is InputEventKey:
			accept_event()
		return
	if button_run_edit.shortcut.matches_event(event):
		in_run_edit = true
		if event.is_released():
			in_run_edit = false
			_button_run_edit_pressed()
		accept_event()
		return
	elif in_run_edit:
		in_run_edit = false
		_button_run_edit_pressed()
		accept_event()
		return
		
func _button_run_edit_pressed():
	button_run_edit.pressed.emit()
	var normal_sb = button_run_edit.get_theme_stylebox("normal")
	var hover_pressed_sb = button_run_edit.get_theme_stylebox("hover_pressed")
	button_run_edit.add_theme_stylebox_override("normal", hover_pressed_sb)
	in_run_edit_shortcut_feedback = true
	await get_tree().create_timer(ProjectSettings.get_setting("gui/timers/button_shortcut_feedback_highlight_time", 0.2)).timeout
	in_run_edit_shortcut_feedback = false
	if button_run_edit:
		button_run_edit.add_theme_stylebox_override("normal", normal_sb)
