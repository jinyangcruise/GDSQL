@tool
extends VBoxContainer

## 通过该信号可以把需要在检查器中查看的对象发送给EditorInterface
signal inspect_object(object: Object, for_property: String, inspector_only: bool)

@onready var header: MarginContainer = $VBoxContainer/Header
@onready var header_col_model: Control = $HSplitContainer/HeaderColModel
@onready var v_box_container: VBoxContainer = $VBoxContainer/ScrollContainer/VBoxContainer
#@onready var row_model: HBoxContainer = $Models/RowModel
@onready var row_panel_container: PanelContainer = $Models/RowPanelContainer
@onready var label_model: Label = $Models/LabelModel
@onready var texture_rect_model: TextureRect = $Models/TextureRectModel
@onready var check_box_model: CheckBox = $Models/CheckBoxModel


@export var show_raw_data: bool = false
@export var editable: bool = true

@export var colums: Array[String]:
	set(val):
		colums = val
		if is_node_ready():
			reset_header()
			
@export var datas: Array[Array]:
	set(val):
		datas = val
		if is_node_ready():
			clear_rows()
			for data in datas:
				var d = data.duplicate()
				add_row(d)
		
		
var buttons: Array[Button] = []
var controls: Array = []

func _ready() -> void:
	reset_header()
	await await create_tween().tween_callback(func(): return).set_delay(1).finished
	datas = datas
	for i in 50:
		await create_tween().tween_callback(func(): realign_rows()).set_delay(0.1).finished
	

func reset_header():
	buttons.clear()
	controls.clear()
	
	if header.get_child_count() > 0:
		var h = header.get_child(0)
		header.remove_child(h)
		h.queue_free()
	
	var fake_columns = [""]
	fake_columns.append_array(colums)
	fake_columns.push_back("")
	
	var parent = header
	for i in fake_columns.size():
		var c: HSplitContainer = header_col_model.duplicate()
		parent.add_child(c)
		var split_container_dragger = c.get_child(c.get_child_count(true)-1, true)
		split_container_dragger.gui_input.connect(_on_dragger_gui_input.bind(c))
		var button = c.get_child(0)
		var control = c.get_child(1)
		if i == 0:
			button.hide()
			control.size_flags_stretch_ratio = 10000
			c.dragger_visibility = HSplitContainer.DRAGGER_HIDDEN_COLLAPSED
		elif i == fake_columns.size() - 2:
			button.size_flags_stretch_ratio = 10000
			c.dragger_visibility = HSplitContainer.DRAGGER_HIDDEN_COLLAPSED
		else:
			control.size_flags_stretch_ratio = fake_columns.size() - i - 2
			
		if i == fake_columns.size() - 1:
			button.hide()
			
		button.text = fake_columns[i]
		parent = control
		buttons.push_back(button)
		if i < fake_columns.size() - 1:
			controls.push_back(control)
		
		c.dragged.connect(_on_header_col_model_dragged.bind(c))
		
	# 把最后一个空control删掉，免得占空间
	parent.queue_free()
	clear_rows()
	
func _on_header_col_model_dragged(_offset: int, h_split_container: HSplitContainer) -> void:
	#var child_button: Button = h_split_container.get_child(0)
	var child_control = h_split_container.get_child(1)
	child_control.custom_minimum_size.x = 1
	await get_tree().process_frame
	await get_tree().process_frame
	var next_h_split_container: HSplitContainer = child_control.get_child(0)
	next_h_split_container.size.x = child_control.size.x
	realign_rows()
	
func add_row(data: Array):
	var a_row = row_panel_container.duplicate()
	v_box_container.add_child(a_row)
	a_row.show()
	a_row.gui_input.connect(_on_row_gui_input.bind(a_row, data.duplicate()))
	data.insert(0, "")
	data.push_back("")
	var control: Control
	for i in data.size():
		var handled = false
		if not show_raw_data:
			match typeof(data[i]):
				TYPE_BOOL:
					handled = true
					control = check_box_model.duplicate()
					control.button_pressed = data[i]
					#control.disabled = true # 需要通过检查器inspector来修改 # 也不用专门设置了，因为a_row的mouse_filter是stop
				TYPE_STRING, TYPE_STRING_NAME:
					handled = true
					control = label_model.duplicate()
					control.text = data[i]
				TYPE_OBJECT:
					if data[i] is Texture:
						handled = true
						var editor_resource_picker := EditorResourcePicker.new()
						editor_resource_picker.mouse_filter = Control.MOUSE_FILTER_IGNORE
						editor_resource_picker.propagate_call("set_mouse_filter", [Control.MOUSE_FILTER_IGNORE])
						editor_resource_picker.base_type = data[i].get_class()
						editor_resource_picker.edited_resource = data[i].duplicate()
						editor_resource_picker.editable = false
						control = editor_resource_picker
						#control = texture_rect_model.duplicate()
						#control.texture = data[i]
					## TODO 其他类型待添加，例如音频
					
		if not handled:
			control = label_model.duplicate()
			control.text = var_to_str(data[i])
			
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		#control.set_meta("data", data[i])
		#control.gui_input.connect(_on_label_model_gui_input.bind(control))
		a_row.get_child(0).add_child(control)
		if i == 0 or i == data.size() - 1:
			control.hide()
		control.size_flags_stretch_ratio = buttons[i].size.x + 4 # HSplitContainer间隔为8，两边各取一半
		
func clear_rows():
	while v_box_container.get_child_count() > 0:
		var r = v_box_container.get_child(0)
		v_box_container.remove_child(r)
		r.queue_free()
		
func realign_rows():
	for row in v_box_container.get_children():
		for i in row.get_child(0).get_child_count():
			row.get_child(0).get_child(i).size_flags_stretch_ratio = buttons[i].size.x + 4
		
func _on_button_pressed() -> void:
	realign_rows()
#	print_tree_pretty()
#	for button in buttons:
#		var parent = button.get_parent()
#		var splitCol = parent.get_parent()
#		printt(button.size_flags_horizontal, button.size.x, splitCol, splitCol.size_flags_horizontal, splitCol.size.x)
		
func _on_dragger_gui_input(event: InputEvent, _split_container: HSplitContainer):
	# 让control不要自动填充
	if event is InputEventMouseButton:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			for control in controls:
				if control.size_flags_horizontal == Control.SIZE_EXPAND_FILL:
					control.custom_minimum_size = control.size
					control.size_flags_horizontal = Control.SIZE_FILL
		else:
			for control in controls:
				control.custom_minimum_size = control.size
			


#func _on_texture_button_model_button_up(node: TextureButton) -> void:
	#if not editable:
		#return
	#var editor_file_dialog = EditorFileDialog.new()
	#editor_file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	#editor_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	#editor_file_dialog.file_selected.connect(func(path: String):
		#node.texture_normal = load(path)
	#)
	#add_child(editor_file_dialog)
	#editor_file_dialog.popup_centered_ratio(0.5)
	#editor_file_dialog.close_requested.connect(func():
		#editor_file_dialog.queue_free()
	#)


func _on_row_gui_input(event: InputEvent, row: Control, data: Array) -> void:
	if not editable:
		return
	if not event is InputEventMouseButton:
		return
		
	if not (event as InputEventMouseButton).double_click:
		return
		
	var save_button = Button.new()
	save_button.text = "save"
	var obj = DictionaryObject.new({
		"id": randi(),
		"name": "jinyang",
		"good": true,
		"level": 20,
		"age": 33,
		"title": preload("res://resource/bitmap/icon/skill/icon_skill7.s110.png"),
	}, {
		"title": {
			"hint": PROPERTY_HINT_RESOURCE_TYPE,
			"hint_string": "Texture2D"
		}
	})
	inspect_object.emit(obj, "", false)


func _on_row_panel_container_focus_entered() -> void:
	var style_box: StyleBoxFlat = row_panel_container.get_theme_stylebox("panel")
	style_box.bg_color.a = 0.788


func _on_row_panel_container_focus_exited() -> void:
	var style_box: StyleBoxFlat = row_panel_container.get_theme_stylebox("panel")
	style_box.bg_color.a = 0.0
