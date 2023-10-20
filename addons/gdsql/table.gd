@tool
extends VBoxContainer

signal row_clicked(row_index: int, mouse_button_index: int, data)
signal row_deleted(row_index: int, data)

var mgr: GDSQLWorkbenchManagerClass = Engine.get_singleton("GDSQLWorkbenchManager")

@onready var header: MarginContainer = $VBoxContainer/Header
@onready var header_col_model: Control = $HSplitContainer/HeaderColModel
@onready var v_box_container: VBoxContainer = $VBoxContainer/ScrollContainer/VBoxContainer
@onready var row_panel_container: PanelContainer = $Models/RowPanelContainer
@onready var label_model: Label = $Models/LabelModel
@onready var texture_rect_model: TextureRect = $Models/TextureRectModel
@onready var check_box_model: CheckBox = $Models/CheckBoxModel
@onready var scroll_container = $VBoxContainer/ScrollContainer
@onready var popup_menu_text = $PopupMenuText



## 表格是否可编辑（datas中的元素必须是DictionaryObject才有效）
@export var editable: bool = false

@export var support_delete_row: bool = false

## 每列的名称。注意：如果要正确显示tooltip，需要先设置column_tips，再设置columns
@export var columns: Array:
	set(val):
		columns = val
		if is_node_ready():
			# 与原先的表头数量一致，就不重绘，只修改文字显示
			if buttons.size() == columns.size() + 2:
				for i in columns.size():
					buttons[i+1].text = columns[i]
					if not column_tips.is_empty():
						buttons[i+1].tooltip_text = column_tips[i]
			else:
				reset_header()
			
## 表头tooltip
@export var column_tips: Array = []

## 每列的初始宽度比例。
## 第N个元素是X，表示第N列的宽度是后面宽度之和的1/X。
## 例如，第一个元素是20，表示第一列的宽度是后面宽度之和的1/20
@export var ratios: Array[float] = []
	
## 表格中的数据，datas中的元素可以是数组、字典或DictionaryObject。
## 如果要增量添加元素，请使用table.append_data(data)，避免重新对datas进行赋值，在数据量大时效率很低。
@export var datas: Array = []:
	set(val):
		datas = val
		if is_node_ready():
			clear_rows()
			for data in datas:
				add_row(data)
				
			if not _entered_tree:
				await tree_entered
			if is_inside_tree():
				for i in 50:
					await create_tween().tween_callback(func(): realign_rows()).set_delay(0.1).finished
		
var _entered_tree = false
## 表头
var buttons: Array[Button] = []
var controls: Array = []
var data_of_focused_row

func _ready() -> void:
	reset_header()
	await get_tree().process_frame
	datas = datas
	if is_inside_tree() and !datas.is_empty():
		for i in 50:
			await create_tween().tween_callback(func(): realign_rows()).set_delay(0.1).finished
	
func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		popup_menu_text.set_item_metadata(0, null)
		popup_menu_text.set_item_metadata(1, null)
		clear_header()
		clear_rows()
		datas = []
		data_of_focused_row = null
		# 下面3个清空的话会导致用户只能通过代码来设置这三个属性，不能通过检查器来设置
		#ratios.clear()
		#column_tips.clear()
		#columns.clear()
		mgr = null
	elif what == NOTIFICATION_ENTER_TREE:
		_entered_tree = true
	
func clear_header():
	# header是嵌套的，所以删除第一个就行
	if header.get_child_count() > 0:
		var h = header.get_child(0)
		header.remove_child(h)
		h.queue_free()

func reset_header():
	buttons.clear()
	controls.clear()
	clear_header()
	
	var fake_columns = [""]
	fake_columns.append_array(columns)
	fake_columns.push_back("")
	
	var parent = header
	for i in fake_columns.size():
		var c: HSplitContainer = header_col_model.duplicate()
		parent.add_child(c)
		var split_container_dragger = c.get_child(-1, true)
		split_container_dragger.gui_input.connect(_on_dragger_gui_input.bind(c), CONNECT_DEFERRED)
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
		
		c.dragged.connect(_on_header_col_model_dragged.bind(c), CONNECT_DEFERRED)
		
	# 把最后一个空control删掉，免得占空间
	parent.queue_free()
	clear_rows()
	
func _on_header_col_model_dragged(_offset: int, h_split_container: HSplitContainer) -> void:
	#var child_button: Button = h_split_container.get_child(0)
	var child_control = h_split_container.get_child(1)
	child_control.custom_minimum_size.x = 1
	await get_tree().process_frame
	var next_h_split_container: HSplitContainer = child_control.get_child(0)
	next_h_split_container.size.x = child_control.size.x
	realign_rows()
	
##region 增量操作
func append_data(a_data):
	datas.push_back(a_data)
	if is_node_ready():
		add_row(a_data)
		
func insert_data(pos: int, a_data):
	datas.insert(pos, a_data)
	if is_node_ready():
		add_row(a_data)
		if pos != v_box_container.get_child_count() - 1:
			v_box_container.move_child(v_box_container.get_child(-1), pos)
		
func remove_data_at(index: int, free_data: bool):
	if free_data and datas[index] is DictionaryObject:
		var data = datas[index]
		data.get_custom_display_control("Data Type").queue_free()
		data.get_custom_display_control("Hint").queue_free()
	datas.remove_at(index)
	if is_node_ready():
		var row = v_box_container.get_child(index)
		row.remove_meta("data")
		v_box_container.remove_child(row)
		row.queue_free()
		
func move_data(from: int, to: int):
	if from != to:
		var data = datas[from]
		datas.remove_at(from)
		datas.insert(to, data)
		if is_node_ready():
			var row = v_box_container.get_child(from)
			v_box_container.move_child(row, to)
##endregion
		
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
	a_row.set_meta("data", a_data)
	v_box_container.add_child(a_row)
	a_row.gui_input.connect(_on_row_gui_input.bind(a_row, a_data), CONNECT_DEFERRED)
	var style_box: StyleBoxFlat = a_row.get_theme_stylebox("panel").duplicate()
	a_row.add_theme_stylebox_override("panel", style_box)
	# add_child好像会导致之前的focus丢失
	if a_data == data_of_focused_row:
		highlight_row(a_row)
	#elif data_of_focused_row != null:
		#for i in v_box_container.get_children():
			#if i.get_meta("data") == data_of_focused_row:
				#highlight_row(i)
	data.insert(0, "")
	data.push_back("")
	for i in data.size():
		var control: Control
		var handled = false
		
		# 如果该数据提供了自定义显示控件，就直接使用
		if i > 0 and i < data.size() - 1 and a_data is Object and a_data.has_method("get_custom_display_control"):
			control = a_data.get_custom_display_control(columns[i-1])
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
				TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME:
					handled = true
					control = label_model.duplicate()
					control.text = str(data[i])
					control.tooltip_text = str(data[i])
					control.gui_input.connect(_label_gui_input.bind(control.text), CONNECT_DEFERRED)
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
			control.gui_input.connect(_label_gui_input.bind(control.text), CONNECT_DEFERRED)
			if i > 0 and i < data.size() - 1 and a_data is Object and a_data.has_method("set_update_callback"):
				var callback = func(new_value, control_ref: WeakRef):
					var ctl = control_ref.get_ref()
					if ctl:
						ctl.text = var_to_str(new_value)
				a_data.set_update_callback(columns[i-1], callback.bind(weakref(control))) # 绕这么一圈用弱引用是怕内存溢出;i-1是因为data前面比column多一个空值
			
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		#control.set_meta("data", data[i])
		#control.gui_input.connect(_on_label_model_gui_input.bind(control), CONNECT_DEFERRED)
		# 表格刷新时某些自定义控件可能需要重复使用，要去掉parent
		if control.get_parent() == null:
			a_row.get_child(0).add_child(control)
		else:
			control.reparent(a_row.get_child(0))
		if i == 0 or i == data.size() - 1:
			control.hide()
		control.size_flags_stretch_ratio = buttons[i].size.x + 4 # HSplitContainer间隔为8，两边各取一半
		
func clear_rows():
	while v_box_container.get_child_count() > 0:
		var r = v_box_container.get_child(0)
		r.remove_meta("data")
		v_box_container.remove_child(r)
		r.queue_free()
		
func realign_rows():
	if v_box_container == null:
		return
	for row in v_box_container.get_children():
		for i in row.get_child(0).get_child_count():
			row.get_child(0).get_child(i).size_flags_stretch_ratio = buttons[i].size.x + 4
		
func _on_button_pressed() -> void:
	#realign_rows()
#	print_tree_pretty()
#	for button in buttons:
#		var parent = button.get_parent()
#		var splitCol = parent.get_parent()
#		printt(button.size_flags_horizontal, button.size.x, splitCol, splitCol.size_flags_horizontal, splitCol.size.x)
	test(header)
	printt("---------------------------")
	test($VBoxContainer/ScrollContainer/VBoxContainer)
	
func test(container):
	if container.get_child_count() == 0:
		printt(container, container.size, container.custom_minimum_size)
	for child in container.get_children():
		test(child)
		
func _on_dragger_gui_input(_event: InputEvent, _split_container: HSplitContainer):
	return
	## 让control不要自动填充
	#if event is InputEventMouseButton:
		#if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			#for control in controls:
				#if control.size_flags_horizontal == Control.SIZE_EXPAND_FILL:
					#control.custom_minimum_size = control.size
					#control.size_flags_horizontal = Control.SIZE_FILL
		#else:
			#for control in controls:
				#control.custom_minimum_size = control.size
	
func _on_resized():
	realign_rows()
	
#func _on_texture_button_model_button_up(node: TextureButton) -> void:
	#if not editable:
		#return
	#var editor_file_dialog = EditorFileDialog.new()
	#editor_file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	#editor_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	#editor_file_dialog.file_selected.connect(func(path: String):
		#node.texture_normal = load(path)
	#, CONNECT_DEFERRED)
	#add_child(editor_file_dialog)
	#editor_file_dialog.popup_centered_ratio(0.5)
	#editor_file_dialog.close_requested.connect(func():
		#editor_file_dialog.queue_free()
	#, CONNECT_DEFERRED)


func _on_row_gui_input(event: InputEvent, row_panel, source_data) -> void:
	var emit_click = func():
		if event is InputEventMouseButton and \
			(event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT):
			highlight_row(row_panel)
			row_clicked.emit(datas.find(source_data), event.button_index, source_data)
			
	if not editable:
		emit_click.call()
		return

	if not event is InputEventMouseButton:
		#emit_click.call()
		return

	#if not (event as InputEventMouseButton).double_click:
		#return
		
	if source_data is Object and editable and event is InputEventMouseButton and \
			(event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT):
		EditorInterface.inspect_object(source_data)
		
	emit_click.call()

func highlight_row(row_panel: PanelContainer) -> void:
	var style_box: StyleBoxFlat = row_panel.get_theme_stylebox("panel")
	style_box.bg_color.a = 0.788
	# 清空兄弟节点的背景色。这个逻辑不放在focus_exited里是因为这两个信号的发生顺序，是先exited，再entered
	for i in v_box_container.get_children():
		if i != row_panel:
			var style_box_1: StyleBoxFlat = i.get_theme_stylebox("panel")
			style_box_1.bg_color.a = 0.0
			
	data_of_focused_row = row_panel.get_meta("data", null)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and \
		row_panel.get_rect().has_point(v_box_container.get_local_mouse_position()):
		popup_menu_text.position = DisplayServer.mouse_get_position() # 为什么要用这个方法获取鼠标位置？不知道……在插件中该方法是正确的
		popup_menu_text.set_item_metadata(1, row_panel.get_meta("data"))
		if support_delete_row:
			popup_menu_text.set_item_disabled(1, false)
		else:
			popup_menu_text.set_item_disabled(1, true)
		popup_menu_text.popup()
	else:
		popup_menu_text.set_item_disabled(1, true)
		
func row_grab_focus(row: int):
	if v_box_container.get_child_count() > row:
		highlight_row(v_box_container.get_child(row))
		
		if datas[row] is Object and editable:
			EditorInterface.inspect_object(datas[row])
			
func scroll_to_bottom():
	var v_scroll_bar = scroll_container.get_v_scroll_bar() as VScrollBar
	await get_tree().create_timer(0.1).timeout
	v_scroll_bar.value = v_scroll_bar.max_value

func _label_gui_input(event: InputEvent, content: String):
	if event is InputEventMouseButton and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		popup_menu_text.position = DisplayServer.mouse_get_position() # 为什么要用这个方法获取鼠标位置？不知道……在插件中该方法是正确的
		popup_menu_text.set_item_metadata(0, content)
		if support_delete_row and popup_menu_text.get_item_metadata(1) != null:
			popup_menu_text.set_item_disabled(1, false)
		else:
			popup_menu_text.set_item_disabled(1, true)
		popup_menu_text.popup()

func _on_popup_menu_text_index_pressed(index):
	match popup_menu_text.get_item_text(index):
		"Copy":
			DisplayServer.clipboard_set(popup_menu_text.get_item_metadata(index))
		"Delete":
			var data = popup_menu_text.get_item_metadata(index)
			var pos = datas.find(data)
			datas.remove_at(pos)
			datas = datas
			row_deleted.emit(pos, data)
			
	popup_menu_text.set_item_metadata(index, null)
