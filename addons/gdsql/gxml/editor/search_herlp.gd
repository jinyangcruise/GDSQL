@tool
extends ConfirmationDialog

signal search_help_insert(content: String)

@onready var search_box: LineEdit = $vbox/hbox/search_box
@onready var case_sensitive_button: Button = $vbox/hbox/case_sensitive_button
@onready var filter_combo: OptionButton = $vbox/hbox/filter_combo
@onready var results_tree: Tree = $vbox/results_tree
@onready var hide_deprecated: CheckButton = $vbox/hbox/hide_deprecated


var EDSCALE: float = EditorInterface.get_editor_scale()

func _ready() -> void:
	search_box.custom_minimum_size.x = 200 * EDSCALE
	register_text_enter(search_box)
	
	case_sensitive_button.icon = get_theme_icon("MatchCase", "EditorIcons")
	
	filter_combo.custom_minimum_size.x = 200 * EDSCALE
	
	results_tree.clear()
	results_tree.set_column_title(0, tr("Name"))
	results_tree.set_column_clip_content(0, true)
	results_tree.set_column_title(1, tr("Description"))
	results_tree.set_column_clip_content(1, true)
	results_tree.set_column_custom_minimum_width(1, int(350 * EDSCALE))
	results_tree.set_column_title(2, tr("Member Type"))
	results_tree.set_column_expand(2, false)
	results_tree.set_column_custom_minimum_width(2, int(150 * EDSCALE))
	results_tree.set_column_clip_content(2, true)
	results_tree.custom_minimum_size.y = 100 * EDSCALE
	results_tree.item_selected.connect(
		Callable(get_ok_button(), "set_disabled").bind(false))
		
	var root = results_tree.create_item()
	for item_name in GDSQL.GBatisMapperRule.rule:
		var item = results_tree.create_item(root)
		item.set_meta("is_base", true)
		item.set_icon(0, get_theme_icon("Object", "EditorIcons"))
		item.set_text(0, item_name)
		item.set_icon(2, get_theme_icon("Object", "EditorIcons"))
		item.set_text(2, tr("Class"))
		if GDSQL.GBatisMapperRule.rule[item_name].deprecated:
			item.set_meta("deprecated", true)
			item.set_icon(1, get_theme_icon("StatusError", "EditorIcons"))
			item.set_tooltip_text(1, tr("This class is marked as deprecated."))
			item.collapsed = true
		var props_info = GDSQL.GBatisMapperRule.rule[item_name]["attr_list"]
		for prop in props_info:
			var p_item = results_tree.create_item(item)
			p_item.set_meta("is_attr", true)
			p_item.set_meta("parent", item_name)
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
			
		var sub_elements = GDSQL.GBatisMapperRule.rule[item_name]["valid_child"]
		for element in sub_elements:
			var e_item = results_tree.create_item(item)
			e_item.set_meta("is_child", true)
			e_item.set_meta("parent", item_name)
			e_item.set_icon(0, get_theme_icon("Object", "EditorIcons"))
			e_item.set_text(0, element)
			e_item.set_icon(2, get_theme_icon("Object", "EditorIcons"))
			e_item.set_text(2, tr("Children"))
			
	_on_hide_deprecated_toggled(hide_deprecated.button_pressed)
	
	
func popup_search(search: String = ""):
	if search != "":
		search_box.text = search
		search_box.text_changed.emit(search)
		search_box.select_all()
	popup_centered_ratio(0.5)
	
func EDITOR_GET(n: String):
	return EditorInterface.get_editor_settings().get_setting(n)
	
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_ENTER_TREE, NOTIFICATION_THEME_CHANGED:
			EDSCALE = EditorInterface.get_editor_scale()
			
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
			
			
func _search_box_text_changed(_new_text: String) -> void:
	_update_results()
	
func _update_results() -> void:
	var a_hide_deprecated = hide_deprecated.button_pressed
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
				if a_hide_deprecated and c_item.get_meta("deprecated", false) == true:
					c_item.visible = false
				elif c_item.get_text(0).to_lower().contains(search_str):
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
		
func _filter_combo_item_selected(_index: int) -> void:
	pass # Replace with function body.
	
func _confirmed() -> void:
	var selected = null
	var arr_base = {}
	var arr_attr = [] # stand alone
	var arr_child = [] # stand alone
	while true:
		selected = results_tree.get_next_selected(selected)
		if not selected:
			break
		if selected.get_meta("is_base", false):
			var curr_base = selected.get_text(0)
			arr_base[curr_base] = {"attrs": [], "children": []}
			for i in GDSQL.GBatisMapperRule.rule[curr_base].attr_list:
				if GDSQL.GBatisMapperRule.rule[curr_base].attr_list[i].required:
					arr_base[curr_base].attrs.push_back(i)
		elif selected.get_meta("is_attr", false):
			if arr_base.has(selected.get_meta("parent")):
				if not arr_base[selected.get_meta("parent")].attrs.\
				has(selected.get_text(0)):
					arr_base[selected.get_meta("parent")].attrs.\
						push_back(selected.get_text(0))
			else:
				arr_attr.push_back(
					[selected.get_text(0), selected.get_parent().get_text(0)])
		elif selected.get_meta("is_child", false):
			if arr_base.has(selected.get_meta("parent")):
				arr_base[selected.get_meta("parent")].children.\
					push_back(selected.get_text(0))
			else:
				arr_child.push_back(selected.get_text(0))
				
	var s = []
	for i in arr_base:
		if not s.is_empty():
			s.push_back("\n\t")
		s.push_back("<%s" % i)
		for j in arr_base[i].attrs:
			s.push_back(' %s="%s"' % [j, 
				GDSQL.GBatisMapperRule.rule[i].attr_list[j].default])
		s.push_back(">")
		for j in arr_base[i].children:
			var c = j.replace("*", "").replace("?", "").replace("+", "")
			s.push_back('\n\t\t<%s/>' % c)
		s.push_back("\n\t</%s>" % i)
		
	var s1 = []
	for i in arr_attr:
		s1.push_back('%s="%s"' % [i[0], 
			GDSQL.GBatisMapperRule.rule[i[1]].attr_list[i[0]].default])
	s.push_back(" ".join(s1))
	
	var s2 = []
	for i in arr_child:
		s2.push_back('<%s/>' % i)
	s.push_back("\n\t\t".join(s2))
	
	var insert = "".join(s)
	if insert != "":
		search_help_insert.emit(insert)
	hide()
	
func _on_hide_deprecated_toggled(_toggled_on: bool) -> void:
	_update_results()
	
func _on_visibility_changed() -> void:
	if visible:
		search_box.grab_focus()
