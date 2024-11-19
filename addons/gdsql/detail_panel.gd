@tool
extends PanelContainer

@onready var texture_rect: TextureRect = $TextureRect
@onready var grid_container: GridContainer = $GridContainer
@onready var check_box_container: MarginContainer = $CheckBoxContainer
@onready var check_box: CheckBox = $CheckBoxContainer/CheckBox



@onready var label_model: Label = $Models/LabelModel
@onready var texture_rect_model: TextureRect = $Models/TextureRectModel
@onready var check_box_model: CheckBox = $Models/CheckBoxModel

const DETAIL_PANEL_CHECKED = preload("res://addons/gdsql/detail_panel_checked.stylebox")
const DETAIL_PANEL_UNCHECKED = preload("res://addons/gdsql/detail_panel_unchecked.stylebox")
const DETAIL_PANEL_NORMAL_CHECKED = preload("res://addons/gdsql/detail_panel_normal_checked.stylebox")
const DETAIL_PANEL_NORMAL_UNCHECKED = preload("res://addons/gdsql/detail_panel_normal_unchecked.stylebox")

var status: String:
	set(val):
		status = val
		if status == "normal_checked":
			add_theme_stylebox_override("panel", DETAIL_PANEL_NORMAL_CHECKED)
		elif status == "normal_unchecked":
			add_theme_stylebox_override("panel", DETAIL_PANEL_NORMAL_UNCHECKED)
			
		if check_box:
			check_box.button_pressed = (status == "checked" or status == "normal_checked")
			
var show_check_box: bool = true:
	set(val):
		show_check_box = val
		if check_box:
			check_box.visible = show_check_box
			
var show_column_name: bool = true:
	set(val):
		show_column_name = val
		if grid_container:
			if show_column_name:
				grid_container.columns = 2
				for i in grid_container.get_children():
					i.show()
			else:
				grid_container.columns = 1
				var index = -1
				for i in grid_container.get_children():
					index += 1
					i.visible = index % 2 == 1
					
var show_column_value: bool = true:
	set(val):
		show_column_value = val
		if grid_container:
			grid_container.visible = show_column_value
			
var font_size: int = 14:
	set(val):
		font_size = val
		if grid_container:
			propagate_call_set_font_size(grid_container)
			
var processor: String = "":
	set(val):
		var changed = processor != val
		processor = val
		if grid_container and changed:
			set_datas(_data)
			
var _data: Dictionary

func propagate_call_set_font_size(node: Node):
	if node is Control:
		node.add_theme_font_size_override("font_size", font_size)
	for i in node.get_children():
		propagate_call_set_font_size(i)
		
func _ready() -> void:
	status = status
	show_check_box = show_check_box
	show_column_name = show_column_name
	show_column_value = show_column_value
	font_size = font_size
	processor = processor
	
func set_datas(data: Dictionary):
	# processor
	var processor_obj
	if processor != "":
		var script = GDSQLUtils.gdscript
		script.source_code = "extends Object\n%s" % processor
		var err = script.reload()
		if err != OK:
			push_error("processor wrong! err: %s" % error_string(err))
			printt(processor)
			return null
			
		processor_obj = script.new()
		assert(processor_obj.has_method("process"), "processor must contain a method: process")
		
	_data = data
	while grid_container.get_child_count() > 0:
		var c = grid_container.get_child(0)
		grid_container.remove_child(c)
		c.queue_free()
		
	var arr_tool_tip = []
	for i in data:
		if data[i] is Texture2D and texture_rect.texture == null:
			texture_rect.texture = data[i]
		else:
			var l = label_model.duplicate()
			l.text = str(i)
			grid_container.add_child(l)
			var value = processor_obj.process(l.text, data[i]) if processor_obj else data[i]
			var control = get_control_by_data_type(value)
			grid_container.add_child(control)
			if control.tooltip_text != '':
				arr_tool_tip.push_back(str(i) + ": " + control.tooltip_text)
				
	if processor_obj:
		processor_obj.free()
	check_box_container.tooltip_text = '\n'.join(arr_tool_tip)
	show_column_name = show_column_name
	show_column_value = show_column_value
	font_size = font_size
	
func get_control_by_data_type(data) -> Control:
	var control: Control
	var handled = false
	match typeof(data):
		TYPE_BOOL:
			handled = true
			control = check_box_model.duplicate()
			control.button_pressed = data
			control.tooltip_text = str(data)
		TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME:
			handled = true
			control = label_model.duplicate()
			control.text = str(data)
			control.tooltip_text = split_for_tooltip(control.text)
		TYPE_OBJECT:
			if data is Resource:
				handled = true
				if data is Texture2D:
					var t_rect = TextureRect.new()
					t_rect.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN
					t_rect.texture = data
					t_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
					t_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
					t_rect.tooltip_text = \
						"%s\nType: %s\nSize: %s" % [data.resource_path, data.get_class(), data.get_size()]
					control = t_rect
				else:
					## 注意：EditorResourcePicker有些慢，如果数据量比较大，会很卡，所以尽可能把常用的类型单独处理，比如上面的Texture2D
					var editor_resource_picker := EditorResourcePicker.new()
					editor_resource_picker.mouse_default_cursor_shape = Control.CURSOR_FORBIDDEN
					#editor_resource_picker.mouse_filter = Control.MOUSE_FILTER_IGNORE
					#editor_resource_picker.propagate_call("set_mouse_filter", [Control.MOUSE_FILTER_IGNORE])
					editor_resource_picker.base_type = "Resource"
					editor_resource_picker.edited_resource = data
					editor_resource_picker.editable = false
					control = editor_resource_picker
			elif data is Control:
				handled = true
				control = data
			## TODO 可能需要添加其他有必要预览的类型
		
	if not handled:
		control = label_model.duplicate()
		control.text = var_to_str(data)
		control.tooltip_text = split_for_tooltip(control.text)
		
	return control
	
func split_for_tooltip(content: String) -> String:
	const l = 40
	var total_l = content.length()
	if total_l <= l:
		return content
	var arr = []
	var start = 0
	while true:
		if start >= total_l:
			break
		if start + l >= total_l:
			arr.push_back(content.substr(start, l))
		# 不要把单词分开，找到下一个空格
		else:
			if (0x4e00 <= content.unicode_at(start+l) and content.unicode_at(start+l) <= 0x9fff) or \
			content[start + l] in [" ", "\t", ",", ".", "?", "!", ":", ";", "/", "~", "，", "。", "？", "！", "：", "；"]:
				arr.push_back(content.substr(start, l))
			else:
				var ll = -1
				for i in [" ", "\t", ",", ".", "?", "!", ":", ";", "/", "~", "，", "。", "？", "！", "：", "；"]:
					ll = content.find(i, start + l)
					if ll != -1:
						break
				if ll == -1:
					arr.push_back(content.substr(start))
					break
				else:
					arr.push_back(content.substr(start, ll - start + 1))
					start = ll + 1
					continue
		if start + l >= total_l:
			break
		start += l
	return "\n".join(arr)


func _on_check_box_toggled(toggled_on: bool) -> void:
	match status:
		"normal_checked":
			add_theme_stylebox_override("panel", DETAIL_PANEL_NORMAL_CHECKED if toggled_on else DETAIL_PANEL_UNCHECKED)
		"normal_unchecked":
			add_theme_stylebox_override("panel", DETAIL_PANEL_CHECKED if toggled_on else DETAIL_PANEL_NORMAL_UNCHECKED)


func _on_check_box_container_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.is_pressed() and event.button_index == MOUSE_BUTTON_LEFT:
			check_box.button_pressed = !check_box.button_pressed

func commit():
	if get_theme_stylebox("panel") == DETAIL_PANEL_CHECKED:
		status = "normal_checked"
		check_box.button_pressed = true
	elif get_theme_stylebox("panel") == DETAIL_PANEL_UNCHECKED:
		status = "normal_unchecked"
		check_box.button_pressed = false

func revert():
	match status:
		"normal_checked":
			check_box.button_pressed = true
		"normal_unchecked":
			check_box.button_pressed = false

func get_change_status():
	var sb = get_theme_stylebox("panel")
	if sb == DETAIL_PANEL_NORMAL_CHECKED or sb == DETAIL_PANEL_NORMAL_UNCHECKED:
		return ""
	if sb == DETAIL_PANEL_CHECKED:
		return "add"
	if sb == DETAIL_PANEL_UNCHECKED:
		return "delete"
	push_error(false, "Inner error 240 in detail_panel.gd")
	return ""
