@tool
extends VBoxContainer

const __Singletons := preload("res://addons/gdsql/autoload/singletons.gd")
const __Manager := preload("res://addons/gdsql/singletons/gdsql_workbench_manager.gd")

@onready var header: MarginContainer = $VBoxContainer/Header
@onready var header_col_model: Control = $HSplitContainer/HeaderColModel
@onready var v_box_container: VBoxContainer = $VBoxContainer/ScrollContainer/VBoxContainer
@onready var row_panel_container: PanelContainer = $Models/RowPanelContainer
@onready var label_model: Label = $Models/LabelModel
@onready var texture_rect_model: TextureRect = $Models/TextureRectModel
@onready var check_box_model: CheckBox = $Models/CheckBoxModel


## 表格是否可编辑（datas中的元素必须是DictionaryObject才有效）
@export var editable: bool = false

## 每列的名称
@export var columns: Array[String]:
	set(val):
		columns = val
		if is_node_ready():
			reset_header()
			
## 表头tooltip
@export var column_tips: Array[String] = []

## 每列的初始宽度比例
## 第N个元素是X，表示第N列的宽度是后面宽度之和的1/X
## 例如，第一个元素是20，表示第一列的宽度是后面宽度之和的1/20
@export var ratios: Array[float] = []
	
## 表格中的数据，datas中的元素可以是数组、字典或DictionayObject
@export var datas: Array:
	set(val):
		datas = val
		if is_node_ready():
			clear_rows()
			for data in datas:
				add_row(data)
		
		
var buttons: Array[Button] = []
var controls: Array = []

func _ready() -> void:
	reset_header()
	await get_tree().process_frame
	datas = datas
	if is_inside_tree() and !datas.is_empty():
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
	fake_columns.append_array(columns)
	fake_columns.push_back("")
	
	var parent = header
	for i in fake_columns.size():
		var c: HSplitContainer = header_col_model.duplicate()
		parent.add_child(c)
		var split_container_dragger = c.get_child(c.get_child_count(true)-1, true)
		split_container_dragger.gui_input.connect(_on_dragger_gui_input.bind(c))
		var button = c.get_child(0) as Button
		var control = c.get_child(1)
		if i == 0:
			button.hide()
			control.size_flags_stretch_ratio = 10000
			c.dragger_visibility = HSplitContainer.DRAGGER_HIDDEN_COLLAPSED
		elif i == fake_columns.size() - 2:
			button.size_flags_stretch_ratio = 10000
			c.dragger_visibility = HSplitContainer.DRAGGER_HIDDEN_COLLAPSED
			if not column_tips.is_empty():
				button.tooltip_text = column_tips[i-1]
		elif i == fake_columns.size() - 1:
			button.size_flags_stretch_ratio = 1
		else:
			if not column_tips.is_empty():
				button.tooltip_text = column_tips[i-1]
				
			if ratios.size() > i - 1:
				control.size_flags_stretch_ratio = ratios[i - 1]
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
	
func add_row(a_data):
	var data: Array
	if a_data is Array:
		data = a_data.duplicate()
		if columns.is_empty():
			for i in data.size():
				columns.push_back("#%d" % i)
	elif a_data is Dictionary:
		data = []
		if columns.is_empty():
			columns = []
			for key in a_data:
				columns.push_back(key)
				data.push_back(a_data[key])
		else:
			for key in columns:
				data.push_back(a_data[key])
	elif a_data is DictionaryObject:
		data = []
		if columns.is_empty():
			columns = []
			for info in a_data._get_property_list():
				columns.push_back(info["name"])
				data.push_back(a_data.get(info["name"]))
		else:
			for key in columns:
				data.push_back(a_data.get(key))
				
	var a_row = row_panel_container.duplicate()
	v_box_container.add_child(a_row)
	a_row.gui_input.connect(_on_row_gui_input.bind(a_data))
	a_row.focus_entered.connect(_on_row_panel_container_focus_entered.bind(a_row))
	a_row.focus_exited.connect(_on_row_panel_container_focus_exited.bind(a_row))
	var style_box: StyleBoxFlat = a_row.get_theme_stylebox("panel").duplicate()
	a_row.add_theme_stylebox_override("panel", style_box)
	data.insert(0, "")
	data.push_back("")
	var control: Control
	for i in data.size():
		var handled = false
		
		# 如果该数据提供了自定义显示控件，就直接使用
		if i > 0 and i < data.size() - 1 and a_data is Object and a_data.has_method("get_custom_display_control_duplicate"):
			control = a_data.get_custom_display_control_duplicate(columns[i-1])
			handled = control != null
			
		# 否则，用表格自带的显示控件
		if not handled:
			match typeof(data[i]):
				TYPE_BOOL:
					handled = true
					control = check_box_model.duplicate()
					control.button_pressed = data[i]
					if i > 0 and i < data.size() - 1 and a_data is Object and a_data.has_method("set_update_callback"):
						var callback = func(new_value, control_ref: WeakRef):
							var ctl = control_ref.get_ref()
							if ctl:
								ctl.button_pressed = new_value
						a_data.set_update_callback(columns[i-1], callback.bind(weakref(control))) # 绕这么一圈用弱引用是怕内存溢出;i-1是因为data前面比column多一个空值
				TYPE_STRING, TYPE_STRING_NAME:
					handled = true
					control = label_model.duplicate()
					control.text = data[i]
					if i > 0 and i < data.size() - 1 and a_data is Object and a_data.has_method("set_update_callback"):
						var callback = func(new_value, control_ref: WeakRef):
							var ctl = control_ref.get_ref()
							if ctl:
								ctl.text = new_value
						a_data.set_update_callback(columns[i-1], callback.bind(weakref(control))) # 绕这么一圈用弱引用是怕内存溢出;i-1是因为data前面比column多一个空值
				TYPE_OBJECT:
					if data[i] is Resource:
						handled = true
						var editor_resource_picker := EditorResourcePicker.new()
						editor_resource_picker.mouse_filter = Control.MOUSE_FILTER_IGNORE
						editor_resource_picker.propagate_call("set_mouse_filter", [Control.MOUSE_FILTER_IGNORE])
						editor_resource_picker.base_type = "Resource"
						editor_resource_picker.edited_resource = data[i]
						editor_resource_picker.editable = false
						control = editor_resource_picker
						if i > 0 and i < data.size() - 1 and a_data is Object and a_data.has_method("set_update_callback"):
							var callback = func(new_value, control_ref: WeakRef):
								var ctl = control_ref.get_ref()
								if ctl:
									ctl.edited_resource = new_value
							a_data.set_update_callback(columns[i-1], callback.bind(weakref(control))) # 绕这么一圈用弱引用是怕内存溢出;i-1是因为data前面比column多一个空值
						#control = texture_rect_model.duplicate()
						#control.texture = data[i]
					## TODO 可能需要添加其他有必要预览的类型
				
		if not handled:
			control = label_model.duplicate()
			control.text = var_to_str(data[i])
			if i > 0 and i < data.size() - 1 and a_data is Object and a_data.has_method("set_update_callback"):
				var callback = func(new_value, control_ref: WeakRef):
					var ctl = control_ref.get_ref()
					if ctl:
						ctl.text = var_to_str(new_value)
				a_data.set_update_callback(columns[i-1], callback.bind(weakref(control))) # 绕这么一圈用弱引用是怕内存溢出;i-1是因为data前面比column多一个空值
			
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		#control.set_meta("data", data[i])
		#control.gui_input.connect(_on_label_model_gui_input.bind(control))
		# 表格刷新时某些自定义控件可能需要重复使用，要去掉parent
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


func _on_row_gui_input(event: InputEvent, source_data) -> void:
	if not editable:
		return

	if not event is InputEventMouseButton:
		return

	#if not (event as InputEventMouseButton).double_click:
		#return
		
	if source_data is Object and editable:
		var mgr: __Manager = __Singletons.instance_of(__Manager, self)
		mgr.editor_interface.inspect_object(source_data, "", false)

func _on_row_panel_container_focus_entered(row_panel: PanelContainer) -> void:
	var style_box: StyleBoxFlat = row_panel.get_theme_stylebox("panel")
	style_box.bg_color.a = 0.788


func _on_row_panel_container_focus_exited(row_panel: PanelContainer) -> void:
	var style_box: StyleBoxFlat = row_panel.get_theme_stylebox("panel")
	style_box.bg_color.a = 0.0
	
