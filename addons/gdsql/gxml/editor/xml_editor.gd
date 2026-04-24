@tool
extends VBoxContainer

@onready var text_editor: CodeEdit = $TextEditor
@onready var status_bar: HBoxContainer = $ScrollContainer/StatusBar
@onready var toggle_scripts_button: Button = $ScrollContainer/StatusBar/ToggleScriptsButton
@onready var error_button: Button = $ScrollContainer/StatusBar/ErrorButton
@onready var warning_button: Button = $ScrollContainer/StatusBar/WarningButton
@onready var zoom_button: MenuButton = $ScrollContainer/StatusBar/ZoomButton
@onready var line_and_col_txt: Label = $ScrollContainer/StatusBar/LineAndColTxt
@onready var indentation_txt: Label = $ScrollContainer/StatusBar/IndentationTxt
@onready var error: Label = $ScrollContainer/StatusBar/Scroll/Error
@onready var idle: Timer = $Idle
@onready var code_complete_timer: Timer = $CodeCompleteTimer

signal text_changed
signal validate_script
signal show_errors_panel
signal show_warnings_panel
signal zoomed(p_zoom_factor: float)

signal toggle_scripts_pressed

var scripts_panel_toggled = false
## 由外部设置
var find_replace_bar: Node
var content: String
var EDSCALE: float = EditorInterface.get_editor_scale()
var error_line = 0
var error_column = 0
var is_warnings_panel_opened = false
var is_errors_panel_opened = false
var zoom_factor = 1.0
var code_complete_timer_line = 0
var code_complete_enabled = true
var completion_font_color
var completion_string_color
var completion_string_name_color
var completion_node_path_color
var completion_comment_color
var completion_doc_comment_color

const ZOOM_FACTOR_PRESETS = [0.5, 0.75, 0.9, 1.0, 1.1, 1.25, 1.5, 2.0]

const SHORTCUT_FINDNEXT = preload("res://addons/gdsql/gxml/editor/shortcut/shortcut_findnext.tres")
const SHORTCUT_FINDPREVIOUS = preload("res://addons/gdsql/gxml/editor/shortcut/shortcut_findprevious.tres")
const SHORTCUT_MOVEDOWN = preload("res://addons/gdsql/gxml/editor/shortcut/shortcut_movedown.tres")
const SHORTCUT_MOVEUP = preload("res://addons/gdsql/gxml/editor/shortcut/shortcut_moveup.tres")
const SHORTCUT_DELETELINE = preload("res://addons/gdsql/gxml/editor/shortcut/shortcut_deleteline.tres")
const SHORTCUT_DUPLICATESELECTION = preload("res://addons/gdsql/gxml/editor/shortcut/shortcut_duplicateselection.tres")
const SHORTCUT_DUPLICATELINE = preload("res://addons/gdsql/gxml/editor/shortcut/shortcut_duplicateline.tres")

func goto_line(p_line: int, p_column: int):
	text_editor.remove_secondary_carets()
	text_editor.deselect()
	text_editor.unfold_line(clamp(p_line, 0, text_editor.get_line_count() - 1))
	text_editor.set_caret_line(p_line, false)
	text_editor.set_caret_column(p_column, false)
	text_editor.set_code_hint("")
	text_editor.cancel_code_completion()
	text_editor.center_viewport_to_caret()
	
func goto_line_selection(p_line: int, p_begin: int, p_end: int):
	text_editor.remove_secondary_carets()
	text_editor.unfold_line(clamp(p_line, 0, text_editor.get_line_count() - 1))
	text_editor.select(p_line, p_begin, p_line, p_end)
	text_editor.set_code_hint("")
	text_editor.cancel_code_completion()
	text_editor.center_viewport_to_caret()
	
func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
		
	var key_event = event
	if !key_event.is_pressed():
		return
	if !text_editor.has_focus():
		if (find_replace_bar != null and find_replace_bar.is_visible()) and \
		get_viewport().gui_get_focus_owner() and \
		(find_replace_bar.has_focus() or (get_viewport().gui_get_focus_owner() and \
		find_replace_bar.is_ancestor_of(get_viewport().gui_get_focus_owner()))):
			if SHORTCUT_FINDNEXT.matches_event(key_event):
				find_replace_bar.search_next()
				accept_event()
				return
				
			if SHORTCUT_FINDPREVIOUS.matches_event(key_event):
				find_replace_bar.search_prev()
				accept_event()
				return
		return
		
	if SHORTCUT_MOVEUP.matches_event(key_event):
		text_editor.move_lines_up()
		accept_event()
		return
		
	if SHORTCUT_MOVEDOWN.matches_event(key_event):
		text_editor.move_lines_down()
		accept_event()
		return
		
	if SHORTCUT_DELETELINE.matches_event(key_event):
		text_editor.delete_lines()
		accept_event()
		return
		
	if SHORTCUT_DUPLICATESELECTION.matches_event(key_event):
		text_editor.duplicate_selection()
		accept_event()
		return
	
	if SHORTCUT_DUPLICATELINE.matches_event(key_event):
		text_editor.duplicate_lines()
		accept_event()
		return
		
## 在p_search中，获取p_key这个词的位置。该函数由TextEdit的C++代码改写为GDScript而来。
func _get_column_pos_of_word(p_key: String, p_search: String, p_search_flags: int, p_from_column: int) -> int:
	var col = -1
	
	if p_key.length() == 0 or p_search.length() == 0:
		return -1
		
	if p_from_column < 0 or p_from_column > p_search.length():
		p_from_column = 0
		
	var key_start_is_symbol = is_symbol(p_key[0])
	var key_end_is_symbol = is_symbol(p_key[p_key.length() - 1])
	
	while col == -1 and p_from_column <= p_search.length():
		if (p_search_flags & TextEdit.SEARCH_MATCH_CASE):
			col = p_search.find(p_key, p_from_column)
		else:
			col = p_search.findn(p_key, p_from_column)
			
		if col == -1:
			break
			
		if (p_search_flags & TextEdit.SEARCH_WHOLE_WORDS):
			if not key_start_is_symbol and col > 0 and not is_symbol(p_search[col - 1]):
				col = -1
			elif not key_end_is_symbol and (col + p_key.length()) < p_search.length() \
			and not is_symbol(p_search[col + p_key.length()]):
				col = -1
				
		p_from_column += 1
		
	return col
	
func is_symbol(c: String) -> bool:
	return c != '_' and ((c >= '!' and c <= '/') or (c >= ':' and c <= '@') or \
		(c >= '[' and c <= '`') or (c >= '{' and c <= '~') or c == '\t' or c == ' ')
		
## 返回当前鼠标下的词的起始col和结束col，col从整段文本的第一个字符开始算起，而不是从所在行的第一个字符开始算起
func get_word_global_positions(mouse_pos) -> Vector2i:
	var pos = text_editor.get_line_column_at_pos(mouse_pos)
	var line = pos.y
	var col = pos.x
	var boundry = find_word_boundaries(text_editor.get_line(line), col)
	var start_line = pos.y
	var end_line = pos.y
	var start_col = boundry.x
	var end_col = boundry.y
	
	if start_line == -1 or end_line == -1:
		return Vector2i(-1, -1)  # 没有选中内容
		
	var total_char_count = 0
	var found_start = false
	var found_end = false
	var start_pos = -1
	var end_pos = -1
	
	for line_idx in text_editor.get_line_count():
		var line_text = text_editor.get_line(line_idx)
		var line_len = line_text.length()
		
		if not found_start:
			if line_idx < start_line:
				# 跳过前面的行
				total_char_count += line_len + (1 if line_idx > 0 else 0)  # +1 表示换行符
			elif line_idx == start_line:
				# 当前行是起始行
				start_pos = total_char_count + start_col
				found_start = true
				if start_line == end_line:
					end_pos = total_char_count + end_col
					found_end = true
					break
				else:
					total_char_count += line_len + (1 if line_idx > 0 else 0)  # 加上剩余字符数和换行符
			else:
				if line_idx < end_line:
					total_char_count += line_len + 1
				elif line_idx == end_line:
					end_pos = total_char_count + end_col
					found_end = true
					break
					
	if found_start and found_end:
		return Vector2i(start_pos, end_pos)
	else:
		return Vector2i(-1, -1)
		
func global_pos_to_line_col(global_start: int, global_end: int) -> Dictionary:
	var start_line = -1
	var start_col = -1
	var end_line = -1
	var end_col = -1
	
	var current_pos = 1 # first line \n
	var line_count = text_editor.get_line_count()
	
	for line_idx in line_count:
		var line_text = text_editor.get_line(line_idx)
		var line_len = line_text.length()
		var line_end_pos = current_pos + line_len
		
		# 判断是否命中 start_pos
		if start_line == -1:
			if global_start <= line_end_pos:
				start_line = line_idx
				start_col = global_start - current_pos
			else:
				current_pos = line_end_pos + (1 if line_idx > 0 else 0)  # +1 for newline
				continue
				
		# 判断是否命中 end_pos
		if end_line == -1:
			if global_end <= line_end_pos:
				end_line = line_idx
				end_col = global_end - current_pos
			else:
				current_pos = line_end_pos + (1 if line_idx > 0 else 0)  # +1 for newline
				continue
				
		# 如果都找到了就退出
		if start_line != -1 and end_line != -1:
			break
			
	return {
		"start_line": start_line,
		"start_col": start_col,
		"end_line": end_line,
		"end_col": end_col
	}
	
# 查找单词的起始和结束位置（基于行内列号）
func find_word_boundaries(line_text: String, col: int) -> Vector2i:
	if line_text.is_empty() or col < 0 or col >= line_text.length():
		return Vector2i(-1, -1)# 无效位置
		
	# 初始化边界
	var start_pos = col
	var end_pos = col
	# 向前扫描（找起始位置）
	while start_pos > 0 and not is_symbol(line_text[start_pos - 1]):
		start_pos -= 1
	# 如果中间是符号，不向后扫描
	if is_symbol(line_text[col]):
		end_pos = col - 1 # 最后会加1，正好是col
	else:
		# 向后扫描（找结束位置）
		while end_pos < line_text.length() - 1 and not is_symbol(line_text[end_pos + 1]):
			end_pos += 1
	# 返回行内起始和结束列号
	return Vector2i(start_pos, end_pos + 1)
	
var _draw_line_info = null
func _on_text_editor_draw() -> void:
	if _draw_line_info == null:
		return
	var under_line_from = _draw_line_info[0]
	var under_line_to = _draw_line_info[1]
	text_editor.draw_line(under_line_from, under_line_to, Color.WHITE, 1)
	
func _text_editor_gui_input(p_event: InputEvent) -> void:
	if p_event is InputEventMouseMotion:
		# 按CTRL的时候，显示一个下划线
		if p_event.is_command_or_control_pressed():
			var mouse_pos = text_editor.get_local_mouse_pos()
			var word = text_editor.get_word_at_pos(mouse_pos)
			if word == "":
				return
			var pos = text_editor.get_line_column_at_pos(mouse_pos)
			var line = pos.y
			var col = pos.x
			var boundry = find_word_boundaries(text_editor.get_line(line), col)
			var start_col = boundry.x
			var end_col = boundry.y
			var under_line_from = text_editor.get_pos_at_line_column(line, start_col)
			var under_line_to = text_editor.get_pos_at_line_column(line, end_col)
			var offset = 0
			# TODO FIXME 由于get_pos_at_line_column有bug，获取的位置是前一个的。
			# 这个判断条件可以判断是否有bug。
			if text_editor.get_pos_at_line_column(line, 0) == text_editor.get_pos_at_line_column(line, 1):
				offset = text_editor.get_pos_at_line_column(line, end_col).x - \
				text_editor.get_pos_at_line_column(line, end_col - 1).x
			under_line_from.x += offset
			under_line_to.x += offset
			_draw_line_info = [under_line_from, under_line_to]
			text_editor.queue_redraw()
		elif _draw_line_info != null:
			_draw_line_info = null
			text_editor.queue_redraw()
			
	if p_event is InputEventMouseButton:
		var mb = p_event as InputEventMouseButton
		if mb.is_pressed() and mb.is_command_or_control_pressed():
			if mb.get_button_index() == MOUSE_BUTTON_WHEEL_UP:
				_zoom_in()
				accept_event()
				return
			if mb.get_button_index() == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_out()
				accept_event()
				return
				
		# 双击选词，不要选尖括号和等号，除非只包含尖括号和等号
		if mb.is_pressed() and mb.button_index == MOUSE_BUTTON_LEFT and mb.double_click:
			# 鼠标释放的时候再处理
			while Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				await get_tree().process_frame
			if text_editor.get_caret_count() != 1:
				return
			var selected = text_editor.get_selected_text(0)
			if selected == "":
				return
			if not (selected.contains("<") or selected.contains(">") or selected.contains("=")):
				return
			if selected.replace("<", "").replace(">", "").replace("=", "") == "":
				return
			var line = text_editor.get_selection_from_line(0)
			var col_from = text_editor.get_selection_from_column(0)
			var col_to = text_editor.get_selection_to_column(0)
			
			for i in selected.length():
				if selected[i] in ["<", ">", "="]:
					col_from += 1
				else:
					break
			for i in range(selected.length()-1, -1, -1):
				if selected[i] in ["<", ">", "="]:
					col_to -= 1
				else:
					break
					
			text_editor.deselect(0)
			text_editor.select(line, col_from, line, col_to, 0)
			text_editor.set_caret_column(col_to)
			accept_event()
			return
			
		# 如果按了CTRL，则自动跳到下一个/上一个出现的位置
		elif mb.is_released() and mb.is_command_or_control_pressed():
			var mouse_pos = text_editor.get_local_mouse_pos()
			var highlighted_text = text_editor.get_word_at_pos(mouse_pos)
			if highlighted_text == "":
				return
				
			# 当前选中词在整个文本中的起始col和结束col
			var search_flag = TextEdit.SEARCH_MATCH_CASE | TextEdit.SEARCH_WHOLE_WORDS
			var highlighted_pos = get_word_global_positions(mouse_pos)
			var to_highlight_col = -1
			
			# 上一个
			if Input.is_key_pressed(KEY_SHIFT):
				var pre_highlighted_text_col = highlighted_pos.y
				var next_round_flag = false # 第二轮
				while true:
					var next_highlighted_text_col = _get_column_pos_of_word(
						highlighted_text, text_editor.text, search_flag, 
						pre_highlighted_text_col)
					if next_highlighted_text_col == -1:
						if next_round_flag:
							break
						next_round_flag = true
						next_highlighted_text_col = _get_column_pos_of_word(
							highlighted_text, text_editor.text, search_flag, 0)
					if next_highlighted_text_col == -1:
						return
					if next_highlighted_text_col + highlighted_text.length() >= highlighted_pos.y:
						if next_round_flag:
							break
					pre_highlighted_text_col = next_highlighted_text_col + highlighted_text.length()
				to_highlight_col = pre_highlighted_text_col - highlighted_text.length()
			# 下一个
			else:
				var next_highlighted_text_col = _get_column_pos_of_word(
					highlighted_text, text_editor.text, search_flag, highlighted_pos.y)
				if next_highlighted_text_col == -1:
					next_highlighted_text_col = _get_column_pos_of_word(
						highlighted_text, text_editor.text, search_flag, 0)
				if next_highlighted_text_col == -1:
					return
				to_highlight_col = next_highlighted_text_col
				
			if to_highlight_col > 0:
				var to_highlight_info = global_pos_to_line_col(to_highlight_col, 
					to_highlight_col + highlighted_text.length())
				text_editor.set_caret_line(to_highlight_info.start_line, false)
				text_editor.set_caret_column(to_highlight_info.start_col, false)
				text_editor.select(to_highlight_info.start_line, to_highlight_info.start_col, 
					to_highlight_info.end_line, to_highlight_info.end_col)
				text_editor.center_viewport_to_caret(0)
				_draw_line_info = null
				queue_redraw()
				accept_event()
				
	if p_event is InputEventMagnifyGesture:
		var magnify_gesture = p_event as InputEventMagnifyGesture
		_zoom_to(zoom_factor * pow(magnify_gesture.get_factor(), 0.25))
		accept_event()
		return
		
	#if p_event is InputEventShortcut:
		#var k = p_event as InputEventShortcut
		#if k.is_pressed():
			#if (ED_IS_SHORTCUT("script_editor/zoom_in", p_event)) {
				#_zoom_in();
				#accept_event();
				#return;
			#}
			#if (ED_IS_SHORTCUT("script_editor/zoom_out", p_event)) {
				#_zoom_out();
				#accept_event();
				#return;
			#}
			#if (ED_IS_SHORTCUT("script_editor/reset_zoom", p_event)) {
				#_zoom_to(1);
				#accept_event();
				#return
				
func _line_col_changed() -> void:
	if !code_complete_timer.is_stopped() and code_complete_timer_line != text_editor.get_caret_line():
		code_complete_timer.stop()
		
	var line = text_editor.get_line(text_editor.get_caret_line())
	
	var positional_column = 0
	for i in text_editor.get_caret_column():
		if line[i] == '\t':
			positional_column += text_editor.get_indent_size() # Tab size
		else:
			positional_column += 1
			
	var sb = str(text_editor.get_caret_line() + 1).lpad(4) + " : " + str((positional_column + 1)).lpad(3)
	line_and_col_txt.set_text(sb)
	
	if find_replace_bar:
		if not find_replace_bar.line_col_changed_for_result:
			find_replace_bar.needs_to_count_results = true
		find_replace_bar.line_col_changed_for_result = false
		
func _text_changed() -> void:
	if code_complete_enabled:# and text_editor.is_insert_text_operation():
		code_complete_timer_line = text_editor.get_caret_line()
		code_complete_timer.start()
		
	idle.start()
	text_changed.emit()
	
	if find_replace_bar:
		find_replace_bar.needs_to_count_results = true
		
func _code_complete_timer_timeout() -> void:
	pass # Replace with function body.TODO
	
func _complete_request() -> void:
	# TODO
	pass
	#var entries = []
	#var ctext = text_editor.get_text_for_code_completion()
	#_code_complete_script(ctext, entries)
	#var forced = false
	#if code_complete_func:
		#code_complete_func(code_complete_ud, ctext, entries, forced)
		#
	#for e in entries:
		#var font_color = completion_font_color
		#if !e.theme_color_name.is_empty() and EDITOR_GET("text_editor/completion/colorize_suggestions"):
			#font_color = get_theme_color(e.theme_color_name, "Editor")
		#elif e.insert_text.begins_with("\"") or e.insert_text.begins_with("\'"):
			#font_color = completion_string_color
		#elif e.insert_text.begins_with("##") or e.insert_text.begins_with("///"):
			#font_color = completion_doc_comment_color
		#elif e.insert_text.begins_with("&"):
			#font_color = completion_string_name_color
		#elif e.insert_text.begins_with("^"):
			#font_color = completion_node_path_color
		#elif e.insert_text.begins_with("#") or e.insert_text.begins_with("//"):
			#font_color = completion_comment_color
		#text_editor.add_code_completion_option(e.kind, e.display, e.insert_text, font_color, _get_completion_icon(e), e.default_value, e.location)
	#text_editor.update_code_completion_options(forced)
	
#func _get_completion_icon() # TODO
#func update_editor_settings()# TODO
	
func set_find_replace_bar(p_bar):
	if find_replace_bar:
		return
	find_replace_bar = p_bar
	find_replace_bar.set_text_edit(self)
	find_replace_bar.connect("error", error.set_text)
	
func remove_find_replace_bar():
	if not find_replace_bar:
		return
	find_replace_bar.disconnect("error", error.set_text)
	find_replace_bar = null
	
func _zoom_popup_id_pressed(p_idx: int) -> void:
	_zoom_to(zoom_button.get_popup().get_item_metadata(p_idx))
	
func _set_show_errors_panel(p_show: bool):
	is_errors_panel_opened = p_show
	emit_signal("show_errors_panel", p_show)
	
func _set_show_warnings_panel(p_show: bool):
	is_warnings_panel_opened = p_show
	emit_signal("show_warnings_panel", p_show)
	
func _toggle_scripts_pressed() -> void:
	toggle_scripts_pressed.emit()
	update_toggle_scripts_button()
	
func _error_pressed(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.is_pressed() and mb.get_button_index() == MOUSE_BUTTON_LEFT:
			goto_error()
			
func set_warning_count(p_warning_count: int):
	warning_button.set_text(str(p_warning_count))
	warning_button.set_visible(p_warning_count > 0)
	if !p_warning_count:
		_set_show_warnings_panel(false)
		
func _notification(p_what):
	match p_what:
		NOTIFICATION_ENTER_TREE, NOTIFICATION_THEME_CHANGED:
			EDSCALE = EditorInterface.get_editor_scale()
			#if toggle_scripts_button and toggle_scripts_button.is_visible():
				#update_toggle_scripts_button()
			##_update_text_editor_theme()
		NOTIFICATION_VISIBILITY_CHANGED:
			if toggle_scripts_button and toggle_scripts_button.is_visible():
				update_toggle_scripts_button()
			set_process_input(is_visible_in_tree())
		NOTIFICATION_PREDELETE:
			if find_replace_bar:
				find_replace_bar.set_text_edit(null)
				
func set_error_count(p_error_count: int):
	error_button.set_text(str(p_error_count))
	error_button.set_visible(p_error_count > 0)
	if !p_error_count:
		_set_show_errors_panel(false)
		
func _zoom_in():
	var s = text_editor.get_theme_font_size("font_size")
	_zoom_to(zoom_factor * (s + max(1.0, EDSCALE)) / s)
	
func _zoom_out():
	var s = text_editor.get_theme_font_size("font_size")
	_zoom_to(zoom_factor * (s - max(1.0, EDSCALE)) / s)
	
func _zoom_to(p_zoom_factor: float):
	if zoom_factor == p_zoom_factor:
		return
		
	var old_zoom_factor = zoom_factor
	
	set_zoom_factor(p_zoom_factor)
	
	if old_zoom_factor != zoom_factor:
		emit_signal("zoomed", zoom_factor)
		
func set_zoom_factor(p_zoom_factor: float):
	zoom_factor = clamp(p_zoom_factor, ZOOM_FACTOR_PRESETS[0], ZOOM_FACTOR_PRESETS.back());
	var neutral_font_size = int(EDITOR_GET("interface/editor/code_font_size")) * EDSCALE;
	var new_font_size = roundi(zoom_factor * neutral_font_size)
	
	zoom_button.set_text(str(roundi(zoom_factor * 100)) + " %")
	
	if text_editor.has_theme_font_size_override("font_size"):
		text_editor.remove_theme_font_size_override("font_size")
		
	text_editor.add_theme_font_size_override("font_size", new_font_size)
	
func _ready() -> void:
	set_translation_domain("godot.editor")
	#status_bar.custom_minimum_size.y = 24 * EDSCALE
	
	var zoom_menu = zoom_button.get_popup()
	zoom_menu.clear(true)
	for i in ZOOM_FACTOR_PRESETS.size():
		var z = ZOOM_FACTOR_PRESETS[i]
		zoom_menu.add_item(str(roundi(z * 100)) + " %")
		zoom_menu.set_item_metadata(i, z)
	zoom_menu.id_pressed.connect(_zoom_popup_id_pressed)
	
	text_editor.structured_text_bidi_override = TextServer.STRUCTURED_TEXT_GDSCRIPT
	text_editor.code_completion_prefixes = [".", ",", "(", "=", "$", "@", "\"", "\'"]
	text_editor.delimiter_strings = ["''", '""', "<>"]
	text_editor.delimiter_comments = ["<!--"]
	text_editor.text = content
	content = ""
	indentation_txt.text = tr("Tabs", "Indentation")
	add_theme_constant_override("separation", int(4 * EDSCALE))
	
	completion_font_color = EDITOR_GET("text_editor/theme/highlighting/completion_font_color")
	completion_string_color = EDITOR_GET("text_editor/theme/highlighting/string_color")
	completion_string_name_color = EDITOR_GET("text_editor/theme/highlighting/gdscript/string_name_color")
	completion_node_path_color = EDITOR_GET("text_editor/theme/highlighting/gdscript/node_path_color")
	completion_comment_color = EDITOR_GET("text_editor/theme/highlighting/comment_color")
	completion_doc_comment_color = EDITOR_GET("text_editor/theme/highlighting/doc_comment_color")
	
	update_toggle_scripts_button()
	
func EDITOR_GET(n: String):
	return EditorInterface.get_editor_settings().get_setting(n)
	
func is_scripts_panel_toggled():
	return not scripts_panel_toggled
	
func update_toggle_scripts_button():
	if is_layout_rtl():
		toggle_scripts_button.icon = get_theme_icon("Forward" if is_scripts_panel_toggled() else "Back", "EditorIcons")
	else:
		toggle_scripts_button.icon = get_theme_icon("Back" if is_scripts_panel_toggled() else "Forward", "EditorIcons")
	toggle_scripts_button.tooltip_text = "%s (%s)" % ["Toggle Scripts Panel", "Ctrl+BackSlash"]

func goto_error():
	if !error.get_text().is_empty():
		if text_editor.get_line_count() != error_line:
			text_editor.unfold_line(error_line)
			
		text_editor.remove_secondary_carets();
		text_editor.set_caret_line(error_line);
		text_editor.set_caret_column(error_column);
		text_editor.center_viewport_to_caret()
		
func _error_button_pressed() -> void:
	_set_show_errors_panel(!is_errors_panel_opened)
	_set_show_warnings_panel(false)
	
func _warning_button_pressed() -> void:
	_set_show_warnings_panel(!is_warnings_panel_opened)
	_set_show_errors_panel(false)
	
#func ED_IS_SHORTCUT(p_name: String, p_event: InputEvent) -> bool:
	#return true# 
	
func _text_changed_idle_timeout() -> void:
	pass # Replace with function body.
