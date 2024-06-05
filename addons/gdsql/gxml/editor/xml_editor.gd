@tool
extends VBoxContainer

@onready var text_editor: CodeEdit = $TextEditor
@onready var status_bar: HBoxContainer = $StatusBar
@onready var toggle_scripts_button: Button = $StatusBar/ToggleScriptsButton
@onready var error_button: Button = $StatusBar/ErrorButton
@onready var warning_button: Button = $StatusBar/WarningButton
@onready var zoom_button: MenuButton = $StatusBar/ZoomButton
@onready var line_and_col_txt: Label = $StatusBar/LineAndColTxt
@onready var indentation_txt: Label = $StatusBar/IndentationTxt
@onready var error: Label = $StatusBar/Scroll/Error
@onready var idle: Timer = $Idle
@onready var code_complete_timer: Timer = $CodeCompleteTimer

signal text_changed
signal validate_script
signal show_errors_panel
signal show_warnings_panel
signal zoomed(p_zoom_factor: float)

signal toggle_scripts_pressed

var content: String
var EDSCALE: float
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

const ZOOM_FACTOR_PRESETS = [0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0]

func _notification(p_what):
	match p_what:
		NOTIFICATION_THEME_CHANGED:
			if toggle_scripts_button and toggle_scripts_button.is_visible():
				update_toggle_scripts_button()
			#_update_text_editor_theme() TODO
		NOTIFICATION_VISIBILITY_CHANGED:
			if toggle_scripts_button and toggle_scripts_button.is_visible():
				update_toggle_scripts_button()
			set_process_input(is_visible_in_tree())
		NOTIFICATION_PREDELETE:
			pass
			#if find_replace_bar:
				#find_replace_bar->set_text_edit(nullptr)
			
func _ready() -> void:
	EDSCALE = get_display_scale()
	status_bar.custom_minimum_size.y = 24 * EDSCALE
	
	var zoom_menu = zoom_button.get_popup()
	zoom_menu.clear(true)
	for i in ZOOM_FACTOR_PRESETS.size():
		var z = ZOOM_FACTOR_PRESETS[i]
		zoom_menu.add_item(str(round(z * 100)) + " %")
		zoom_menu.set_item_metadata(i, z)
	zoom_menu.id_pressed.connect(_zoom_popup_id_pressed)
	
	text_editor.structured_text_bidi_override = TextServer.STRUCTURED_TEXT_GDSCRIPT
	text_editor.code_completion_prefixes = [".", ",", "(", "=", "$", "@", "\"", "\'"]
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
	
	
func EDITOR_GET(n: String):
	return EditorInterface.get_editor_settings().get_setting(n)
	
func get_display_scale():
	var setting = EDITOR_GET("interface/editor/display_scale")
	match setting:
		0:
			return get_auto_display_scale()
		1:
			return 0.75
		2:
			return 1.0
		3:
			return 1.25
		4:
			return 1.5
		5:
			return 1.75
		6:
			return 2.0
		_:
			return EDITOR_GET("interface/editor/custom_display_scale")
			
func get_auto_display_scale() -> float:
	#ifdef LINUXBSD_ENABLED
	if OS.has_feature("linuxbsd"):
		if DisplayServer.get_name() == "Wayland":
			var main_window_scale = DisplayServer.screen_get_scale(DisplayServer.SCREEN_OF_MAIN_WINDOW)
			
			if DisplayServer.get_screen_count() == 1 || fract(main_window_scale) != 0:
				return main_window_scale
			return DisplayServer.screen_get_max_scale()
	#endif

	#if defined(MACOS_ENABLED) || defined(ANDROID_ENABLED)
	if OS.has_feature("macos") or OS.has_feature("android"):
		return DisplayServer.screen_get_max_scale()
	#else
	var screen = DisplayServer.window_get_current_screen()
	
	if DisplayServer.screen_get_size(screen) == Vector2i():
		return 1.0
		
	var smallest_dimension = min(DisplayServer.screen_get_size(screen).x, DisplayServer.screen_get_size(screen).y)
	if DisplayServer.screen_get_dpi(screen) >= 192 and smallest_dimension >= 1400:
		return 2.0
	elif smallest_dimension >= 1700:
		return 1.5
	elif smallest_dimension <= 800:
		return 0.75
	return 1.0
	#endif

func fract(value):
	return value - floor(value)

func set_error_count(p_error_count: int):
	error_button.set_text(str(p_error_count))
	error_button.set_visible(p_error_count > 0)
	if !p_error_count:
		_set_show_errors_panel(false)
		
func _set_show_errors_panel(p_show: bool):
	is_errors_panel_opened = p_show
	emit_signal("show_errors_panel", p_show)
	
func set_warning_count(p_warning_count: int):
	warning_button.set_text(str(p_warning_count))
	warning_button.set_visible(p_warning_count > 0)
	if !p_warning_count:
		_set_show_warnings_panel(false)
		
func _set_show_warnings_panel(p_show: bool):
	is_warnings_panel_opened = p_show
	emit_signal("show_warnings_panel", p_show)
	
func _toggle_scripts_pressed() -> void:
	toggle_scripts_pressed.emit()
	update_toggle_scripts_button()
	
func is_scripts_panel_toggled():
	return false #TODO
	
func update_toggle_scripts_button():
	if is_layout_rtl():
		toggle_scripts_button.icon = get_theme_icon("Forward" if is_scripts_panel_toggled() else "Back")
	else:
		toggle_scripts_button.icon = get_theme_icon("Back" if is_scripts_panel_toggled() else "Forward")
	toggle_scripts_button.tooltip_text = "%s (%s)" % ["Toggle Scripts Panel", "Ctrl+BackSlash"]

func _error_pressed(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb = event as InputEventMouseButton
		if mb.is_pressed() and mb.get_button_index() == MOUSE_BUTTON_LEFT:
			goto_error()
			
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
	
func _zoom_popup_id_pressed(p_idx: int) -> void:
	_zoom_to(zoom_button.get_popup().get_item_metadata(p_idx))
	
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
	var new_font_size = round(zoom_factor * neutral_font_size)
	
	zoom_button.set_text(str(round(zoom_factor * 100)) + " %")
	
	if text_editor.has_theme_font_size_override("font_size"):
		text_editor.remove_theme_font_size_override("font_size")
		
	text_editor.add_theme_font_size_override("font_size", new_font_size)
	
#func ED_IS_SHORTCUT(p_name: String, p_event: InputEvent) -> bool:
	#return true# 
	
func _text_editor_gui_input(p_event: InputEvent) -> void:
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
				
	if p_event is InputEventMagnifyGesture:
		var magnify_gesture = p_event as InputEventMagnifyGesture
		_zoom_to(zoom_factor * pow(magnify_gesture.get_factor(), 0.25))
		accept_event()
		return;
		
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
				
func _zoom_in():
	var s = text_editor.get_theme_font_size("font_size")
	_zoom_to(zoom_factor * (s + max(1.0, EDSCALE)) / s)
	
func _zoom_out():
	var s = text_editor.get_theme_font_size("font_size")
	_zoom_to(zoom_factor * (s - max(1.0, EDSCALE)) / s)
	
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
	
	# TODO
	#if find_replace_bar:
		#if (!find_replace_bar.line_col_changed_for_result) {
			#find_replace_bar.needs_to_count_results = true
		#}
#
		#find_replace_bar.line_col_changed_for_result = false


func _text_changed() -> void:
	if code_complete_enabled:# and text_editor.is_insert_text_operation():
		code_complete_timer_line = text_editor.get_caret_line()
		code_complete_timer.start()
		
	idle.start()
	text_changed.emit()
	# TODO
	#if find_replace_bar:
		#find_replace_bar.needs_to_count_results = true

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


func _text_changed_idle_timeout() -> void:
	pass # Replace with function body.


func _code_complete_timer_timeout() -> void:
	pass # Replace with function body.
