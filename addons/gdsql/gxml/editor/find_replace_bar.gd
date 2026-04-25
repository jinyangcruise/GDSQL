@tool
## modified from C++ code_edit.cpp's FindReplaceBar
## 移植记录：
## 1. Fix find result current match count 17c8e8b2b44af68e5e6ee2ab24970bb0bd1f0a7f
## 2. b72d8a3: Cancel code completion and code hint in multiple places
## 3. 86762f0a03206998bddc539a80c438c2da5068ce Code Editor: Add button to toggle 
##    between search and search+replace modes
## 已检查的版本：
## 1. Merge pull request #63744 from KoBeWi/shader_spaghetti Refactor toggling script list 
## 3bc84c298841e2633444535ea0b817cda5d15c73
extends HBoxContainer

@onready var toggle_replace_button: Button = $toggle_replace_button
@onready var search_text: LineEdit = $vbc_lineedit/search_text
@onready var hbc_button_search: HBoxContainer = $vbc_button/hbc_button_search
@onready var hbc_button_replace: HBoxContainer = $vbc_button/hbc_button_replace
@onready var hbc_option_search: HBoxContainer = $vbc_option/hbc_option_search
@onready var hbc_option_replace: HBoxContainer = $vbc_option/hbc_option_replace
@onready var matches_label: Label = $vbc_button/hbc_button_search/matches_label
@onready var replace_text: LineEdit = $vbc_lineedit/replace_text
@onready var find_prev: Button = $vbc_button/hbc_button_search/find_prev
@onready var find_next: Button = $vbc_button/hbc_button_search/find_next
@onready var case_sensitive: CheckBox = $vbc_option/hbc_option_search/case_sensitive
@onready var whole_words: CheckBox = $vbc_option/hbc_option_search/whole_words
@onready var replace: Button = $vbc_button/hbc_button_replace/replace
@onready var replace_all: Button = $vbc_button/hbc_button_replace/replace_all
@onready var selection_only: CheckBox = $vbc_option/hbc_option_replace/selection_only
@onready var hide_button: TextureButton = $hide_button

signal error(label: String)

var EDSCALE: float = EditorInterface.get_editor_scale()
var base_text_editor: Node
var text_editor: CodeEdit

var flags = 0
var result_line = 0
var result_col = 0
var results_count = -1
var results_count_to_current = -1
var replace_all_mode = false
var preserve_cursor = false
var needs_to_count_results = true
var line_col_changed_for_result = false

enum SearchMode {
	SEARCH_CURRENT,
	SEARCH_NEXT,
	SEARCH_PREV,
}

func _notification(p_what: int):
	match p_what:
		NOTIFICATION_READY:
			pass
		NOTIFICATION_VISIBILITY_CHANGED:
			set_process_unhandled_input(is_visible_in_tree())
		NOTIFICATION_ENTER_TREE, NOTIFICATION_THEME_CHANGED:
			EDSCALE = EditorInterface.get_editor_scale()
			#if matches_label:
				#matches_label.add_theme_color_override("font_color", 
					#(get_theme_color("font_color", "Label") if results_count > 0 else\
					#get_theme_color("error_color", "Editor")))
		NOTIFICATION_PREDELETE:
			if base_text_editor:
				base_text_editor.remove_find_replace_bar()
				base_text_editor = null
				
func _unhandled_input(p_event):
	if not p_event is InputEventKey:
		return
	var k = p_event as InputEventKey
	if k.is_action_pressed("ui_cancel", false, true):
		var focus_owner = get_viewport().gui_get_focus_owner()
		
		if text_editor.has_focus() or (focus_owner and is_ancestor_of(focus_owner)):
			_hide_bar()
			accept_event()
			
func _focus_lost() -> void:
	if Input.is_action_pressed("ui_cancel"):
		# Unfocused after pressing Escape, so hide the bar.
		_hide_bar(true)
		
func _update_flags(p_direction_backwards: bool):
	flags = 0
	if is_whole_words():
		flags |= TextEdit.SEARCH_WHOLE_WORDS
	if is_case_sensitive():
		flags |= TextEdit.SEARCH_MATCH_CASE
	if p_direction_backwards:
		flags |= TextEdit.SEARCH_BACKWARDS
		
func _search(p_flags: int, p_from_line: int, p_from_col: int):
	if !preserve_cursor:
		text_editor.remove_secondary_carets()
		
	var text = get_search_text()
	var pos = text_editor.search(text, p_flags, p_from_line, p_from_col)
	
	if pos.x != -1:
		if !preserve_cursor and !is_selection_only():
			text_editor.unfold_line(pos.y)
			text_editor.select(pos.y, pos.x, pos.y, pos.x + text.length())
			text_editor.set_caret_line(pos.y, true, true, 0, 0) # needed in gdscript
			text_editor.center_viewport_to_caret(0)
			text_editor.set_code_hint("")
			text_editor.cancel_code_completion()
			
			line_col_changed_for_result = true
			
		text_editor.set_search_text(text)
		text_editor.set_search_flags(p_flags)
		
		result_line = pos.y
		result_col = pos.x
		
		_update_results_count()
	else:
		results_count = 0
		result_line = -1
		result_col = -1
		text_editor.set_search_text("")
		text_editor.set_search_flags(p_flags)
		
	_update_matches_display()
	return pos.x != -1
	
func _replace():
	text_editor.begin_complex_operation()
	text_editor.remove_secondary_carets()
	var selection_enabled = text_editor.has_selection(0)
	var selection_begin = Vector2i.ZERO
	var selection_end = Vector2i.ZERO
	if selection_enabled:
		selection_begin = Vector2i(text_editor.get_selection_from_line(0), text_editor.get_selection_from_column(0))
		selection_end = Vector2i(text_editor.get_selection_to_line(0), text_editor.get_selection_to_column(0))
		
	var repl_text = get_replace_text() as String
	var search_text_len = get_search_text().length()
	
	if selection_enabled and is_selection_only():
		# Restrict search_current() to selected region.
		# ALERT if the 4th param is set to -1, Godot get error
		text_editor.set_caret_line(selection_begin.x, false, true, 0, 0) # FIXME?
		text_editor.set_caret_column(selection_begin.y, true, 0)
		
	if search_current():
		text_editor.unfold_line(result_line)
		text_editor.select(result_line, result_col, result_line, result_col + search_text_len, 0)
		
		if selection_enabled and is_selection_only():
			var match_from = Vector2i(result_line, result_col)
			var match_to = Vector2i(result_line, result_col + search_text_len)
			if !(match_from < selection_begin || match_to > selection_end):
				text_editor.insert_text_at_caret(repl_text, 0)
				if match_to.x == selection_end.x:
					# Adjust selection bounds if necessary.
					selection_end.y += repl_text.length() - search_text_len
		else:
			text_editor.insert_text_at_caret(repl_text, 0)
			
	text_editor.end_complex_operation()
	results_count = -1
	results_count_to_current = -1
	needs_to_count_results = true

	if selection_enabled and is_selection_only():
		# Reselect in order to keep 'Replace' restricted to selection.
		text_editor.select(selection_begin.x, selection_begin.y, selection_end.x, selection_end.y, 0)
	else:
		text_editor.deselect(0)
		
func _replace_all() -> void:
	text_editor.begin_complex_operation()
	text_editor.remove_secondary_carets()
	text_editor.disconnect("text_changed", _editor_text_changed)
	# Line as x so it gets priority in comparison, column as y.
	var orig_cursor = Vector2i(text_editor.get_caret_line(0), text_editor.get_caret_column(0))
	var prev_match = Vector2i(-1, -1)
	
	var selection_enabled = text_editor.has_selection(0)
	if !is_selection_only():
		text_editor.deselect()
		selection_enabled = false
	else:
		result_line = -1
		result_col = -1
		
	var selection_begin = Vector2i.ZERO
	var selection_end = Vector2i.ZERO
	if selection_enabled:
		selection_begin = Vector2i(text_editor.get_selection_from_line(0), text_editor.get_selection_from_column(0))
		selection_end = Vector2i(text_editor.get_selection_to_line(0), text_editor.get_selection_to_column(0))
		
	var vsval = text_editor.get_v_scroll()
	
	var repl_text = get_replace_text()
	var search_text_len = get_search_text().length()
	
	var rc = 0
	
	replace_all_mode = true
	
	if selection_enabled and is_selection_only():
		text_editor.set_caret_line(selection_begin.x, false, true, 0, 0) # FIXME?
		text_editor.set_caret_column(selection_begin.y, true, 0)
	else:
		text_editor.set_caret_line(0, false, true, 0, 0) # FIXME?
		text_editor.set_caret_column(0, true, 0)
		
	if search_current():
		while true:
			# Replace area.
			var match_from = Vector2i(result_line, result_col)
			var match_to = Vector2i(result_line, result_col + search_text_len)
			if match_from < prev_match:
				break # Done.
				
			prev_match = Vector2i(result_line, result_col + repl_text.length())
			
			text_editor.unfold_line(result_line)
			text_editor.select(result_line, result_col, result_line, match_to.y, 0)
			
			if selection_enabled:
				if match_from < selection_begin or match_to > selection_end:
					break # Done.
					
				# Replace but adjust selection bounds.
				text_editor.insert_text_at_caret(repl_text, 0)
				if match_to.x == selection_end.x:
					selection_end.y += repl_text.length() - search_text_len
			else:
				# Just replace.
				text_editor.insert_text_at_caret(repl_text, 0)
				
			rc += 1
			if not search_next():
				break
				
	text_editor.end_complex_operation()
	
	replace_all_mode = false
	
	# Restore editor state (selection, cursor, scroll).
	text_editor.set_caret_line(orig_cursor.x, false, true, 0, 0)
	text_editor.set_caret_column(orig_cursor.y, true, 0)
	
	if selection_enabled:
		# Reselect.
		text_editor.select(selection_begin.x, selection_begin.y, selection_end.x, selection_end.y, 0)
		
	text_editor.set_v_scroll(vsval)
	matches_label.add_theme_color_override("font_color", 
		(get_theme_color("font_color", "Label") if rc > 0 \
		else get_theme_color("error_color", "Editor")))
	matches_label.set_text(tr("%d replaced.") % rc)
	
	var callable = Callable(text_editor, "connect")
	callable.call_deferred("text_changed", _editor_text_changed)
	results_count = -1
	results_count_to_current = -1
	needs_to_count_results = true
	
func _get_search_from(r_line_and_col: Array, p_search_mode: SearchMode):
	var r_line = r_line_and_col[0]
	var r_col = r_line_and_col[1]
	if !text_editor.has_selection(0) or is_selection_only():
		r_line = text_editor.get_caret_line(0)
		r_col = text_editor.get_caret_column(0)
		r_line_and_col[0] = r_line
		r_line_and_col[1] = r_col
		
		if p_search_mode == SearchMode.SEARCH_PREV and r_line == result_line and r_col >= result_col \
		and r_col <= result_col + get_search_text().length():
			r_col = result_col
			r_line_and_col[1] = r_col
		return
		
	if p_search_mode == SearchMode.SEARCH_NEXT:
		r_line = text_editor.get_selection_to_line()
		r_col = text_editor.get_selection_to_column()
	else:
		r_line = text_editor.get_selection_from_line()
		r_col = text_editor.get_selection_from_column()
	r_line_and_col[0] = r_line
	r_line_and_col[1] = r_col
	
func _update_results_count():
	var caret_line_and_column = [0, 0]
	_get_search_from(caret_line_and_column, SearchMode.SEARCH_CURRENT);
	var caret_line = caret_line_and_column[0]
	var caret_column = caret_line_and_column[1]
	var match_selected = caret_line == result_line and caret_column == result_col \
		and !is_selection_only() and text_editor.has_selection(0)
		
	if match_selected and !needs_to_count_results and result_line != -1 and results_count_to_current > 0:
		results_count_to_current += -1 if (flags & TextEdit.SEARCH_BACKWARDS) else 1
		
		if results_count_to_current > results_count:
			results_count_to_current = results_count_to_current - results_count
		elif results_count_to_current <= 0:
			results_count_to_current = results_count
		return
		
	var searched = get_search_text() as String
	if searched == "":
		return
		
	needs_to_count_results = !match_selected
	results_count = 0
	results_count_to_current = 0
	
	for i in text_editor.get_line_count():
		var line_text = text_editor.get_line(i)
		var col_pos = 0
		var searched_start_is_symbol = is_symbol(searched[0])
		var searched_end_is_symbol = is_symbol(searched[searched.length() - 1])
		
		while true:
			col_pos = line_text.find(searched, col_pos) if is_case_sensitive() \
				else line_text.findn(searched, col_pos)
			if col_pos == -1:
				break
			if is_whole_words():
				if !searched_start_is_symbol and col_pos > 0 and \
				!is_symbol(line_text[col_pos - 1]):
					col_pos += searched.length()
					continue
					
				if !searched_end_is_symbol and col_pos + searched.length() < line_text.length() \
				and !is_symbol(line_text[col_pos + searched.length()]):
					col_pos += searched.length()
					continue
					
			results_count += 1
			if i <= result_line and col_pos <= result_col:
				results_count_to_current = results_count
			if i == result_line and col_pos < result_col and col_pos + searched.length() > result_col:
				# Searching forwards and backwards with repeating text can lead to different matches.
				col_pos = result_col
				
			col_pos += searched.length()
	if !match_selected:
		# Current result should refer to the match before the caret, if the caret is not on a match.
		if caret_line != result_line or caret_column != result_col:
			results_count_to_current -= 1
		if results_count_to_current == 0 and (caret_line > result_line or \
		(caret_line == result_line and caret_column > result_col)):
			# Caret is after all matches.
			results_count_to_current = results_count;
			
func _update_matches_display():
	if search_text.get_text() == "" or results_count == -1:
		matches_label.hide()
	else:
		matches_label.show()
		matches_label.add_theme_color_override("font_color", 
			(get_theme_color("font_color", "Label") if results_count > 0 else \
			get_theme_color("error_color", "Editor")))
			
		if results_count == 0:
			matches_label.set_text(tr("No match"))
		elif results_count_to_current == -1:
			#var s = "%d match" if results_count == 1 else "%d matches"
			#matches_label.set_text(tr(s) % results_count)
			matches_label.set_text(atr_n("%d match", "%d matches", results_count) % results_count)
		else:
			#var s = "%d of %d match" if results_count == 1 else "%d of %d matches"
			#matches_label.set_text(tr(s) % [results_count_to_current, results_count])
			matches_label.set_text(atr_n("%d of %d match", "%d of %d matches", 
				results_count) % [results_count_to_current, results_count])
				
	find_prev.set_disabled(results_count < 1)
	find_next.set_disabled(results_count < 1)
	replace.set_disabled(search_text.get_text().is_empty())
	replace_all.set_disabled(search_text.get_text().is_empty())
	
func search_current():
	_update_flags(false)
	var line_and_col = [0, 0]
	_get_search_from(line_and_col, SearchMode.SEARCH_CURRENT)
	return _search(flags, line_and_col[0], line_and_col[1])
	
func search_prev() -> bool:
	if is_selection_only() and !replace_all_mode:
		return false
		
	if !is_visible():
		popup_search(true)
		
	var text = get_search_text()
	
	if (flags & TextEdit.SEARCH_BACKWARDS) == 0:
		needs_to_count_results = true
		
	_update_flags(true)
	
	var line_and_col = [0, 0]
	_get_search_from(line_and_col, SearchMode.SEARCH_PREV)
	var line = line_and_col[0]
	var col = line_and_col[1]
	
	col -= text.length()
	if col < 0:
		line -= 1
		if line < 0:
			line = text_editor.get_line_count() - 1
			
		col = text_editor.get_line(line).length()
		
	return _search(flags, line, col)
	
func search_next() -> bool:
	if is_selection_only() and !replace_all_mode:
		return false
		
	if !is_visible():
		popup_search(true)
		
	if flags & TextEdit.SEARCH_BACKWARDS:
		needs_to_count_results = true
		
	_update_flags(false)
	
	var line_and_col = [0, 0]
	_get_search_from(line_and_col, SearchMode.SEARCH_NEXT)
	var line = line_and_col[0]
	var col = line_and_col[1]
	
	return _search(flags, line, col)
	
func _hide_bar(p_force_focus: bool = false) -> void:
	if replace_text.has_focus() or search_text.has_focus() or p_force_focus:
		text_editor.grab_focus()
		
	text_editor.set_search_text("")
	result_line = -1
	result_col = -1
	hide()
	
func _update_toggle_replace_button(p_replace_visible: bool):
	var tooltip = tr("Hide Replace") if p_replace_visible else tr("Show Replace")
	#var shortcut = ED_GET_SHORTCUT("script_text_editor/find" if p_replace_visible else "script_text_editor/replace").to_string()
	var shortcut = "Ctrl+F" if p_replace_visible else "Ctrl+R"
	toggle_replace_button.tooltip_text = "%s (%s)" % [tooltip, shortcut]
	var rtl_compliant_arrow = ("GuiTreeArrowLeft") if is_layout_rtl() else ("GuiTreeArrowRight")
	toggle_replace_button.icon = get_editor_theme_icon("GuiTreeArrowDown" if p_replace_visible else rtl_compliant_arrow)
	
func _show_search(p_with_replace: bool, p_show_only: bool):
	show()
	if p_show_only:
		return
		
	var on_one_line = text_editor.has_selection(0) and \
		text_editor.get_selection_from_line(0) == text_editor.get_selection_to_line(0)
	var focus_replace = p_with_replace and on_one_line
	
	if focus_replace:
		search_text.deselect()
		replace_text.call_deferred("grab_focus")
	else:
		replace_text.deselect()
		search_text.call_deferred("grab_focus")
		
	if on_one_line:
		search_text.set_text(text_editor.get_selected_text(0))
		result_line = text_editor.get_selection_from_line()
		result_col = text_editor.get_selection_from_column()
		
	if !get_search_text().is_empty():
		if focus_replace:
			replace_text.select_all()
			replace_text.set_caret_column(replace_text.get_text().length())
		else:
			search_text.select_all()
			search_text.set_caret_column(search_text.get_text().length())
			
		preserve_cursor = true
		_search_text_changed(get_search_text())
		preserve_cursor = false
		
func popup_search(p_show_only: bool = false):
	replace_text.hide()
	hbc_button_replace.hide()
	hbc_option_replace.hide()
	selection_only.set_pressed(false)
	_update_toggle_replace_button(false)
	_show_search(false, p_show_only)
	
func popup_replace():
	if !replace_text.is_visible_in_tree():
		replace_text.show()
		hbc_button_replace.show()
		hbc_option_replace.show()
		_update_toggle_replace_button(true)
		
	selection_only.set_pressed(text_editor.has_selection(0) and \
		text_editor.get_selection_from_line(0) < text_editor.get_selection_to_line(0))
		
	_show_search(true, false)
	
func _search_options_changed(_toggled_on: bool) -> void:
	results_count = -1;
	results_count_to_current = -1;
	needs_to_count_results = true;
	search_current()
	
func _editor_text_changed():
	results_count = -1
	results_count_to_current = -1
	needs_to_count_results = true
	if is_visible_in_tree():
		preserve_cursor = true
		search_current()
		preserve_cursor = false
		
func _search_text_changed(_new_text: String) -> void:
	results_count = -1;
	results_count_to_current = -1;
	needs_to_count_results = true;
	search_current()
	
func _search_text_submitted(_new_text: String) -> void:
	if Input.is_key_pressed(KEY_SHIFT):
		search_prev()
	else:
		search_next()
		
	search_text.edit.call_deferred()
	
func _replace_text_submitted(_new_text: String) -> void:
	if selection_only.is_pressed() and text_editor.has_selection(0):
		_replace_all()
		_hide_bar()
	elif Input.is_key_pressed(KEY_SHIFT):
		_replace()
		search_prev()
	else:
		_replace()
		search_next()
		
func _toggle_replace_pressed() -> void:
	var replace_visible = replace_text.is_visible_in_tree()
	@warning_ignore("standalone_ternary")
	popup_search(true) if replace_visible else popup_replace()
	
func get_search_text() -> String:
	return search_text.get_text()
	
func get_replace_text():
	return replace_text.get_text()
	
func is_case_sensitive() -> bool:
	return case_sensitive.is_pressed()
	
func is_whole_words() -> bool:
	return whole_words.is_pressed()
	
func is_selection_only():
	return selection_only.is_pressed()
	
func set_error(p_label):
	error.emit(p_label)
	
func set_text_edit(p_text_editor):
	if p_text_editor == base_text_editor:
		return
		
	if base_text_editor:
		text_editor.set_search_text("")
		base_text_editor.remove_find_replace_bar()
		base_text_editor = null
		text_editor.disconnect("text_changed", _editor_text_changed)
		text_editor = null
		
	if not p_text_editor:
		return
		
	results_count = -1
	results_count_to_current = -1
	needs_to_count_results = true
	base_text_editor = p_text_editor
	text_editor = base_text_editor.text_editor
	text_editor.connect("text_changed", _editor_text_changed)
	
	_editor_text_changed()
	
func _ready() -> void:
	search_text.custom_minimum_size.x = 100 * EDSCALE
	replace_text.custom_minimum_size.x = 100 * EDSCALE
	#find_prev.custom_minimum_size.y = search_text.size.y
	if not find_prev.icon:
		find_prev.icon = get_theme_icon("MoveUp", "EditorIcons")
	if not find_next.icon:
		find_next.icon = get_theme_icon("MoveDown", "EditorIcons")
	hide_button.set_texture_normal(get_theme_icon("Close", "EditorIcons"))
	hide_button.set_texture_hover(get_theme_icon("Close", "EditorIcons"))
	hide_button.set_texture_pressed(get_theme_icon("Close", "EditorIcons"))
	hide_button.set_custom_minimum_size(hide_button.get_texture_normal().get_size())
	_update_toggle_replace_button(replace_text.is_visible_in_tree())
	
func _exit_tree() -> void:
	find_prev.icon = null
	find_next.icon = null
	
func EDITOR_GET(n: String):
	return EditorInterface.get_editor_settings().get_setting(n)
	
func ED_GET_SHORTCUT(n: String):
	return EditorInterface.get_editor_settings().get_setting(n)
	
func get_editor_theme_icon(p_name):
	return get_theme_icon(p_name, "EditorIcons")
	
func is_symbol(c: String) -> bool:
	return c != '_' and ((c >= '!' and c <= '/') or (c >= ':' and c <= '@') or \
	(c >= '[' and c <= '`') or (c >= '{' and c <= '~') or c == '\t' or c == ' ')
