@tool
extends PanelContainer

@onready var texture_rect: TextureRect = $TextureRect
@onready var grid_container: GridContainer = $GridContainer
@onready var check_box: CheckBox = $CheckBox

@onready var label_model: Label = $Models/LabelModel
@onready var texture_rect_model: TextureRect = $Models/TextureRectModel
@onready var check_box_model: CheckBox = $Models/CheckBoxModel

var checked: bool:
	set(val):
		checked = val
		if check_box:
			check_box.button_pressed = val
			
var show_check_box: bool = true:
	set(val):
		show_check_box = val
		if check_box:
			check_box.visible = show_check_box
			
func _ready() -> void:
	checked = checked
	show_check_box = show_check_box
	
func set_datas(data: Dictionary):
	while grid_container.get_child_count() > 0:
		var c = grid_container.get_child(0)
		grid_container.remove_child(c)
		c.queue_free()
		
	for i in data:
		if data[i] is Texture2D and texture_rect.texture == null:
			texture_rect.texture = data[i]
		else:
			var l = label_model.duplicate()
			l.text = str(i)
			grid_container.add_child(l)
			grid_container.add_child(get_control_by_data_type(data[i]))
			
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
