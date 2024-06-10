@tool
extends ConfirmationDialog

@onready var search_box: LineEdit = $vbox/hbox/search_box
@onready var case_sensitive_button: Button = $vbox/hbox/case_sensitive_button
@onready var filter_combo: OptionButton = $vbox/hbox/filter_combo
@onready var results_tree: Tree = $vbox/results_tree
@onready var hide_deprecated: CheckButton = $vbox/hbox/hide_deprecated


var EDSCALE: float

func _ready() -> void:
	EDSCALE = get_display_scale()
	
	search_box.custom_minimum_size.x = 200 * EDSCALE
	register_text_enter(search_box)
	
	case_sensitive_button.icon = get_theme_icon("MatchCase", "EditorIcons")
	
	filter_combo.custom_minimum_size.x = 200 * EDSCALE
	
	results_tree.clear()
	results_tree.set_column_title(0, tr("Name"))
	results_tree.set_column_clip_content(0, true)
	results_tree.set_column_title(1, tr("Description"))
	results_tree.set_column_clip_content(1, true)
	results_tree.set_column_custom_minimum_width(1, 350 * EDSCALE)
	results_tree.set_column_title(2, tr("Member Type"))
	results_tree.set_column_expand(2, false)
	results_tree.set_column_custom_minimum_width(2, 150 * EDSCALE)
	results_tree.set_column_clip_content(2, true)
	results_tree.custom_minimum_size.y = 100 * EDSCALE
	results_tree.item_selected.connect(
		Callable(get_ok_button(), "set_disabled").bind(false))
		
	var root = results_tree.create_item()
	for item_name in GBatisMapperRule.rule:
		var item = results_tree.create_item(root)
		item.set_icon(0, get_theme_icon("Object", "EditorIcons"))
		item.set_text(0, item_name)
		item.set_icon(2, get_theme_icon("Object", "EditorIcons"))
		item.set_text(2, tr("Class"))
		if GBatisMapperRule.rule[item_name].deprecated:
			item.set_meta("deprecated", true)
			item.set_icon(1, get_theme_icon("StatusError", "EditorIcons"))
			item.set_tooltip_text(1, tr("This class is marked as deprecated."))
			item.collapsed = true
		var props_info = GBatisMapperRule.rule[item_name]["attr_list"]
		for prop in props_info:
			var p_item = results_tree.create_item(item)
			p_item.set_icon(0, get_theme_icon("MemberProperty", "EditorIcons"))
			p_item.set_text(0, prop)
			if not props_info[prop].support:
				p_item.set_meta("deprecated", true)
				p_item.set_icon(1, get_theme_icon("StatusError", "EditorIcons"))
				p_item.set_tooltip_text(1, tr("This member is marked as deprecated."))
			else:
				p_item.set_icon(1, get_theme_icon("StatusSuccess", "EditorIcons"))
				p_item.set_tooltip_text(1, props_info[prop].desc)
			p_item.set_text(1, props_info[prop].desc.replace("\n", ""))
			if props_info[prop].required:
				p_item.set_icon(2, get_theme_icon("CryptoKey", "EditorIcons"))
			else:
				p_item.set_icon(2, get_theme_icon("KeyValue", "EditorIcons"))
			p_item.set_text(2, tr("Property"))
			
		var sub_elements = GBatisMapperRule.rule[item_name]["valid_child"]
		for element in sub_elements:
			var e_item = results_tree.create_item(item)
			e_item.set_icon(0, get_theme_icon("Object", "EditorIcons"))
			e_item.set_text(0, element)
			e_item.set_icon(2, get_theme_icon("Object", "EditorIcons"))
			e_item.set_text(2, tr("Children"))
			
	_on_hide_deprecated_toggled(hide_deprecated.button_pressed)
		
		
func EDITOR_GET(n: String):
	return EditorInterface.get_editor_settings().get_setting(n)
	
func get_display_scale():
	var setting = EDITOR_GET("interface/editor/display_scale")
	match setting:
		0: return get_auto_display_scale()
		1: return 0.75
		2: return 1.0
		3: return 1.25
		4: return 1.5
		5: return 1.75
		6: return 2.0
		_: return EDITOR_GET("interface/editor/custom_display_scale")
		
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

func _search_box_gui_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key = event as InputEventKey
	match key.keycode:
		KEY_UP, KEY_DOWN, KEY_PAGEUP, KEY_PAGEDOWN:
			results_tree.grab_focus()
			push_input(key)
			search_box.accept_event()
			search_box.grab_focus()
			
			
func _search_box_text_changed(new_text: String) -> void:
	_update_results()


func _update_results() -> void:
	var hide_deprecated = hide_deprecated.button_pressed
	var search_str = search_box.text.to_lower()
	
	for item in results_tree.get_root().get_children():
		if search_str != "":
			if not item.get_text(0).to_lower().contains(search_str):
				item.visible = false
			else:
				item.visible = true
		else:
			item.visible = true
			
		if not item.visible:
			for c_item in item.get_children():
				if c_item.get_text(0).to_lower().contains(search_str):
					item.visible = true
					c_item.visible = true
				else:
					c_item.visible = false
		else:
			for c_item in item.get_children():
				c_item.visible = true
				
		if not item.visible:
			continue
			
		if item.get_meta("deprecated", false):
			item.visible = not hide_deprecated
			continue
		for p_item in item.get_children():
			if p_item.get_meta("deprecated", false):
				p_item.visible = not hide_deprecated
				
	if results_tree.get_selected():
		results_tree.scroll_to_item(results_tree.get_selected(), true)
		
func _filter_combo_item_selected(index: int) -> void:
	pass # Replace with function body.


func _confirmed() -> void:
	pass # Replace with function body.


func _on_hide_deprecated_toggled(toggled_on: bool) -> void:
	_update_results()


func _on_visibility_changed() -> void:
	if visible:
		search_box.grab_focus()
