@tool
extends VBoxContainer

signal row_clicked(row_index: int, mouse_button_index: int, data)
signal row_deleted(datas) # {index: data}

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
@onready var button_select_all = $Control/ButtonSelectAll



## 表格是否可编辑（datas中的元素必须是DictionaryObject才有效）
@export var editable: bool = false

## 是否显示默认的右键菜单（包括copy、delete）
@export var show_menu: bool = false

## 是否支持从右键菜单delete行
@export var support_delete_row: bool = false

## 是否支持多行选择（高亮）
@export var support_multi_rows_selected: bool = false

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
				
			if not _entered_tree:
				await tree_entered
			if is_inside_tree():
				for i in 50:
					await create_tween().tween_callback(func(): realign_rows()).set_delay(0.1).finished
		
var _entered_tree = false
## 表头
var buttons: Array[Button] = []
var controls: Array = []
# 最后focus的行
var last_focused_row
const HIGHTLIGHT_COLOR = Color(Color.MEDIUM_PURPLE, 0.788)
const CLICKED_COLOR = Color(Color.LIGHT_BLUE, 0.1)
#var data_of_focused_row

func _ready() -> void:
	reset_header()
	await get_tree().process_frame
	datas = datas
	label_max_lines_visible = label_max_lines_visible
	if is_inside_tree() and !datas.is_empty():
		for i in 50:
			await create_tween().tween_callback(func(): realign_rows()).set_delay(0.1).finished
	
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
		
func move_data(from: int, to: int):
	if from != to:
		var data = datas[from]
		datas.remove_at(from)
		datas.insert(to, data)
		if is_node_ready():
			var row = v_box_container.get_child(from)
			v_box_container.move_child(row, to)
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
	var style_box: StyleBoxFlat = a_row.get_theme_stylebox("panel").duplicate()
	a_row.add_theme_stylebox_override("panel", style_box)
	
	data.insert(0, "")
	data.push_back("")
	for i in data.size():
		var control: Control
		var handled = false
		
		# 如果该数据提供了自定义显示控件，就直接使用
		if i > 0 and i < data.size() - 1 and a_data is DictionaryObject:
			a_data = a_data as DictionaryObject
			control = a_data.get_custom_display_control(a_data.__get_index_prop(i-1))
			handled = control != null
			
		# 否则，用表格自带的显示控件
		if not handled:
			match typeof(data[i]):
				TYPE_BOOL:
					handled = true
					control = check_box_model.duplicate()
					control.button_pressed = data[i]
					control.tooltip_text = str(data[i])
					control.gui_input.connect(_label_gui_input.bind(i-1), CONNECT_DEFERRED)
					if i > 0 and i < data.size() - 1 and a_data is DictionaryObject:
						a_data = a_data as DictionaryObject
						var callback = func(new_value, control_ref: WeakRef):
							var ctl = control_ref.get_ref()
							if ctl:
								ctl.button_pressed = new_value
						 # 绕这么一圈用弱引用是怕内存溢出;i-1是因为data前面比column多一个空值
						a_data.set_update_callback(a_data.__get_index_prop(i-1), callback.bind(weakref(control)))
				TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME:
					handled = true
					control = label_model.duplicate()
					control.text = str(data[i])
					control.tooltip_text = str(data[i])
					control.gui_input.connect(_label_gui_input.bind(i-1), CONNECT_DEFERRED)
					if i > 0 and i < data.size() - 1 and a_data is DictionaryObject:
						a_data = a_data as DictionaryObject
						var callback = func(new_value, control_ref: WeakRef):
							var ctl = control_ref.get_ref()
							if ctl:
								ctl.text = str(new_value)
						a_data.set_update_callback(a_data.__get_index_prop(i-1), callback.bind(weakref(control)))
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
							control.gui_input.connect(_label_gui_input.bind(i-1), CONNECT_DEFERRED)
							if i > 0 and i < data.size() - 1 and a_data is DictionaryObject:
								var callback = func(new_value, control_ref: WeakRef):
									var ctl = control_ref.get_ref()
									if ctl:
										ctl.texture = new_value
								a_data.set_update_callback(a_data.__get_index_prop(i-1), callback.bind(weakref(control)))
						else:
							## 注意：EditorResourcePicker有些慢，如果数据量比较大，会很卡，所以尽可能把常用的类型单独处理，比如上面的Texture2D
							var editor_resource_picker := EditorResourcePicker.new()
							#editor_resource_picker.mouse_filter = Control.MOUSE_FILTER_IGNORE
							#editor_resource_picker.propagate_call("set_mouse_filter", [Control.MOUSE_FILTER_IGNORE])
							editor_resource_picker.base_type = "Resource"
							editor_resource_picker.edited_resource = data[i]
							editor_resource_picker.editable = false
							control = editor_resource_picker
							control.gui_input.connect(_label_gui_input.bind(i-1), CONNECT_DEFERRED)
							if i > 0 and i < data.size() - 1 and a_data is DictionaryObject:
								var callback = func(new_value, control_ref: WeakRef):
									var ctl = control_ref.get_ref()
									if ctl:
										ctl.edited_resource = new_value
								a_data.set_update_callback(a_data.__get_index_prop(i-1), callback.bind(weakref(control)))
						#control = texture_rect_model.duplicate()
						#control.texture = data[i]
					elif data[i] is Control:
						handled = true
						control = data[i]
					## TODO 可能需要添加其他有必要预览的类型
				
		if not handled:
			control = label_model.duplicate()
			control.text = var_to_str(data[i])
			control.gui_input.connect(_label_gui_input.bind(i-1), CONNECT_DEFERRED)
			if i > 0 and i < data.size() - 1 and a_data is DictionaryObject and a_data.has_method("set_update_callback"):
				a_data = a_data as DictionaryObject
				var callback = func(new_value, control_ref: WeakRef):
					var ctl = control_ref.get_ref()
					if ctl:
						ctl.text = var_to_str(new_value)
				a_data.set_update_callback(a_data.__get_index_prop(i-1), callback.bind(weakref(control)))
			
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
		if r == last_focused_row:
			last_focused_row = null
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
