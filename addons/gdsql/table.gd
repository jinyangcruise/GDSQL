@tool
extends VBoxContainer

signal row_clicked(row_index: int, mouse_button_index: int, data)
signal row_deleted(datas) # {index: data}

var mgr: GDSQLWorkbenchManagerClass = Engine.get_singleton("GDSQLWorkbenchManager")

@onready var header: MarginContainer = $VBoxContainer/Header
@onready var header_col_model: Control = $HSplitContainer/HeaderColModel
@onready var v_box_container: VBoxContainer = $VBoxContainer/ScrollContainer/VBoxContainer
@onready var row_panel_container: PanelContainer = $Models/RowPanelContainer
@onready var row_model = $Models/RowPanelContainer/RowModel
@onready var label_model: Label = $Models/LabelModel
@onready var texture_rect_model: TextureRect = $Models/TextureRectModel
@onready var check_box_model: CheckBox = $Models/CheckBoxModel
@onready var scroll_container = $VBoxContainer/ScrollContainer
@onready var popup_menu_text = $PopupMenuText
@onready var button_select_all = $Control/ButtonSelectAll
@onready var borders_container = $BordersContainer



## 表格是否可编辑（datas中的元素必须是DictionaryObject才有效）
@export var editable: bool = false

## 是否显示默认的右键菜单（包括copy、delete）
@export var show_menu: bool = false

## 是否支持从右键菜单delete行
@export var support_delete_row: bool = false

## 是否支持多行选择（高亮）
@export var support_multi_rows_selected: bool = false

## 是否显示外纵向框架1\2\3\4...
@export var show_frame: bool = false

## 每列的名称。注意：如果要正确显示tooltip，需要先设置column_tips，再设置columns
@export var columns: Array:
	set(val):
		columns = val
		if is_node_ready():
			# 与原先的表头数量一致，就不重绘，只修改文字显示
			if buttons.size() == columns.size() + 2 + int(show_frame):
				for i in columns.size():
					buttons[i+1+int(show_frame)].text = columns[i]
					if not column_tips.is_empty():
						buttons[i+1+int(show_frame)].tooltip_text = column_tips[i]
			else:
				reset_header()
				
@export var label_max_lines_visible: int = 1:
	set(val):
		label_max_lines_visible = val
		if label_model:
			label_model.max_lines_visible = val
			
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
				
			if editable:
				# 默认选中第一个
				#make_table_border(v_box_container.get_child(0))
				pass
				
			#if not _entered_tree:
				#await tree_entered
			#if is_inside_tree():
				#for i in 50:
					#await create_tween().tween_callback(func(): realign_rows()).set_delay(0.1).finished
		
var _entered_tree = false
## 表头
var buttons: Array[Button] = []
var controls: Array = []
var style_box_empty = StyleBoxEmpty.new()
# 最后focus的行
var last_focused_row
const HIGHTLIGHT_COLOR = Color(Color.MEDIUM_PURPLE, 0.788)
const CLICKED_COLOR = Color(Color.LIGHT_BLUE, 0.1)
#var data_of_focused_row
# 选框
var start_drag = false
var start_drag_with_ctrl = false
var selected_borders = []
var last_selected_pos = Vector2(0, 0) # 默认选中第一行第一列，不算表格的辅助内部节点
var exclude_mode = false # 排除模式：ctrl到选区中时再次选择会开启排除模式，将选区变为非选区
var exclude_border
var cornor_dragger: Control
var cornor_drag_start = false
var autofill_info
var autofill_borders = []
var DEFAULT_BORDER_STYLE = StyleBoxFlat.new()
const DEFAULT_BORDER_BG_COLOR = Color(Color.WHITE, 0.05)
const DEFAULT_BORDER_BORDER_COLOR = Color(Color.WHITE_SMOKE, 0.75)

func _ready() -> void:
	DEFAULT_BORDER_STYLE.draw_center = false
	DEFAULT_BORDER_STYLE.bg_color = DEFAULT_BORDER_BG_COLOR
	DEFAULT_BORDER_STYLE.border_color = DEFAULT_BORDER_BORDER_COLOR
	reset_header()
	await get_tree().process_frame
	datas = datas
	label_max_lines_visible = label_max_lines_visible
	var v_scroll_bar = scroll_container.get_v_scroll_bar() as VScrollBar
	v_scroll_bar.visibility_changed.connect(func():
		if not buttons.is_empty():
			(buttons.back() as Button).custom_minimum_size.x = int(v_scroll_bar.visible) * v_scroll_bar.size.x
			await get_tree().process_frame
			realign_rows()
	)
	#if is_inside_tree() and !datas.is_empty():
		#for i in 50:
			#await create_tween().tween_callback(func(): realign_rows()).set_delay(0.1).finished
	
func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		# 取消编辑本表中的对象
		var obj = EditorInterface.get_inspector().get_edited_object()
		if obj != null and obj is DictionaryObject and datas.has(obj):
			EditorInterface.inspect_object(null)
			
		popup_menu_text.set_item_metadata(0, null)
		popup_menu_text.set_item_metadata(1, null)
		popup_menu_text.set_item_metadata(2, null)
		clear_header()
		clear_rows()
		datas = []
		last_focused_row = null
		for i: Control in autofill_borders:
			i.queue_free()
		autofill_borders.clear()
		autofill_info = {}
		if cornor_dragger:
			cornor_dragger.queue_free()
		#data_of_focused_row = null
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
	if show_frame:
		fake_columns.push_back("") # 给外纵向框架再加1列
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
			control.size_flags_stretch_ratio = 1000000
			c.dragger_visibility = HSplitContainer.DRAGGER_HIDDEN_COLLAPSED
		elif i == 1 and show_frame:
			button.icon = preload("res://addons/gdsql/img/2D.png") # 全选
			button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			button.pressed.connect(_on_button_select_all_pressed)
			control.size_flags_stretch_ratio = 10000
			c.collapsed = true
		elif i == fake_columns.size() - 2:
			button.size_flags_stretch_ratio = 1000000
			c.dragger_visibility = HSplitContainer.DRAGGER_HIDDEN_COLLAPSED
			if not column_tips.is_empty():
				button.tooltip_text = column_tips[i-1-int(show_frame)]
		elif i == fake_columns.size() - 1:
			button.size_flags_stretch_ratio = 1
			button.self_modulate.a = 0
			button.add_theme_stylebox_override("normal", style_box_empty)
			button.add_theme_stylebox_override("hover", style_box_empty)
			button.add_theme_stylebox_override("pressed", style_box_empty)
			button.add_theme_stylebox_override("focus", style_box_empty)
		else:
			if not column_tips.is_empty():
				button.tooltip_text = column_tips[i-1-int(show_frame)]
				
			if ratios.size() > i - 1 - int(show_frame):
				control.size_flags_stretch_ratio = ratios[i - 1 - int(show_frame)]
			else:
				control.size_flags_stretch_ratio = fake_columns.size() - i - 2
			
		#if i == fake_columns.size() - 1:
			#button.hide()
			
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
	await get_tree().process_frame
	realign_rows()
	
#region 增量操作
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
		if show_frame:
			for i in range(pos, v_box_container.get_child_count(), 1):
				var line_btn = v_box_container.get_child(i).get_child(0).get_child(1)
				line_btn.text = str(i+1)
		
func remove_data_at(index: int, free_data: bool):
	if datas[index] is DictionaryObject:
		var data = datas[index] as DictionaryObject
		if free_data:
			data.free_all_custom_display_controls()
		else:
			# 把自定义控件剥离出来，不然后面row释放的时候会把子控件都销毁
			if v_box_container.get_child_count() > index:
				var row = v_box_container.get_child(index)
				for i in columns.size():
					var ctl = data.get_custom_display_control(data.__get_index_prop(i))
					if row.is_ancestor_of(ctl):
						ctl.get_parent().remove_child(ctl)
	datas.remove_at(index)
	if v_box_container.get_child_count() > index:
		var row = v_box_container.get_child(index)
		if row == last_focused_row:
			last_focused_row = null
		row.remove_meta("data")
		v_box_container.remove_child(row)
		row.queue_free()
		if show_frame:
			for i in range(index, v_box_container.get_child_count(), 1):
				var line_btn = v_box_container.get_child(i).get_child(0).get_child(1)
				line_btn.text = str(int(line_btn.text)-1)
		
func move_data(from: int, to: int):
	if from != to:
		var data = datas[from]
		datas.remove_at(from)
		datas.insert(to, data)
		if is_node_ready():
			var row = v_box_container.get_child(from)
			v_box_container.move_child(row, to)
			for i in range(from, to+1, 1):
				var line_btn = v_box_container.get_child(i).get_child(0).get_child(1)
				line_btn.text = str(i+1)
#endregion
		
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
			for i in columns.size():
				data.push_back(a_data.get(a_data.keys()[i], null))
	elif a_data is DictionaryObject:
		data = []
		if columns.is_empty():
			columns = []
			for info in a_data._get_property_list():
				if a_data._is_hidden_prop(info["name"]):
					continue
				columns.push_back(info["name"])
				data.push_back(a_data.get(info["name"]))
		else:
			for i in columns.size():
				data.push_back(a_data._get_by_index(i)) # 不用字段名称去获取是因为columns的字段名称和实际数据的字段名称不一定一致
	else:
		push_error("Table only support Array, Dictionary or DictionaryObject.")
		return
		
	var a_row = row_panel_container.duplicate()
	a_row.set_meta("data", a_data)
	v_box_container.add_child(a_row)
	a_row.gui_input.connect(_on_row_gui_input.bind(a_row, a_data), CONNECT_DEFERRED)
	a_row.mouse_entered.connect(_on_row_mouse_entered.bind(a_row), CONNECT_DEFERRED)
	var style_box: StyleBoxFlat = a_row.get_theme_stylebox("panel").duplicate()
	a_row.add_theme_stylebox_override("panel", style_box)
	
	data.insert(0, "")
	if show_frame:
		data.insert(1, Button.new())
	data.push_back("")
	for i in data.size():
		var control: Control
		var handled = false
		
		# 外边框的按钮
		if show_frame and i == 1:
			control = data[i] as Button
			control.text = str(v_box_container.get_child_count())
			control.ready.connect(func():
				await get_tree().process_frame
				control.custom_minimum_size.x = buttons[1].size.x
			, CONNECT_ONE_SHOT)
			control.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			control.add_theme_stylebox_override("focus", style_box_empty)
			control.add_theme_font_size_override("font_size", 12)
			control.pressed.connect(func():
				# TODO signal
				printt("aaaaaaaa")
			)
			handled = true
		
		# 该条数据在column中的位置
		var col_index = i - 1 - int(show_frame)
		if i == data.size() - 1:
			col_index = -1
		# 如果该数据提供了自定义显示控件，就直接使用
		if not handled and col_index >= 0 and a_data is DictionaryObject:
			a_data = a_data as DictionaryObject
			control = a_data.get_custom_display_control(a_data.__get_index_prop(col_index))
			handled = control != null
			
		# 否则，用表格自带的显示控件
		if not handled:
			match typeof(data[i]):
				TYPE_BOOL:
					handled = true
					control = check_box_model.duplicate()
					control.button_pressed = data[i]
					control.tooltip_text = str(data[i])
					control.gui_input.connect(_label_gui_input.bind(col_index), CONNECT_DEFERRED)
					if col_index >= 0 and a_data is DictionaryObject:
						a_data = a_data as DictionaryObject
						var callback = func(new_value, control_ref: WeakRef):
							var ctl = control_ref.get_ref()
							if ctl:
								ctl.button_pressed = new_value
						 # 绕这么一圈用弱引用是怕内存溢出
						a_data.set_update_callback(a_data.__get_index_prop(col_index), callback.bind(weakref(control)))
				TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME:
					handled = true
					control = label_model.duplicate()
					control.text = str(data[i])
					control.tooltip_text = str(data[i])
					control.gui_input.connect(_label_gui_input.bind(col_index), CONNECT_DEFERRED)
					if col_index >= 0 and a_data is DictionaryObject:
						a_data = a_data as DictionaryObject
						var callback = func(new_value, control_ref: WeakRef):
							var ctl = control_ref.get_ref()
							if ctl:
								ctl.text = str(new_value)
						a_data.set_update_callback(a_data.__get_index_prop(col_index), callback.bind(weakref(control)))
				TYPE_OBJECT:
					if data[i] is Resource:
						handled = true
						if data[i] is Texture2D:
							var texture_rect = TextureRect.new()
							texture_rect.texture = data[i]
							texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
							texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
							texture_rect.tooltip_text = \
								"%s\nType: %s\nSize: %s" % [data[i].resource_path, data[i].get_class(), data[i].get_size()]
							control = texture_rect
							control.gui_input.connect(_label_gui_input.bind(col_index), CONNECT_DEFERRED)
							if col_index >= 0 and i < data.size() - 1 and a_data is DictionaryObject:
								var callback = func(new_value, control_ref: WeakRef):
									var ctl = control_ref.get_ref()
									if ctl:
										ctl.texture = new_value
								a_data.set_update_callback(a_data.__get_index_prop(col_index), callback.bind(weakref(control)))
						else:
							## 注意：EditorResourcePicker有些慢，如果数据量比较大，会很卡，所以尽可能把常用的类型单独处理，比如上面的Texture2D
							var editor_resource_picker := EditorResourcePicker.new()
							#editor_resource_picker.mouse_filter = Control.MOUSE_FILTER_IGNORE
							#editor_resource_picker.propagate_call("set_mouse_filter", [Control.MOUSE_FILTER_IGNORE])
							editor_resource_picker.base_type = "Resource"
							editor_resource_picker.edited_resource = data[i]
							editor_resource_picker.editable = false
							control = editor_resource_picker
							control.gui_input.connect(_label_gui_input.bind(col_index), CONNECT_DEFERRED)
							if col_index >= 0 and i < data.size() - 1 and a_data is DictionaryObject:
								var callback = func(new_value, control_ref: WeakRef):
									var ctl = control_ref.get_ref()
									if ctl:
										ctl.edited_resource = new_value
								a_data.set_update_callback(a_data.__get_index_prop(col_index), callback.bind(weakref(control)))
						#control = texture_rect_model.duplicate()
						#control.texture = data[i]
					elif data[i] is Control:
						handled = true
						control = data[i]
					## TODO 可能需要添加其他有必要预览的类型
				
		if not handled:
			control = label_model.duplicate()
			control.text = var_to_str(data[i])
			control.gui_input.connect(_label_gui_input.bind(col_index), CONNECT_DEFERRED)
			if col_index >= 0 and a_data is DictionaryObject and a_data.has_method("set_update_callback"):
				a_data = a_data as DictionaryObject
				var callback = func(new_value, control_ref: WeakRef):
					var ctl = control_ref.get_ref()
					if ctl:
						ctl.text = var_to_str(new_value)
				a_data.set_update_callback(a_data.__get_index_prop(col_index), callback.bind(weakref(control)))
			
		#control.set_meta("data", data[i])
		#control.gui_input.connect(_on_label_model_gui_input.bind(control), CONNECT_DEFERRED)
		# 表格刷新时某些自定义控件可能需要重复使用，要去掉parent
		var panel_container = PanelContainer.new()
		panel_container.set_meta("overlapping", 0) # 选区重叠次数
		panel_container.mouse_filter = Control.MOUSE_FILTER_PASS
		panel_container.add_theme_stylebox_override("panel", DEFAULT_BORDER_STYLE)
		panel_container.gui_input.connect(_on_border_panel_container_gui_input.bind(panel_container), CONNECT_DEFERRED)
		if col_index >= 0:# 行号的button不用填充
			control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			panel_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
			panel_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			
		if i == 0 or (i == 1 and show_frame):
			a_row.get_child(0).add_child(panel_container, false, INTERNAL_MODE_FRONT)
		elif i == data.size() - 1:
			a_row.get_child(0).add_child(panel_container, false, INTERNAL_MODE_BACK)
		else:
			a_row.get_child(0).add_child(panel_container)
			
		if control.get_parent() == null:
			panel_container.add_child(control)
		else:
			control.reparent(panel_container)
		if i == 0 or i == data.size() - 1:
			panel_container.hide()
		panel_container.size_flags_stretch_ratio = buttons[i].size.x + 6 # HSplitContainer间隔为8，两边各取一半
		
		
func clear_rows():
	clear_borders()
	while v_box_container.get_child_count() > 0:
		var r = v_box_container.get_child(0)
		if r == last_focused_row:
			last_focused_row = null
		r.remove_meta("data")
		v_box_container.remove_child(r)
		r.queue_free()
		
func realign_rows():
	if v_box_container == null:
		return
	for row in v_box_container.get_children():
		for i in row.get_child(0).get_child_count(true):
			row.get_child(0).get_child(i, true).size_flags_stretch_ratio = buttons[i].size.x + 6
	# TODO 选框更新
		
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
	await get_tree().process_frame
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
	if not (event is InputEventMouseButton and event.is_pressed()):
		return
		
	var emit_click = func():
		if event is InputEventMouseButton and \
			(event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT):
			highlight_row(row_panel, true, event.button_index == MOUSE_BUTTON_RIGHT)
			row_clicked.emit(datas.find(source_data), event.button_index, source_data)
			
	if not editable:
		emit_click.call()
		return

	if not event is InputEventMouseButton:
		#emit_click.call()
		return

	#if not (event as InputEventMouseButton).double_click:
		#return
		
	emit_click.call()
	
	if editable and event is InputEventMouseButton and \
		(event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT):
		inspect_highlight_rows()
		
func _on_row_mouse_entered(row_panel) -> void:
	#printt(row_panel)
	pass
	
func clear_borders() -> void:
	for info in selected_borders:
		var rect = info["rect"] as Rect2
		var start_pos = rect.position # 选区左上角
		var end_pos =  rect.end # 选区右下角
		for row in range(start_pos.x, end_pos.x):
			for col in range(start_pos.y, end_pos.y):
				var pc = v_box_container.get_child(row).get_child(0).get_child(col) as PanelContainer
				if pc.get_theme_stylebox("panel") != DEFAULT_BORDER_STYLE:
					pc.add_theme_stylebox_override("panel", DEFAULT_BORDER_STYLE)
				pc.set_meta("overlapping", 0)
	selected_borders.clear()
	if is_instance_valid(cornor_dragger):
		cornor_dragger.queue_free()
		cornor_dragger = null
	
func clear_border_of_start(start: Vector2) -> void:
	var i = -1
	for info in selected_borders:
		i += 1
		if info["start"] == start:
			var rect = info["rect"] as Rect2
			var start_pos = rect.position # 选区左上角
			var end_pos =  rect.end # 选区右下角
			for row in range(start_pos.x, end_pos.x):
				for col in range(start_pos.y, end_pos.y):
					var pc = v_box_container.get_child(row).get_child(0).get_child(col) as PanelContainer
					pc.add_theme_stylebox_override("panel", DEFAULT_BORDER_STYLE)
					pc.set_meta("overlapping", pc.get_meta("overlapping") - 1)
					if is_instance_valid(cornor_dragger) and pc.is_ancestor_of(cornor_dragger):
						cornor_dragger.queue_free()
						cornor_dragger = null
			selected_borders.remove_at(i)
			break
				
# 一个start最多只能为一个区域的起点
func get_border_of_start(start: Vector2):
	for info in selected_borders:
		if info["start"] == start:
			return info
	return null
	
func add_border(border) -> void:
	printt("begin add border", border)
	# 起始点
	last_selected_pos = border["start"]
	
	# 唯一选区要更新区域，清了重画
	if selected_borders.size() == 1 and selected_borders[0]["start"] == last_selected_pos:
		clear_border_of_start(last_selected_pos)
		printt("iiiiii")
	else:
		if not selected_borders.is_empty():
			# 和上一个选区是同一个起始点，要先还原一下（背景色）再重新画
			if selected_borders.back()["start"] == last_selected_pos:
				printt("ppp")
				var old_start_pos = (selected_borders.back()["rect"] as Rect2).position
				var old_end_pos = (selected_borders.back()["rect"] as Rect2).end
				for row in range(old_start_pos.x, old_end_pos.x):
					for col in range(old_start_pos.y, old_end_pos.y):
						var pc = v_box_container.get_child(row).get_child(0).get_child(col) as PanelContainer
						var sb = pc.get_theme_stylebox("panel") as StyleBoxFlat
						var overlapping = pc.get_meta("overlapping") - 1
						pc.set_meta("overlapping", overlapping)
						if overlapping == 0:
							sb = DEFAULT_BORDER_STYLE
							pc.add_theme_stylebox_override("panel", sb)
						else:
							sb.bg_color.a = DEFAULT_BORDER_BG_COLOR.a * overlapping * 1.05
							sb.border_color = Color(DEFAULT_BORDER_BORDER_COLOR, 0.1)#sb.bg_color
							# 还原时要看是否在边框，从而设定边框宽度
							sb.set_border_width_all(0) # 先统一设为0
							for a_border in selected_borders:
								if a_border["start"] == last_selected_pos:
									continue
								var rect = a_border["rect"] as Rect2
								if not rect.intersects(selected_borders.back()["rect"]):
									continue
								if row == rect.position.x:
									sb.border_width_top = 2
								if col == rect.position.y:
									sb.border_width_left = 2
								if row == rect.end.x - 1:
									sb.border_width_bottom = 2
								if col == rect.end.y - 1:
									sb.border_width_right = 2
									
				selected_borders.pop_back()
			# 非同一起点
			else:
				printt("jjjjjjjjj")
				# 如果按了ctrl，上一选区要把边框取消、起始点显示背景
				if border.has("ctrl") and border["ctrl"]:
					printt("3333333 ctrl pressed")
					var old_start_pos = (selected_borders.back()["rect"] as Rect2).position
					var old_end_pos = (selected_borders.back()["rect"] as Rect2).end
					for row in range(old_start_pos.x, old_end_pos.x):
						for col in range(old_start_pos.y, old_end_pos.y):
							var pc = v_box_container.get_child(row).get_child(0).get_child(col) as PanelContainer
							var sb = pc.get_theme_stylebox("panel") as StyleBoxFlat
							sb.draw_center = true
							var overlapping = pc.get_meta("overlapping")
							sb.bg_color.a = DEFAULT_BORDER_BG_COLOR.a * overlapping * 1.05
							sb.border_color = Color(DEFAULT_BORDER_BORDER_COLOR, 0.1)#sb.bg_color # 相当于把边框取消了
							printt("uuuuuuu", sb.bg_color.a, overlapping, DEFAULT_BORDER_BG_COLOR.a)
				# 没按ctrl，全部选区清空
				else:
					printt("kk")
					clear_borders()
					
	var start_pos = (border["rect"] as Rect2).position
	var end_pos = (border["rect"] as Rect2).end
	for row in range(start_pos.x, end_pos.x):
		for col in range(start_pos.y, end_pos.y):
			var pc = v_box_container.get_child(row).get_child(0).get_child(col) as PanelContainer
			var overlapping = pc.get_meta("overlapping") + 1
			var sb
			
			# 边框设置。
			# 1. 该选区是唯一的选区
			if selected_borders.is_empty():
				if row == start_pos.x:
					if sb == null: sb = DEFAULT_BORDER_STYLE.duplicate()
					sb.border_width_top = 2
				if col == start_pos.y:
					if sb == null: sb = DEFAULT_BORDER_STYLE.duplicate()
					sb.border_width_left = 2
				if row == end_pos.x - 1:
					if sb == null: sb = DEFAULT_BORDER_STYLE.duplicate()
					sb.border_width_bottom = 2
				if col == end_pos.y - 1:
					if sb == null: sb = DEFAULT_BORDER_STYLE.duplicate()
					sb.border_width_right = 2
					
				if col > 0:
					if sb == null: sb = DEFAULT_BORDER_STYLE.duplicate()
					sb.expand_margin_left = 6
				if col < columns.size()-1:
					if sb == null: sb = DEFAULT_BORDER_STYLE.duplicate()
					sb.expand_margin_right = 6
					
				if not(row == last_selected_pos.x and col == last_selected_pos.y):
					if sb == null: sb = DEFAULT_BORDER_STYLE.duplicate()
					sb.draw_center = true
					printt("vvvv", row, col)
			# 2. 不唯一
			else:
				sb = DEFAULT_BORDER_STYLE.duplicate() as StyleBoxFlat
				if row == start_pos.x:
					sb.border_width_top = 2
				if col == start_pos.y:
					sb.border_width_left = 2
				if row == end_pos.x - 1:
					sb.border_width_bottom = 2
				if col == end_pos.y - 1:
					sb.border_width_right = 2
					
				if col > 0:
					sb.expand_margin_left = 6
				if col < columns.size()-1:
					sb.expand_margin_right = 6
					
				if row == last_selected_pos.x and col == last_selected_pos.y:
					sb.border_color = Color(DEFAULT_BORDER_BORDER_COLOR, 0.1)#Color(sb.bg_color, DEFAULT_BORDER_BG_COLOR.a * overlapping * 1.05)
				else:
					sb.border_color = Color(DEFAULT_BORDER_BORDER_COLOR, 0.1)#Color(sb.bg_color, DEFAULT_BORDER_BG_COLOR.a * overlapping * 1.05)
					sb.draw_center = true
				
				pass
				
			if sb != null:
				pc.add_theme_stylebox_override("panel", sb)
				pc.set_meta("overlapping", overlapping)
				sb.bg_color.a = DEFAULT_BORDER_BG_COLOR.a * overlapping * 1.05
				printt("rrrrrr", sb.draw_center, row, col)
			
	selected_borders.push_back(border)
	if selected_borders.size() == 1:
		var start = (selected_borders.front()["rect"] as Rect2).position
		var end = (selected_borders.front()["rect"] as Rect2).end - Vector2.ONE
		var pc = v_box_container.get_child(end.x).get_child(0).get_child(end.y) as PanelContainer
		var sb = pc.get_theme_stylebox("panel") as StyleBoxFlat
		var cd = preload("res://addons/gdsql/table/cornor_dragger.tscn").instantiate() as MarginContainer
		cd.add_theme_constant_override("margin_right", -sb.expand_margin_right)
		pc.add_child(cd)
		cd.cornor_drag_start.connect(func():
			printt("drag start")
			add_autofill_border(start, end + Vector2.ONE, "start")
		)
		cd.cornor_drag_moving.connect(func(diff: Vector2):
			printt("drag moving")
			var panel_container = get_panel_container_under_mouse()
			if panel_container == null:
				printt("panel is null")
				return
			scroll_container.ensure_control_visible(panel_container) # 超出scroll_container的边界时，要让scroll_container自己滚动
			var pos_row = panel_container.get_parent().get_parent().get_index()
			var pos_col = panel_container.get_index()
			# TODO 如果panel_container在上下左右外侧（非内侧、非斜外侧），则稳定多出一块。否则再使用下方的逻辑。
			if diff.x > 0:
				if diff.y > 0:
					if diff.x > diff.y:
						# 向右多出一块
						# #####¯¯¯⌉
						# #####   |
						# #####___⌋
						printt("--------------------1", diff)
						add_autofill_border(start, Vector2(end.x, pos_col) + Vector2.ONE, "add")
					else:
						# 向下多出一块
						# #########
						# #########
						# |       |
						# ⌊_______⌋
						printt("--------------------2", diff)
						add_autofill_border(start, Vector2(pos_row, end.y) + Vector2.ONE, "add")
				else:
					if diff.x > -diff.y:
						# 向右多出一块
						# #####¯¯¯⌉
						# #####   |
						# #####___⌋
						printt("--------------------3", diff)
						add_autofill_border(start, Vector2(end.x, pos_col) + Vector2.ONE, "add")
					else:
						# 向上缩小一块
						if pos_row > start.x:
							printt("--------------------4", diff)
							var rect = panel_container.get_rect() as Rect2
							rect.size.y /= 2
							if rect.has_point(panel_container.get_parent().get_local_mouse_position()):
								add_autofill_border(start, Vector2(pos_row - 1, end.y) + Vector2.ONE, "sub")
							else:
								add_autofill_border(start, Vector2(pos_row, end.y) + Vector2.ONE, 
									"sub" if pos_row != end.x else "start")
						# 全部缩
						elif pos_row == start.x:
							printt("--------------------5", diff)
							var rect = panel_container.get_rect() as Rect2
							rect.size.y /= 2
							if rect.has_point(panel_container.get_parent().get_local_mouse_position()):
								add_autofill_border(start, end + Vector2.ONE, "sub")
							else:
								add_autofill_border(start, Vector2(pos_row, end.y) + Vector2.ONE, 
									"sub" if pos_row != end.x else "start")
						# 向上扩展
						else:
							printt("--------------------6", diff)
							add_autofill_border(Vector2(pos_row, start.y), end + Vector2.ONE, "add")
			else:
				if diff.y > 0:
					if -diff.x > diff.y:
						# 向左缩一块
						if pos_col > start.y:
							printt("--------------------7", diff)
							var rect = panel_container.get_rect() as Rect2
							rect.size.x /= 2
							if rect.has_point(panel_container.get_parent().get_local_mouse_position()):
								add_autofill_border(start, Vector2(end.x, pos_col-1) + Vector2.ONE, "sub")
							else:
								add_autofill_border(start, Vector2(end.x, pos_col) + Vector2.ONE, 
									"sub" if pos_col != end.y else "start")
						# 全部缩
						elif pos_col == start.y:
							printt("--------------------8", diff)
							var rect = panel_container.get_rect() as Rect2
							rect.size.x /= 2
							if rect.has_point(panel_container.get_parent().get_local_mouse_position()):
								add_autofill_border(start, end + Vector2.ONE, "sub")
							else:
								add_autofill_border(start, Vector2(end.x, pos_col) + Vector2.ONE, 
									"sub" if pos_col != end.y else "start")
						# 向左扩展
						else:
							printt("--------------------9", diff)
							add_autofill_border(Vector2(start.x, pos_col), end + Vector2.ONE, "add")
					else:
						# 向下多出一块
						# #########
						# #########
						# |       |
						# ⌊_______⌋
						printt("--------------------16", diff)
						add_autofill_border(start, Vector2(pos_row, end.y) + Vector2.ONE, "add")
				else:
					if -diff.x > -diff.y:
						# 向左缩一块
						if pos_col > start.y:
							printt("--------------------13", diff)
							var rect = panel_container.get_rect() as Rect2
							rect.size.x /= 2
							if rect.has_point(panel_container.get_parent().get_local_mouse_position()):
								add_autofill_border(start, Vector2(end.x, pos_col-1) + Vector2.ONE, "sub")
							else:
								add_autofill_border(start, Vector2(end.x, pos_col) + Vector2.ONE, 
									"sub" if pos_col != end.y else "start")
						# 全部缩
						elif pos_col == start.y:
							printt("--------------------14", diff)
							var rect = panel_container.get_rect() as Rect2
							rect.size.x /= 2
							if rect.has_point(panel_container.get_parent().get_local_mouse_position()):
								add_autofill_border(start, end + Vector2.ONE, "sub")
							else:
								add_autofill_border(start, Vector2(end.x, pos_col) + Vector2.ONE, 
									"sub" if pos_col != end.y else "start")
						# 向左扩展
						else:
							printt("--------------------15", diff)
							add_autofill_border(Vector2(start.x, pos_col), end + Vector2.ONE, "add")
					else:
						# 向上缩小一块
						if pos_row > start.x:
							printt("--------------------10", diff)
							var rect = panel_container.get_rect() as Rect2
							rect.size.y /= 2
							if rect.has_point(panel_container.get_parent().get_local_mouse_position()):
								add_autofill_border(start, Vector2(pos_row - 1, end.y) + Vector2.ONE, "sub")
							else:
								add_autofill_border(start, Vector2(pos_row, end.y) + Vector2.ONE, 
									"sub" if pos_row != end.x else "start")
						# 全部缩
						elif pos_row == start.x:
							printt("--------------------11", diff)
							var rect = panel_container.get_rect() as Rect2
							rect.size.y /= 2
							if rect.has_point(panel_container.get_parent().get_local_mouse_position()):
								add_autofill_border(start, end + Vector2.ONE, "sub")
							else:
								add_autofill_border(start, Vector2(pos_row, end.y) + Vector2.ONE, 
									"sub" if pos_row != end.x else "start")
						# 向上扩展
						else:
							printt("--------------------12", diff)
							add_autofill_border(Vector2(pos_row, start.y), end + Vector2.ONE, "add")
		)
		cd.cornor_drag_end.connect(commit_autofill_border)
		cornor_dragger = cd
	else:
		if is_instance_valid(cornor_dragger):
			cornor_dragger.queue_free()
			cornor_dragger = null
	
func add_exclude_border(border) -> void:
	# 先还原（类似add_border中【和上一个选区是同一个起始点，要先还原一下（背景色）再重新画】这段逻辑
	if exclude_border != null:
		var old_start_pos = (exclude_border["rect"] as Rect2).position
		var old_end_pos = (exclude_border["rect"] as Rect2).end
		for row in range(old_start_pos.x, old_end_pos.x):
			for col in range(old_start_pos.y, old_end_pos.y):
				var pc = v_box_container.get_child(row).get_child(0).get_child(col) as PanelContainer
				var sb = pc.get_theme_stylebox("panel") as StyleBoxFlat
				var overlapping = pc.get_meta("overlapping")
				pc.set_meta("overlapping", overlapping)
				if overlapping == 0:
					sb = DEFAULT_BORDER_STYLE
					pc.add_theme_stylebox_override("panel", sb)
				else:
					sb.bg_color = Color(DEFAULT_BORDER_BG_COLOR, DEFAULT_BORDER_BG_COLOR.a * overlapping * 1.05)
					if selected_borders.size() <= 1:
						sb.border_color = DEFAULT_BORDER_BORDER_COLOR
					else:
						sb.border_color = Color(DEFAULT_BORDER_BORDER_COLOR, 0.1)
					# 还原时要看是否在边框，从而设定边框宽度
					sb.set_border_width_all(0) # 先统一设为0
					for a_border in selected_borders:
						if a_border["start"] == last_selected_pos:
							continue
						var rect = a_border["rect"] as Rect2
						if not rect.intersects(exclude_border["rect"]):
							continue
						if row == rect.position.x:
							sb.border_width_top = 2
						if col == rect.position.y:
							sb.border_width_left = 2
						if row == rect.end.x - 1:
							sb.border_width_bottom = 2
						if col == rect.end.y - 1:
							sb.border_width_right = 2
							
	var start_pos = (border["rect"] as Rect2).position
	var end_pos = (border["rect"] as Rect2).end
	for row in range(start_pos.x, end_pos.x):
		for col in range(start_pos.y, end_pos.y):
			var pc = v_box_container.get_child(row).get_child(0).get_child(col) as PanelContainer
			var sb = pc.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
			# 为了简单起见，只修改背景
			sb.bg_color = Color(Color.DARK_BLUE, 0.25)
			sb.border_color = Color(Color.DARK_BLUE, 0.2)
			sb.draw_center = true
			if row == start_pos.x:
				sb.border_width_top = 2
			if col == start_pos.y:
				sb.border_width_left = 2
			if row == end_pos.x - 1:
				sb.border_width_bottom = 2
			if col == end_pos.y - 1:
				sb.border_width_right = 2
				
			if col > 0:
				sb.expand_margin_left = 6
			if col < columns.size()-1:
				sb.expand_margin_right = 6
			pc.add_theme_stylebox_override("panel", sb)
			
	exclude_border = border
			
func commit_exclude_border():
	if exclude_border == null:
		return
		
	# 还原一下
	var old_start_pos = (exclude_border["rect"] as Rect2).position
	var old_end_pos = (exclude_border["rect"] as Rect2).end
	for row in range(old_start_pos.x, old_end_pos.x):
		for col in range(old_start_pos.y, old_end_pos.y):
			var pc = v_box_container.get_child(row).get_child(0).get_child(col) as PanelContainer
			var sb = pc.get_theme_stylebox("panel") as StyleBoxFlat
			var overlapping = pc.get_meta("overlapping")
			pc.set_meta("overlapping", overlapping)
			if overlapping == 0:
				sb = DEFAULT_BORDER_STYLE
				pc.add_theme_stylebox_override("panel", sb)
			else:
				sb.bg_color = Color(DEFAULT_BORDER_BG_COLOR, DEFAULT_BORDER_BG_COLOR.a * overlapping * 1.05)
				if selected_borders.size() <= 1:
					sb.border_color = DEFAULT_BORDER_BORDER_COLOR
				else:
					sb.border_color = Color(DEFAULT_BORDER_BORDER_COLOR, 0.1)
				# 还原时要看是否在边框，从而设定边框宽度
				sb.set_border_width_all(0) # 先统一设为0
				for a_border in selected_borders:
					if a_border["start"] == last_selected_pos:
						continue
					var rect = a_border["rect"] as Rect2
					if not rect.intersects(exclude_border["rect"]):
						continue
					if row == rect.position.x:
						sb.border_width_top = 2
					if col == rect.position.y:
						sb.border_width_left = 2
					if row == rect.end.x - 1:
						sb.border_width_bottom = 2
					if col == rect.end.y - 1:
						sb.border_width_right = 2
						
	var exclude_rect = exclude_border["rect"] as Rect2
	
	# 完全处于exclude选框内的要删除
	var clears = []
	#var need_update = [] # 需要更新的范围
	for i in selected_borders.size():
		var border = selected_borders[i]
		if exclude_rect.encloses(border["rect"]):
			#need_update.push_back(border["rect"])
			clears.push_back(i)
			var a_start_pos = (border["rect"] as Rect2).position
			var a_end_pos = (border["rect"] as Rect2).end
			for row in range(a_start_pos.x, a_end_pos.x):
				for col in range(a_start_pos.y, a_end_pos.y):
					var pc = v_box_container.get_child(row).get_child(0).get_child(col) as PanelContainer
					pc.set_meta("overlapping", pc.get_meta("overlapping") - 1)
					pc.add_theme_stylebox_override("panel", DEFAULT_BORDER_STYLE)
					
	clears.reverse()
	for i in clears:
		selected_borders.remove_at(i)
		
	# 有交集
	var empty_rect = Rect2()
	var to_add = []
	var to_delete = []
	for i in selected_borders.size():
		var border = selected_borders[i]
		var intersection = exclude_rect.intersection(border["rect"])
		if intersection == empty_rect:
			continue
		#need_update.push_back(border["rect"])
		to_delete.push_back(i)
		var border_size = border["rect"].size
		var border_start = border["rect"].position
		var border_end = border["rect"].end
		var inter_size = intersection.size
		var inter_start = intersection.position
		var inter_end = intersection.end
		# 设置删掉的部分的样式
		for row in range(inter_start.x, inter_end.x):
			for col in range(inter_start.y, inter_end.y):
				var pc = v_box_container.get_child(row).get_child(0).get_child(col) as PanelContainer
				pc.set_meta("overlapping", 0)
				pc.add_theme_stylebox_override("panel", DEFAULT_BORDER_STYLE)
		# 分割空间
		if inter_start.x == border_start.x:
			if inter_start.y == border_start.y:
				if inter_end.x == border_end.x:
					if inter_end.y == border_end.y:
						# 全部删除的情况，前面已经处理过了，应该不会走到这里
						push_error("Invalid situation.")
						# #####
						# #####
						# #####
					else:
						# 左边整体删除
						# ###¯¯⌉
						# ###  |
						# ###__⌋
						to_add.push_back({
							"start": Vector2(inter_start.x, inter_end.y),
							"rect": Rect2(inter_start.x, inter_end.y, border_size.x, border_size.y - inter_size.y)
						})
				# inter_end.x != border_end.x
				else:
					if inter_end.y == border_end.y:
						# 上边整体删除
						# #####
						# #####
						# |   |
						# ⌊___⌋
						to_add.push_back({
							"start": Vector2(inter_end.x, inter_start.y),
							"rect": Rect2(inter_end.x, inter_start.y, border_size.x - inter_size.x, border_size.y)
						})
					else:
						# 左上角去掉一块
						# ###¯¯¯⌉
						# ###   |
						# ###   |
						# |     |
						# ⌊_____⌋
						to_add.push_back({
							"start": Vector2(inter_start.x, inter_end.y),
							"rect": Rect2(inter_start.x, inter_end.y, inter_size.x, border_size.y - inter_size.y)
						})
						to_add.push_back({
							"start": Vector2(inter_end.x, inter_start.y),
							"rect": Rect2(inter_end.x, inter_start.y, border_size.x - inter_size.x, border_size.y)
						})
			# inter_start.x == border_start.x
			# inter_start.y != border_start.y
			else:
				if inter_end.x == border_end.x:
					if inter_end.y == border_end.y:
						# 右边整体删除
						# ⌈¯¯###
						# |  ###
						# ⌊__###
						to_add.push_back({
							"start": border_start,
							"rect": Rect2(border_start, Vector2(border_size.x, border_size.y - inter_size.y))
						})
					else:
						# 中间竖条删除
						# ⌈¯¯###¯¯⌉
						# |  ###  |
						# ⌊__###__⌋
						to_add.push_back({
							"start": border_start,
							"rect": Rect2(border_start, Vector2(border_size.x, inter_start.y - border_start.y))
						})
						to_add.push_back({
							"start": Vector2(inter_start.x, inter_end.y),
							"rect": Rect2(inter_start.x, inter_end.y, border_size.x, border_end.y - inter_end.y)
						})
				else:
					if inter_end.y == border_end.y:
						# 右上角删除
						# ⌈¯¯###
						# |  ###
						# ⌊____⌋
						to_add.push_back({
							"start": border_start,
							"rect": Rect2(border_start, Vector2(inter_size.x, border_size.y - inter_size.y))
						})
						to_add.push_back({
							"start": Vector2(inter_end.x, border_start.y),
							"rect": Rect2(inter_end.x, border_start.y, border_size.x - inter_size.x, border_size.y)
						})
					else:
						# 上边中间一块删除
						# ⌈¯¯###¯¯⌉
						# |  ###  |
						# ⌊_______⌋
						to_add.push_back({
							"start": border_start,
							"rect": Rect2(border_start, Vector2(inter_size.x, inter_start.y - border_start.y))
						})
						to_add.push_back({
							"start": Vector2(inter_start.x, inter_end.y),
							"rect": Rect2(inter_start.x, inter_end.y, inter_size.x, border_end.y - inter_end.y)
						})
						to_add.push_back({
							"start": Vector2(inter_end.x, border_start.y),
							"rect": Rect2(inter_end.x, border_start.y, border_size.x - inter_size.x, border_size.y)
						})
		# inter_start.x != border_start.x
		else:
			if inter_start.y == border_start.y:
				if inter_end.x == border_end.x:
					if inter_end.y == border_end.y:
						# 下面一半删除
						# ⌈¯¯¯¯¯¯¯⌉
						# |       |
						# #########
						# #########
						to_add.push_back({
							"start": border_start,
							"rect": Rect2(border_start, Vector2(border_size.x - inter_size.x, border_size.y))
						})
					else:
						# 左下角一块删除
						# ⌈¯¯¯¯¯¯¯⌉
						# |       |
						# #####   |
						# #####___⌋
						to_add.push_back({
							"start": border_start,
							"rect": Rect2(border_start, Vector2(border_size.x - inter_size.x, border_size.y))
						})
						to_add.push_back({
							"start": Vector2(inter_start.x, inter_end.y),
							"rect": Rect2(inter_start.x, inter_end.y, inter_size.x, border_size.y - inter_size.y)
						})
				else:
					if inter_end.y == border_end.y:
						# 横着一条删掉
						# ⌈¯¯¯¯¯¯¯⌉
						# #########
						# #########
						# ⌊_______⌋
						to_add.push_back({
							"start": border_start,
							"rect": Rect2(border_start, Vector2(inter_start.x - border_start.x, border_size.y))
						})
						to_add.push_back({
							"start": Vector2(inter_end.x, border_start.y),
							"rect": Rect2(inter_end.x, border_start.y, border_end.x - inter_end.x, border_size.y)
						})
					else:
						# 左边中间一块删掉
						# ⌈¯¯¯¯¯¯¯⌉
						# #####   |
						# #####   |
						# ⌊_______⌋
						to_add.push_back({
							"start": border_start,
							"rect": Rect2(border_start, Vector2(inter_start.x - border_start.x, border_size.y))
						})
						to_add.push_back({
							"start": Vector2(inter_start.x, inter_end.y),
							"rect": Rect2(inter_start.x, inter_end.y, inter_size.x, border_size.y - inter_size.y)
						})
						to_add.push_back({
							"start": Vector2(inter_end.x, border_start.y),
							"rect": Rect2(inter_end.x, border_start.y, border_end.x - inter_end.x, border_size.y)
						})
						pass
			# inter_start.x != border_start.x
			# inter_start.y != border_start.y
			else:
				if inter_end.x == border_end.x:
					if inter_end.y == border_end.y:
						# 右下角一块删除
						# ⌈¯¯¯¯¯¯¯⌉
						# |    ####
						# ⌊____####
						to_add.push_back({
							"start": border_start,
							"rect": Rect2(border_start, Vector2(border_size.x - inter_size.x, border_size.y))
						})
						to_add.push_back({
							"start": Vector2(inter_start.x, border_start.y),
							"rect": Rect2(inter_start.x, border_start.y, inter_size.x, border_size.y - inter_size.y)
						})
					else:
						# 下边中间一块删除
						# ⌈¯¯¯¯¯¯¯⌉
						# |  #### |
						# ⌊__####_⌋
						to_add.push_back({
							"start": border_start,
							"rect": Rect2(border_start, Vector2(border_size.x - inter_size.x, border_size.y))
						})
						to_add.push_back({
							"start": Vector2(inter_start.x, border_start.y),
							"rect": Rect2(inter_start.x, border_start.y, inter_size.x, inter_start.y - border_start.y)
						})
						to_add.push_back({
							"start": Vector2(inter_start.x, inter_end.y),
							"rect": Rect2(inter_start.x, inter_end.y, inter_size.x, border_end.y - inter_end.y)
						})
						pass
				else:
					if inter_end.y == border_end.y:
						# 右边中间一块删除
						# ⌈¯¯¯¯¯¯¯⌉
						# |   #####
						# |   #####
						# ⌊_______⌋
						to_add.push_back({
							"start": border_start,
							"rect": Rect2(border_start, Vector2(inter_start.x - border_start.x, border_size.y))
						})
						to_add.push_back({
							"start": Vector2(inter_start.x, border_start.y),
							"rect": Rect2(inter_start.x, border_start.y, inter_size.x, border_size.y - inter_size.y)
						})
						to_add.push_back({
							"start": Vector2(inter_end.x, border_start.y),
							"rect": Rect2(inter_end.x, border_start.y, border_end.x - inter_end.x, border_size.y)
						})
						pass
					else:
						# 中间一块删除
						# ⌈¯¯¯¯¯¯¯⌉
						# |  ###  |
						# |  ###  |
						# ⌊_______⌋
						to_add.push_back({
							"start": border_start,
							"rect": Rect2(border_start, Vector2(inter_start.x - border_start.x, border_size.y))
						})
						to_add.push_back({
							"start": Vector2(inter_start.x, border_start.y),
							"rect": Rect2(inter_start.x, border_start.y, inter_size.x, inter_start.y - border_start.y)
						})
						to_add.push_back({
							"start": Vector2(inter_start.x, inter_end.y),
							"rect": Rect2(inter_start.x, inter_end.y, inter_size.x, border_end.y - inter_end.y)
						})
						to_add.push_back({
							"start": Vector2(inter_end.x, border_start.y),
							"rect": Rect2(inter_end.x, border_start.y, border_end.x - inter_end.x, border_size.y)
						})
						
	to_delete.reverse()
	for i in to_delete:
		selected_borders.remove_at(i)
		
	selected_borders.append_array(to_add)
	Utils.print_variant(selected_borders)
	
	# 更新范围内的样式
	for border in selected_borders:
		var start_pos = (border["rect"] as Rect2).position
		var end_pos = (border["rect"] as Rect2).end
		for row in range(start_pos.x, end_pos.x):
			for col in range(start_pos.y, end_pos.y):
				var pc = v_box_container.get_child(row).get_child(0).get_child(col) as PanelContainer
				var sb = pc.get_theme_stylebox("panel") as StyleBoxFlat
				var overlapping = pc.get_meta("overlapping")
				pc.set_meta("overlapping", overlapping)
				if overlapping == 0:
					sb = DEFAULT_BORDER_STYLE
					pc.add_theme_stylebox_override("panel", sb)
				else:
					sb.bg_color = Color(DEFAULT_BORDER_BG_COLOR, DEFAULT_BORDER_BG_COLOR.a * overlapping * 1.05)
					if selected_borders.size() <= 1:
						sb.border_color = DEFAULT_BORDER_BORDER_COLOR
					else:
						sb.border_color = Color(DEFAULT_BORDER_BORDER_COLOR, 0.1)
					# 还原时要看是否在边框，从而设定边框宽度
					sb.set_border_width_all(0) # 先统一设为0
					for a_border in selected_borders:
						if a_border["start"] == last_selected_pos:
							continue
						var rect = a_border["rect"] as Rect2
						if not rect.intersects(border["rect"]):
							continue
						if row == rect.position.x:
							sb.border_width_top = 2
						if col == rect.position.y:
							sb.border_width_left = 2
						if row == rect.end.x - 1:
							sb.border_width_bottom = 2
						if col == rect.end.y - 1:
							sb.border_width_right = 2
							
	# 最后一个不能被删除，最后一个刚好是exclude_border的起始点
	if selected_borders.is_empty():
		var start = exclude_border["start"] as Vector2
		var border = {"start": start, "rect": Rect2(start.x, start.y, 1, 1)}
		add_border(border)
	# 只剩一个，区分一下起始点的样式
	elif selected_borders.size() == 1:
		var start = selected_borders.front()["start"] as Vector2
		var pc = v_box_container.get_child(start.x).get_child(0).get_child(start.y) as PanelContainer
		var sb = pc.get_theme_stylebox("panel") as StyleBoxFlat
		sb.draw_center = false
		
	exclude_border = null
	
func add_autofill_border(start_pos: Vector2, end_pos: Vector2, mode: String) -> void:
	# 清旧的
	for i: Control in autofill_borders:
		i.queue_free()
	autofill_borders.clear()
	
	if mode == "start":
		autofill_info = null
		return
	
	var dc_scene = preload("res://addons/gdsql/table/dash_border.tscn")
	for row in range(start_pos.x, end_pos.x):
		for col in range(start_pos.y, end_pos.y):
			if row == start_pos.x or col == start_pos.y or row == end_pos.x - 1 or col == end_pos.y - 1:
				var pc = v_box_container.get_child(row).get_child(0).get_child(col) as PanelContainer
				var sb = pc.get_theme_stylebox("panel") as StyleBoxFlat
				var dc = dc_scene.instantiate()
				pc.add_child(dc, false, INTERNAL_MODE_FRONT)
				autofill_borders.push_back(dc)
				dc.show_top = row == start_pos.x
				dc.show_bottom = row == end_pos.x - 1
				dc.show_left = col == start_pos.y
				dc.show_right = col == end_pos.y - 1
				
				if col == 0:
					dc.expand_margin_left = 2 if sb.border_width_left > 0 else 0
				elif sb.border_width_left > 0:
					dc.expand_margin_left = 8
				else:
					dc.expand_margin_left = 6 + 4 * int(col > start_pos.y)
					
				if col == columns.size() - 1:
					dc.expand_margin_right = 2 if sb.border_width_right > 0 else 0
				elif sb.border_width_right > 0:
					dc.expand_margin_right = 8
				else:
					dc.expand_margin_right = 6 + 4 * int(col < end_pos.y - 1)
					
				if row == 0:
					dc.expand_margin_top = 2 if sb.border_width_top > 0 else 0
				elif sb.border_width_top > 0:
					dc.expand_margin_top = 2
				else:
					dc.expand_margin_top = 0 + 2 * int(col > start_pos.y)
					
				if row == datas.size() - 1:
					dc.expand_margin_bottom = -1 if sb.border_width_bottom > 0 else -3
				elif sb.border_width_bottom > 0:
					dc.expand_margin_bottom = -1
				else:
					dc.expand_margin_bottom = -3 - 2 * int(row < end_pos.x - 1)# TODO 放大时有问题
				
	autofill_info = {
		"start": start_pos,
		"rect": Rect2(start_pos, end_pos - start_pos),
		"mode": mode
	}
	
func commit_autofill_border() -> void:
	for i: Control in autofill_borders:
		i.queue_free()
	autofill_borders.clear()
	
	if autofill_info == null:
		return
		
	var selected_rect = selected_borders.front()["rect"] as Rect2
	var autofill_rect = autofill_info["rect"] as Rect2
	printt("22222222", autofill_rect.end, selected_rect.end)
	printt("1111111", range(autofill_rect.end.x, selected_rect.end.x), range(autofill_rect.end.y, selected_rect.end.y))
	match autofill_info["mode"]:
		"sub":
			var sub_rect = Rect2()
			# 全删除
			if autofill_rect == selected_rect:
				sub_rect = autofill_rect
			# 删右边一部分
			elif autofill_rect.size.x == selected_rect.size.x:
				sub_rect.position = Vector2(autofill_rect.position.x, autofill_rect.end.y)
				sub_rect.size = Vector2(autofill_rect.size.x, selected_rect.size.y - autofill_rect.size.y)
			# 删下边一部分
			else:
				sub_rect.position = Vector2(autofill_rect.end.x, autofill_rect.position.y)
				sub_rect.size = Vector2(selected_rect.size.x - autofill_rect.size.x, autofill_rect.size.y)
				
			# 删除部分的属性设置为该数据类型的默认值
			for row in range(sub_rect.position.x, sub_rect.end.x):
				var row_panel_container = v_box_container.get_child(row)
				var data = row_panel_container.get_meta("data") as DictionaryObject
				for col in range(sub_rect.position.y, sub_rect.end.y):
					data._set_default_by_index(col)
					
		"add":
			# TODO
			pass
			
	var diff_rect = autofill_info["rect"]
	Utils.print_variant(selected_borders)
	Utils.print_variant(autofill_info)
	
	autofill_info = null
	
## 支持批量编辑多个数据
func inspect_highlight_rows() -> void:
	await get_tree().create_timer(0.05).timeout
	var rows = get_data_of_highlight_rows()
	if rows.is_empty():
		return
		
	if rows.size() == 1:
		EditorInterface.inspect_object(rows[0])
		# 全部展开（方便用户修改数据）
		await get_tree().process_frame
		for i: MenuButton in EditorInterface.get_inspector().get_parent().\
			find_children("@MenuButton*", "MenuButton", true, false):
			if i.tooltip_text == tr("Manage object properties."):
				i.get_popup().emit_signal("id_pressed", 12) # 12 is for EXPAND_ALL, @see editor\inspector_dock.h
				break
		return
		
	# 多个数据的构造一个MultiNodeEdit。参考Godot源码。
	# @see editor\multi_node_edit.cpp：MultiNodeEdit::_get_property_list
	# 这段主要是得出选中的数据的共同属性。
	var usage = {}
	var p_list = []
	var data_list = []
	var nc = 0
	for data in rows:
		if not data is Object:
			continue
		
		var plist = (data as Object).get_property_list()
		for F in plist:
			# 下面这段不用写，对gdscript来说没用
			#if (F.name == "script") {
				#continue; // Added later manually, since this is intercepted before being set (check Variant Object::get()).
			#} else if (F.name.begins_with("metadata/")) {
				#F.name = F.name.replace_first("metadata/", "Metadata/"); // Trick to not get actual metadata edited from MultiNodeEdit.
			#}
				
			if not usage.has(F["name"]):
				usage[F["name"]] = {"uses": 0, "info": F}
				data_list.push_back(usage[F["name"]])
				
			# Make sure only properties with the same exact PropertyInfo data will appear.
			if usage[F["name"]]["info"] == F:
				usage[F["name"]]["uses"] += 1
				
		nc += 1
		
	for E in data_list:
		if nc == E["uses"]:
			p_list.push_back(E["info"])
			
	#p_list->push_back(PropertyInfo(Variant::OBJECT, "scripts", PROPERTY_HINT_RESOURCE_TYPE, "Script")); 同样gdscript没用处
	
	# 根据共同属性，我们构造一个dict obj。要去掉共同属性中属于共同基类的属性。所以我们要找到这些Object的最小共同基类名称。
	# @see MultiNodeEdit::get_edited_class_name()
	var get_common_class_name = func():
		var a_class_name
		var check_again = true
		while check_again:
			check_again = false
			
			# Check that all nodes inherit from class_name.
			for data in rows:
				if not data is Object:
					continue
					
				data = data as Object
				var obj_class_name = data.get_class()
				if a_class_name == null:
					a_class_name = obj_class_name # a_class_name初始化为第一个object的类名
					
				if obj_class_name == "Object":
					# All nodes inherit from Object, so no need to continue checking.
					return obj_class_name
					
				if a_class_name == obj_class_name or ClassDB.is_parent_class(obj_class_name, a_class_name):
					# class_name is the same or a parent of the object's class.
					continue
					
				# class_name is not a parent of the node's class, so check again with the parent class.
				a_class_name = ClassDB.get_parent_class(a_class_name)
				check_again = true
				break
				
		return a_class_name
		
	var common_class_name = get_common_class_name.call()
	if common_class_name == null:
		push_error("Can not find common parent class name")
		return
		
	# 整一个脚本继承该类，得出基类的属性
	var script = GDScript.new()
	script.source_code = "extends %s" % common_class_name
	script.reload()
	var obj = script.new()
	var props_of_common_class = obj.get_property_list()
	if obj.has_method("free") and not obj is RefCounted:
		obj.free()
	
	# 去掉p_list中的基类的属性
	for i in props_of_common_class:
		for j in p_list.size():
			if i == p_list[j]:
				p_list.remove_at(j)
				break
				
	# 去掉dict obj本身的属性。因为我们要用dict obj来构造一个能被检查器检查的属性。
	var dummy_dict_obj = DictionaryObject.new({})
	for i in dummy_dict_obj.get_property_list():
		for j in p_list.size():
			if i == p_list[j]:
				p_list.remove_at(j)
				break
				
	# 剩下的属性用于构造dict obj
	var impl_data = {}
	var impl_hint = {}
	for i in p_list:
		var prop = i["name"]
		# 如果所有数据该属性有共同的值，就设置上
		var common_value = null
		var inited = false
		for data in rows:
			if not data is Object:
				continue
			if not inited:
				common_value = data.get(prop)
				impl_hint[prop] = {
					"type": i["type"],
					"usage": i["usage"],
					"hint": i["hint"],
					"hint_string": i["hint_string"],
				}
				inited = true
			elif common_value != data.get(prop):
				common_value = null
				break # 在这个属性上，有不同的值，那就不设置了
				
		impl_data[prop] = common_value
		
	var impl_dict_obj = DictionaryObject.new(impl_data, impl_hint)
	
	# 监听值改变的信号，把数据同步到被编辑的对象
	var on_value_changed_ref = []
	var on_value_changed = func(prop, new_value, _old_value):
		var valid = false
		for data in rows:
			if not data is Object or not is_instance_valid(data): # 考虑被编辑对象已经不存在了
				continue
			data.set(prop, new_value)
			valid = true
		if not valid:
			impl_dict_obj.value_changed.disconnect(on_value_changed_ref[0])
			EditorInterface.inspect_object(null)
	on_value_changed_ref.push_back(on_value_changed)
	impl_dict_obj.value_changed.connect(on_value_changed)
	
	# 发送到检查器
	EditorInterface.inspect_object(impl_dict_obj)
	# 全部展开（方便用户修改数据）
	await get_tree().process_frame
	for i: MenuButton in EditorInterface.get_inspector().get_parent().\
		find_children("@MenuButton*", "MenuButton", true, false):
		if i.tooltip_text == tr("Manage object properties."):
			i.get_popup().emit_signal("id_pressed", 12) # 12 is for EXPAND_ALL, @see editor\inspector_dock.h
			break
			
	# 告诉用户正在编辑多个
	# @see editor\gui\editor_object_selector.cpp:EditorObjectSelector::update_path()
	var selector = EditorInterface.get_inspector().get_parent().find_child("@EditorObjectSelector*", true, false)
	if selector != null:
		var label = selector.find_child("@Label*", true, false)
		if label != null:
			label.text = tr("%s (%d Selected)") % [common_class_name, rows.size()]
			
	# history里的名称没法做到修改。history的MenuButton每次弹出前会重新计算，
	# 而我们又获取不到EditorNode::get_singleton()->get_editor_selection_history()，
	# 无法取得对象与Popup item之间的关联。
	# @see editor\inspector_dock.cpp: void InspectorDock::_prepare_history()
	
## 获取高亮行的关联数据
func get_data_of_highlight_rows() -> Array:
	var ret = []
	for i in v_box_container.get_children():
		var style_box: StyleBoxFlat = i.get_theme_stylebox("panel")
		if style_box and style_box.bg_color == HIGHTLIGHT_COLOR:
			ret.push_back(i.get_meta("data"))
	return ret

func mark_last_clicked_row(row_panel: PanelContainer, highlight: bool) -> void:
	last_focused_row = row_panel
	var style_box = row_panel.get_theme_stylebox("panel") as StyleBoxFlat
	style_box.bg_color = HIGHTLIGHT_COLOR if highlight else CLICKED_COLOR
	for i in v_box_container.get_children():
		if i != row_panel:
			var style_box_1 = i.get_theme_stylebox("panel") as StyleBoxFlat
			if style_box_1.bg_color.a < 0.2:
				style_box_1.bg_color.a = 0.0
				
func _on_button_select_all_pressed():
	for i in v_box_container.get_children():
		(i.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = HIGHTLIGHT_COLOR
	if last_focused_row == null:
		last_focused_row = v_box_container.get_child(0)
	if editable:
		inspect_highlight_rows()
		# TODO 选框
		
## 支持多选高亮\多选编辑\shift连选
func highlight_row(row_panel: PanelContainer, skip_await: bool = false, mouse_button_right: bool = false) -> void:
	button_select_all.grab_focus()
	# 是否按下ctrl键、shift键
	var ctrl_pressed = Input.is_key_pressed(KEY_CTRL)
	var shift_pressed = Input.is_key_pressed(KEY_SHIFT)
	
	# 自动滚动到高亮行。
	# 但是一些刚刚添加的新行，需要await才能ensure_control_visible
	if not skip_await:
		await get_tree().create_timer(0.01).timeout
	scroll_container.ensure_control_visible(row_panel)
	
	# shift优先级最高，shift按下，不管左右键，统一按选中处理，而且不影响原来已经选中的项目
	if shift_pressed:
		# 没有上次选的项目，那本次就单独高亮当前行（不影响之前高亮的）
		if last_focused_row == null:
			mark_last_clicked_row(row_panel, true)
		# 有上次选的项目，那本次批量高亮范围内的所有行
		else:
			if last_focused_row == row_panel:
				(row_panel.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = HIGHTLIGHT_COLOR
			else:
				var start = false
				for i in v_box_container.get_children():
					if start:
						(i.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = HIGHTLIGHT_COLOR
						if i == last_focused_row or i == row_panel:
							break
					elif i == last_focused_row or i == row_panel:
						start = true
						(i.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = HIGHTLIGHT_COLOR
		last_focused_row = row_panel
		return
	
	# 本行原先的颜色
	var style_box = row_panel.get_theme_stylebox("panel") as StyleBoxFlat
	var old_color = style_box.bg_color
	
	# 是否取消高亮
	if ctrl_pressed and old_color == HIGHTLIGHT_COLOR and not mouse_button_right:
		mark_last_clicked_row(row_panel, false)
		return
	
	# 高亮本行
	last_focused_row = row_panel
	mark_last_clicked_row(row_panel, true)
	
	# 是否清空其他高亮行
	var clear_other_hightlight = true
	if support_multi_rows_selected:
		# 如果是右键触发的
		if mouse_button_right:
			if ctrl_pressed:
				clear_other_hightlight = false
			elif old_color == HIGHTLIGHT_COLOR:
				clear_other_hightlight = false
		# 左键触发的或默认（相当于）左键触发的
		else:
			if ctrl_pressed:
				clear_other_hightlight = false
	else:
		clear_other_hightlight = true
		
	if clear_other_hightlight:
		for i in v_box_container.get_children():
			if i != row_panel:
				var style_box_1 = i.get_theme_stylebox("panel") as StyleBoxFlat
				style_box_1.bg_color.a = 0.0
			
	#data_of_focused_row = row_panel.get_meta("data", null)
	# 由于一开始等了0.1秒，可能导致检测鼠标按下无效，所以加入检查是否弹出了菜单
	if show_menu and (Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or popup_menu_text.visible) and \
		row_panel.get_rect().has_point(v_box_container.get_local_mouse_position()):
		popup_menu_text.position = DisplayServer.mouse_get_position() # 为什么要用这个方法获取鼠标位置？不知道……在插件中该方法是正确的
		popup_menu_text.set_item_metadata(2, row_panel.get_meta("data"))
		popup_menu_text.set_item_disabled(2, not support_delete_row)
		if not popup_menu_text.visible:
			popup_menu_text.popup()
	else:
		popup_menu_text.set_item_disabled(2, true)
		
## 给外部使用的单独选中某一行
func row_grab_focus(row: int):
	if v_box_container.get_child_count() > row:
		highlight_row(v_box_container.get_child(row))
		
		if datas[row] is Object and editable:
			EditorInterface.inspect_object(datas[row])
			# 全部展开（方便用户修改数据）
			await get_tree().process_frame
			for i: MenuButton in EditorInterface.get_inspector().get_parent().find_children("@MenuButton*", "MenuButton", true, false):
				if i.tooltip_text == tr("Manage object properties."):
					i.get_popup().emit_signal("id_pressed", 12) # 12 is for EXPAND_ALL, @see editor\inspector_dock.h
					break
			
func scroll_to_bottom():
	var v_scroll_bar = scroll_container.get_v_scroll_bar() as VScrollBar
	await get_tree().create_timer(0.1).timeout
	v_scroll_bar.value = v_scroll_bar.max_value

func _label_gui_input(event: InputEvent, col_index: int):
	if show_menu and event is InputEventMouseButton and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		popup_menu_text.position = DisplayServer.mouse_get_position() # 为什么要用这个方法获取鼠标位置？不知道……在插件中该方法是正确的
		popup_menu_text.set_item_metadata(0, col_index)
		#popup_menu_text.set_item_metadata(1, col_index)
		if support_delete_row and popup_menu_text.get_item_metadata(2) != null:
			popup_menu_text.set_item_disabled(2, false)
		else:
			popup_menu_text.set_item_disabled(2, true)
		popup_menu_text.popup()
		
# TODO 二分法搜索
func get_panel_container_under_mouse():
	if not v_box_container.get_rect().has_point(scroll_container.get_local_mouse_position()):
		return null
	for i: PanelContainer in v_box_container.get_children():
		if i.get_rect().has_point(v_box_container.get_local_mouse_position()):
			for j: PanelContainer in i.get_child(0).get_children():
				if j.get_rect().has_point(i.get_child(0).get_local_mouse_position()):
					return j
	return null
	
# 检查一个单元格是不是处于某选区中
func pos_is_selected(pos: Vector2) -> bool:
	for border in selected_borders:
		if border["start"] == pos:
			return true
	var rect = Rect2(pos, Vector2.ONE)
	for border in selected_borders:
		if rect.intersects(border["rect"], false):
			return true
	return false
	
func _on_border_panel_container_gui_input(event: InputEvent, panel_container: PanelContainer):
	if datas.is_empty() or not editable or not (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
	or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)):
		if exclude_mode and start_drag:
			commit_exclude_border()
			printt("8888888888888 exclude end")
		start_drag = false
		exclude_mode = false
		return
		
	# 是否按下ctrl键、shift键
	var ctrl_pressed = Input.is_key_pressed(KEY_CTRL)
	var shift_pressed = Input.is_key_pressed(KEY_SHIFT)
		
	# 触发鼠标事件的panel_container的位置
	var pos_row = panel_container.get_parent().get_parent().get_index()
	var pos_col = panel_container.get_index()
	var old_last_selected_pos = last_selected_pos
	
	if event is InputEventMouseButton:
		if not start_drag:
			# 如果按着shift等同于按原先的位置进行单一选区拖动，所以last_selected_pos不变。
			# 否则要变。
			if not shift_pressed:
				last_selected_pos = Vector2(pos_row, pos_col)
			
		if event.button_index == MOUSE_BUTTON_LEFT:
			#if event.is_pressed(): is_pressed一定是true，否则在上面就return了
			start_drag = true
			start_drag_with_ctrl = ctrl_pressed
			exclude_mode = ctrl_pressed and pos_is_selected(last_selected_pos) # 反选模式
			printt("111111111 start drag", "ctrl:", start_drag_with_ctrl)
		else:
			start_drag = false # 鼠标右键走这行
			exclude_mode = false
			printt("22")
			
	# 经过实验得知，执行到这里时，只要左键在按时，start_drag都为true。但是panel_container却不一定是鼠标下方的那个，
	# 经过实验发现，在鼠标按下且没有释放时，不管怎么移动鼠标，触发鼠标事件（点击和移动事件）的一直是最开始按下触发鼠标事件
	# 的那个panel_container，即便其他panel_container注册了gui_input或mouse_entered，也无法触发。
	if not panel_container.get_rect().has_point(panel_container.get_parent_control().get_local_mouse_position()):
		panel_container = get_panel_container_under_mouse()
		if panel_container == null:
			return
		scroll_container.ensure_control_visible(panel_container) # 超出scroll_container的边界时，要让scroll_container自己滚动
		pos_row = panel_container.get_parent().get_parent().get_index()
		pos_col = panel_container.get_index()
		
	# 如果没拖动（比如右键点击），要清空所有边框
	if not start_drag:
		clear_borders()
		printt("clear")
		
	var x = last_selected_pos.x if start_drag else pos_row
	var y = last_selected_pos.y if start_drag else pos_col
	var start_pos = Vector2(min(x, pos_row), min(y, pos_col)) # 选区左上角
	var end_pos =  Vector2(max(x, pos_row), max(y, pos_col)) # 选区右下角
	var border = {
		"start": last_selected_pos,
		"rect": Rect2(start_pos, end_pos - start_pos + Vector2.ONE),
		"ctrl": start_drag_with_ctrl
	}
	
	# 没按ctrl或按了ctrl时起始点不在选区内
	if not start_drag_with_ctrl or not exclude_mode:
		printt("add border", start_pos, end_pos)
		add_border(border)
		return
		
		
	# ctrl按下时：
	# 1. 点到了一个非选区位置，鼠标按下时所有选区边框立刻消失，起始点位置改变，起始点有绿细边框，无背景。保持按下可拖动扩大选区。鼠标释放时，停止扩大选区，各状态维持当前状况。
	# 2. 点到了某选区中的位置，鼠标按下时在点击位置产生灰色的边框，保持按下可拖动扩大选区，选区背景色较淡，旧选区背景和边框不变。鼠标释放时，新选区变为非选区，旧选区
	# 剩余的部分边框消失，剩余部分被划分为新的若干矩形区域，若没有剩余部分，则选区变为起始点单元格。若旧起始点仍在选区内，则起始点有绿细边框，无背景；
	# 若旧起始点不在选区内，则新划分的若干选区的第一个选区的第一格变为起始点，有绿细边框，无背景。若只剩余一个选区，则选区有边框，无背景。
	if start_drag_with_ctrl:
		if exclude_mode:
			printt("exclude mode 9999999999")
			add_exclude_border(border)
		else:
			printt("777777777777777777777")
			printt("add border", start_pos, end_pos)
			add_border(border)
			
		
func _on_popup_menu_text_index_pressed(index):
	match popup_menu_text.get_item_text(index):
		"Copy Field":
			var col_index = popup_menu_text.get_item_metadata(index)
			if col_index != null:
				var arr_content = []
				for data in get_data_of_highlight_rows():
					var value = data[col_index] if (data is Array or data is Dictionary) \
						else (data as DictionaryObject)._get_by_index(col_index)
					match typeof(value):
						TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME:
							arr_content.push_back(str(value))
						TYPE_OBJECT:
							if value is Resource:
								arr_content.push_back(value.resource_path)
							else:
								arr_content.push_back(var_to_str(value))
						_:
							arr_content.push_back(var_to_str(value))
				DisplayServer.clipboard_set("\n".join(arr_content))
		"Copy Line":
			var arr = []
			for data in get_data_of_highlight_rows():
				var arr_content = []
				for col_index in columns.size():
					var value = data[col_index] if (data is Array or data is Dictionary) \
						else (data as DictionaryObject)._get_by_index(col_index)
					match typeof(value):
						TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME:
							arr_content.push_back(var_to_str(value))
						TYPE_OBJECT:
							if value is Resource:
								arr_content.push_back(var_to_str(value.resource_path))
							else:
								arr_content.push_back(var_to_str(value))
						_:
							arr_content.push_back(var_to_str(value))
				arr.push_back("\t".join(arr_content))
			DisplayServer.clipboard_set("\n".join(arr))
		"Delete":
			var deleted_datas = {}
			var j = -1
			for i in v_box_container.get_children():
				j += 1
				var style_box: StyleBoxFlat = i.get_theme_stylebox("panel")
				if style_box and style_box.bg_color == HIGHTLIGHT_COLOR:
					deleted_datas[j] = i.get_meta("data")
			var indexes = deleted_datas.keys()
			indexes.reverse() # 倒着删除，不然会因为先删了前面的后面的index已经变了
			for i in indexes:
				remove_data_at(i, true) # WARNING 有可能把用户自定义控件释放掉，这个规则缺乏明确的告知
			if not deleted_datas.is_empty():
				row_deleted.emit(deleted_datas)
			
	popup_menu_text.set_item_metadata(index, null)



func _on_focus_entered():
	button_select_all.grab_focus()


func _on_v_box_container_focus_entered():
	button_select_all.grab_focus()


func _on_scroll_container_focus_entered():
	button_select_all.grab_focus()


func _on_button_select_all_focus_exited():
	pass
	#await get_tree().process_frame
	#var focus_owner = get_viewport().gui_get_focus_owner()
	## 如果焦点不在Table中，把检查器中的对象取消掉
	#if focus_owner == null or not mgr.main_panel.is_ancestor_of(focus_owner):
		#var obj = EditorInterface.get_inspector().get_edited_object()
		#if obj != null and obj is DictionaryObject and datas.has(obj):
			#EditorInterface.inspect_object(null)

