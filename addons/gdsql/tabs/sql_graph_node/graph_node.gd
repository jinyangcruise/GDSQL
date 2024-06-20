@tool
extends GraphNode

var mgr: GDSQLWorkbenchManagerClass = Engine.get_singleton("GDSQLWorkbenchManager")

signal node_enabled
signal node_enable_status(enabled: bool)
signal redraw_slot(row, col)

var check_button_enable: CheckButton


## datas的元素是一个长度至少为2的数组，第一个元素是左侧输入port代表的数据，第二个元素是右侧输出port代表的数据。
## 当前两个元素都为null时，这行将不显示port，而显示从第三个元素所代表的控件。
## 元素是DictionaryObject时才会出现port，其他类型都不出现port，如果类型是字符串/数字，则会显示该字符串/数字，否则为空。
## 元素是DictionaryObject时，其所有属性将放到同一行进行显示。
## 元素是DictionaryObject时，若属性名称为下划线开头的，将隐藏属性名称，只保留属性值的设置界面。
## 左侧元素和右侧元素可以相同。
## 元素是Control时，添加到对应的行上。
## ALERT 外部请勿直接在datas上使用pop_front(), pop_back()等改变数组本身的操作，
## 请先使用duplciate浅拷贝一份数据，然后调用本类中的clear()，最后重新对datas进行赋值！
## 否则会产生自定义控件被释放的问题。
var datas: Array[Array]:
	set(val):
		#if datas != val:
		clear()
		datas = val
		redraw()
		
var enabled: bool:
	get:
		return check_button_enable and check_button_enable.button_pressed
	set(val):
		if check_button_enable:
			check_button_enable.button_pressed = val
			if val:
				node_enabled.emit()
			node_enable_status.emit(val)
				
var __property_old_parents = {}
var _redraw_queue = {}
var _mutex: Mutex
var max_btn: TextureButton

func _ready() -> void:
	# enable button
	check_button_enable = CheckButton.new()
	check_button_enable.text = "enable"
	check_button_enable.button_pressed = true
	check_button_enable.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	check_button_enable.toggled.connect(_on_check_button_enable_toggled)
	get_titlebar_hbox().add_child(check_button_enable)
	
	# maximize button
	max_btn = TextureButton.new()
	max_btn.toggle_mode = true
	max_btn.tooltip_text = tr("Double Click") + tr("Titlebar")
	max_btn.stretch_mode = TextureButton.STRETCH_KEEP_CENTERED
	max_btn.texture_normal = preload("res://addons/gdsql/img/maximize.png")
	max_btn.toggled.connect(func(toggled_on: bool):
		if toggled_on:
			max_btn.set_meta("old_size", size)
			var graph_edit = get_parent_control()
			if not graph_edit is GraphEdit:
				return
			if graph_edit.zoom != 1.0:
				get_parent().zoom = 1.0
				await get_tree().create_timer(0.1).timeout
			graph_edit = graph_edit as GraphEdit
			# 移动到节点左上角和窗口左上角对齐
			# edit中心点的偏移
			var center_offset = (graph_edit.get_rect().get_center() - \
				size/2 + graph_edit.scroll_offset) / graph_edit.zoom
			# edit左上角的偏移
			var left_top_cornor_offset = center_offset - graph_edit.size/2
			# node和edit左上角的偏移量
			var diff = position_offset - size/2 - left_top_cornor_offset \
				# graphnode的size的bug补偿
				+ Vector2(0, 80) \
				# top边框
				- Vector2(0, 5) \
				- Vector2.ONE * 8 # 留一个边框
			# edit移动到节点左上角和窗口左上角对齐
			graph_edit.scroll_offset += diff
			size = graph_edit.size - Vector2(16, 20)
		else:
			var graph_edit = get_parent_control()
			if not graph_edit is GraphEdit:
				return
			size = max_btn.get_meta("old_size")
			# 认为目前和左上角是对齐的。（zoom=1时，zoom=1是大概率的）
			# 移动到中心
			# edit中心点的偏移
			var center_offset = (graph_edit.get_rect().get_center() - \
				size/2 + graph_edit.scroll_offset) / graph_edit.zoom
			# node和edit中心点的偏移
			var diff = position_offset - center_offset
			graph_edit.scroll_offset += diff
	)
	get_titlebar_hbox().add_child(max_btn)
	
	# close button
	var close_btn = TextureButton.new()
	close_btn.stretch_mode = TextureButton.STRETCH_KEEP_CENTERED
	close_btn.texture_normal = preload("res://addons/gdsql/img/xmark.png")
	close_btn.pressed.connect(func():
		if get_parent_control() is GraphEdit:
			var nodes: Array[StringName] = [name]
			(get_parent_control() as GraphEdit).delete_nodes_request.emit(nodes)
	)
	get_titlebar_hbox().add_child(close_btn)
	
	# 队列
	_mutex = Mutex.new()
	RenderingServer.frame_post_draw.connect(_flush_redraw_queue)
	
	redraw()
	
func _flush_redraw_queue():
	if _redraw_queue.is_empty():
		return
		
	_mutex.lock()
	# 再次确认
	if _redraw_queue.is_empty():
		_mutex.unlock()
		return
		
	for row in _redraw_queue:
		for col in _redraw_queue[row]:
			redraw_slot_control(row, col)
			
	_redraw_queue.clear()
	_mutex.unlock()

func clear():
	disconnect_focused_selected_propagate(self)
	for i in __property_old_parents:
		if i:
			disconnect_focused_propagate(i)
			if __property_old_parents[i].get_ref():
				i.reparent(__property_old_parents[i].get_ref())
			#if __property_old_parents[i]:
				#i.reparent(__property_old_parents[i])
			else:
				i.queue_free()
			
	__property_old_parents.clear()
	
	if is_node_ready():
		# 把自定义控件从树中剥离出来，不然会给下面的queue_free带来麻烦
		if datas and !datas.is_empty():
			for arr in datas:
				for data in arr:
					if data is Control:
						if data.get_parent_control():
							data.get_parent_control().remove_child(data)
							
		var children = get_children()
		for i in children:
			if i and !i.is_queued_for_deletion():
				remove_child(i)
				i.queue_free()
				
func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		clear()
		
		if datas and !datas.is_empty():
			for arr in datas:
				for data in arr:
					if data is Control:
						data.queue_free()
			datas = []
			
		mgr = null
		max_btn = null
		
func redraw():
	clear()
	if datas and !datas.is_empty() and is_inside_tree():
		#var graph_node = GraphNode.new()
		#graph_node.show_close = true
		#graph_node.resizable = true
		var index = -1
		for arr in datas:
			index += 1
			var hb = HBoxContainer.new()
			#var has_content = false
			#hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
			var left = 0
			if arr.size() > 2:
				assert(arr[0] == null and arr[1] == null, "first two datas must be null if datas' size is larger than 2")
			for data in arr:
				left += 1
				if data != null:
					if left == 1:
						set_slot_enabled_left(index, true)
					elif left == 2:
						set_slot_enabled_right(index, true)
						
					if data is String or data is int or data is float:
						if data is String and data == "":
							hb.add_child(Control.new())
						else:
							#has_content = true
							var label = Label.new()
							label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if left == 1 else HORIZONTAL_ALIGNMENT_RIGHT
							label.text = str(data)
							label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
							label.localize_numeral_system = false
							label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
							hb.add_child(label)
					elif data is DictionaryObject:
						#has_content = true
						# 一些控件依赖inspector，为了简化，所有情况都使用inspector。
						# 比如：EditorPropertyResource，如果不放到一个inspector中的话，reparent的时候（它想折叠资源）会报错，影响体验。
						var inspector = EditorInspector.new()
						inspector.queue_redraw()
						inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
						inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
						inspector.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
						hb.add_child(inspector)
						
						# 允许用户使用垂直方式排列属性（默认横向）
						var p_container
						if data.get_meta("align", "horizontal") == "vertical":
							p_container = VBoxContainer.new()
						else:
							p_container = HBoxContainer.new()
						p_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
						p_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
						hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
						inspector.add_child(p_container)
						
						EditorInterface.inspect_object(data)
						var properties = data._get_property_list().map(func(v): return v["name"])
						var editor_properties = EditorInterface.get_inspector().find_children("@EditorProperty*", "", true, false)
						for i in properties.size():
							# 下划线开头的隐藏label。隐藏方法是把控件整个添加到一个能按比例隐藏子控件的控件中
							var editor_property = editor_properties[i]
							# 只有让检查器显示这个属性，才能修改这个属性。否则修改的是检查器当前显示的属性。
							connect_focused_propagate(editor_property, data)
							__property_old_parents[editor_property] = weakref(editor_property.get_parent())
							editor_property.size_flags_horizontal = Control.SIZE_EXPAND_FILL
							editor_property.size_flags_vertical = Control.SIZE_EXPAND_FILL
							editor_property.add_theme_stylebox_override("bg_selected", StyleBoxEmpty.new())
							if (properties[i] as String).begins_with("_"):
								var container = preload("res://addons/gdsql/tabs/sql_graph_node/cut_control.tscn").instantiate()
								container.invisible_ratio = 0.5
								container.control = editor_property
								container.set_meta("cut_control", true)
								p_container.add_child(container)
							else:
								editor_property.reparent(p_container)
								
					elif data is Control:
						if data.get_class() == "Control" and data.get_child_count() == 0:
							#has_content = false
							pass
						else:
							#has_content = true
							if data.size_flags_vertical == Control.SIZE_EXPAND_FILL:
								hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
						if data.get_parent() and data.get_parent() != hb:
							data.reparent(hb)
						else:
							hb.add_child(data)
			#if hb.get_child_count() == 0 or not has_content:
				#hb.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			#else:
				#hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
			add_child(hb)
	connect_focused_selected_propagate(self)
	
## 把要刷新的控件推送到队列中
func push_redraw_slot_control(slot_row_index, slot_col_index):
	_mutex.lock()
	var cols = _redraw_queue.get(slot_row_index, {})
	cols[slot_col_index] = true
	_redraw_queue[slot_row_index] = cols
	_mutex.unlock()
	
## 强制刷新某个栏位的控件。
func redraw_slot_control(slot_row_index, slot_col_index):
	# 记录焦点控件，用于恢复（如果不恢复，正在修改被刷新控件的内容，则会造成无法连续输入或用户输入后数据并没生效
	var focus_owner = get_viewport().gui_get_focus_owner()
	var hb = get_child(slot_row_index)
	
	# 如果请求刷新某hb里的内容，但是该hb里边的内容正在被编辑，就会造成无法输入。
	# 所以等失去焦点的时候再重绘或者要刷新的地方和正被编辑的地方无关时再重绘，免得影响连续输入或用户输入后数据并没生效。
	if focus_owner and hb.is_ancestor_of(focus_owner):
		push_redraw_slot_control(slot_row_index, slot_col_index)
		return
		
	var data = datas[slot_row_index][slot_col_index]
	if slot_col_index == 0:
		if data == null:
			set_slot_enabled_left(slot_row_index, false)
		else:
			set_slot_enabled_left(slot_row_index, true)
	elif slot_col_index == 1:
		if data == null:
			set_slot_enabled_right(slot_row_index, false)
		else:
			set_slot_enabled_right(slot_row_index, true)
			
	# 释放旧的EditorProperty
	var arr = []
	search_editor_property(hb, arr)
	
	for ep: EditorProperty in arr:
		# parent is a cut_control
		if ep.get_parent() and ep.get_parent().has_meta("cut_control"):
			ep.get_parent().control = null
			
		disconnect_focused_propagate(ep)
		if __property_old_parents[ep].get_ref():
			if ep.get_parent():
				ep.reparent(__property_old_parents[ep].get_ref())
			else:
				__property_old_parents[ep].get_ref().add_child(ep)
			__property_old_parents.erase(ep)
		else:
			__property_old_parents.erase(ep)
			ep.queue_free()
			
	while hb.get_child_count() > 0:
		var c = hb.get_child(0)
		hb.remove_child(c)
		c.queue_free()
		
	# 添加新的
	if data is String or data is int or data is float:
		if data is String and data == "":
			hb.add_child(Control.new())
		else:
			var label = Label.new()
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if slot_row_index == 0 else HORIZONTAL_ALIGNMENT_RIGHT
			label.text = str(data)
			label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			label.localize_numeral_system = false
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hb.add_child(label)
	elif data is Control:
		if data.get_class() == "Control" and data.get_child_count() == 0:
			pass
		else:
			if data.size_flags_vertical == Control.SIZE_EXPAND_FILL:
				hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
		if data.get_parent() and data.get_parent() != hb:
			data.reparent(hb)
		else:
			hb.add_child(data)
	elif data is DictionaryObject:
		# 一些控件依赖inspector，为了简化，所有情况都使用inspector
		var inspector = EditorInspector.new()
		inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
		inspector.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		hb.add_child(inspector)
		
		# 允许用户使用垂直方式排列属性（默认横向）
		var p_container
		if data.get_meta("align", "horizontal") == "vertical":
			p_container = VBoxContainer.new()
		else:
			p_container = HBoxContainer.new()
		p_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
		hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		inspector.add_child(p_container)
		
		EditorInterface.inspect_object(data)
		var properties = data._get_property_list().map(func(v): return v["name"])
		var editor_properties = EditorInterface.get_inspector().find_children("@EditorProperty*", "", true, false)
		for i in properties.size():
			# 下划线开头的隐藏label。隐藏方法是把控件整个添加到一个能按比例隐藏子控件的控件中
			var editor_property: EditorProperty = editor_properties[i]
			
			# 只有让检查器显示这个属性，才能修改这个属性。否则修改的是检查器当前显示的属性。
			connect_focused_propagate(editor_property, data)
			__property_old_parents[editor_property] = weakref(editor_property.get_parent())
			editor_property.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			editor_property.size_flags_vertical = Control.SIZE_EXPAND_FILL
			editor_property.add_theme_stylebox_override("bg_selected", StyleBoxEmpty.new())
			if (properties[i] as String).begins_with("_"):
				var container = preload("res://addons/gdsql/tabs/sql_graph_node/cut_control.tscn").instantiate()
				container.invisible_ratio = 0.5
				container.control = editor_property
				container.set_meta("cut_control", true)
				p_container.add_child(container)
			else:
				editor_property.reparent(p_container)
				
	# 上面的过程中几乎肯定会改变检查器当前编辑的对象，从而影响原来正被编辑的对象的修改，所以需要激活原来的对象编辑
	if focus_owner:
		focus_owner.emit_signal("focus_entered") # 可以触发之前绑定的函数：editor_property_focused
		
	redraw_slot.emit(slot_row_index, slot_col_index)
	
	
func search_editor_property(container: Control, ret: Array):
	if container is EditorProperty:
		ret.push_back(container)
	elif container.get_child_count() > 0:
		for i in container.get_children():
			search_editor_property(i, ret)
				
## 返回第一个匹配该属性名称的值
func get_prop_value(prop):
	for row_datas in datas:
		for data in row_datas:
			if data is DictionaryObject:
				if data._get(prop) != null:
					return data._get(prop)
	return null
	
#func hide_property_control(index):
	#var p = get_child(index)
	#if p is HBoxContainer and p.get_child(0) is EditorProperty:
		#p.get_child(0).get_child(0).hide()
		#
#func show_property_control(index):
	#var p = get_child(index)
	#if p is HBoxContainer and p.get_child(0) is EditorProperty:
		#p.get_child(0).get_child(0).show()
	
func _on_check_button_enable_toggled(button_pressed: bool) -> void:
	enabled = button_pressed
	
func _bind_data_control_focus_entered():
	if get_parent():
		for i in get_parent().get_children():
			if i is GraphNode and i != self:
				i.selected = false
	selected = true
	
func connect_focused_selected_propagate(control: Control):
	if control.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		if not control.is_connected("focus_entered", _bind_data_control_focus_entered):
			control.focus_entered.connect(_bind_data_control_focus_entered)
	for child in control.get_children(true):
		if child is Control:
			connect_focused_selected_propagate(child)
			
func disconnect_focused_selected_propagate(control: Control):
	if control.is_connected("focus_entered", _bind_data_control_focus_entered):
		control.focus_entered.disconnect(_bind_data_control_focus_entered)
	for child in control.get_children(true):
		if child is Control:
			disconnect_focused_propagate(child)
			
func connect_focused_propagate(control: Control, data):
	for child in control.get_children(true):
		if child is Control:
			connect_focused_propagate(child, data)
			if child.mouse_filter != Control.MOUSE_FILTER_IGNORE and child.has_signal("focus_entered"):
				if not (child as Control).is_connected("focus_entered", editor_property_focused):
					child.focus_entered.connect(editor_property_focused.bind(data))
					
func disconnect_focused_propagate(control):
	for child in control.get_children(true):
		if child is Control:
			disconnect_focused_propagate(child)
			if (child as Control).is_connected("focus_entered", editor_property_focused):
				child.focus_entered.disconnect(editor_property_focused)
				
func editor_property_focused(data):
	EditorInterface.inspect_object(data)
	
func _on_resize_request(new_minsize):
	size = new_minsize
	
func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	if event.is_pressed() and event.double_click and \
	get_titlebar_hbox().get_rect().has_point(get_local_mouse_position()):
		max_btn.button_pressed = not max_btn.button_pressed
		get_viewport().set_input_as_handled()
