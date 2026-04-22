@tool
extends GraphNode

signal node_enabled
signal node_enable_status(enabled: bool)
signal redraw_slot(row, col)
signal redraw_slots_finished

var check_button_enable: CheckButton

@export var debug_mode = false
var line_edit_debug: LineEdit
var button_debug: Button
var window_size: Vector2

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
## 如果要在修改datas的时候保留节点间的连接，则需要使用 datas[index] = [xx] 修改数据，然后调用 push_redraw_slot_control() 、
## shrink_by_data_count() 来修改显示。
## 而不是对 datas 进行赋值。
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
				
var _redraw_queue = {}
var _mutex: Mutex
var max_btn: TextureButton

func _ready() -> void:
	set_translation_domain("godot.editor")
	var tween = create_tween()
	tween.set_loops(-1)
	tween.tween_callback(_on_timer_timeout).set_delay(0.1)
	
	if debug_mode:
		var hbox = HBoxContainer.new()
		hbox.name = 'hbox_for_debug'
		add_child(hbox, true, Node.INTERNAL_MODE_BACK)
		line_edit_debug = LineEdit.new()
		line_edit_debug.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(line_edit_debug)
		button_debug = Button.new()
		hbox.add_child(button_debug)
		button_debug.text = "debug"
		button_debug.pressed.connect(_on_button_debug_pressed)
		
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
				+ Vector2(0, 64) \
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
		window_size = size
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
		
	var queue = _redraw_queue.duplicate(true)
	_redraw_queue.clear()
	for row in queue:
		for col in queue[row]:
			redraw_slot_control(row, col)
			
	_mutex.unlock()
	if _redraw_queue.is_empty():
		redraw_slots_finished.emit()
		
func clear():
	disconnect_focused_selected_propagate(self)
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
			if i and !i.is_queued_for_deletion() and not (i == line_edit_debug or i == button_debug):
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
			add_child(hb)
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
							var c = Control.new()
							c.set_meta("col_index", left - 1)
							hb.add_child(c)
						else:
							#has_content = true
							var label = Label.new()
							label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if left == 1 else HORIZONTAL_ALIGNMENT_RIGHT
							label.text = str(data)
							label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
							label.localize_numeral_system = false
							label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
							label.set_meta("col_index", left - 1)
							hb.add_child(label)
					elif data is GDSQL.DictionaryObject:
						#has_content = true
						# 一些控件依赖inspector，为了简化，所有情况都使用inspector。
						# 比如：EditorPropertyResource，如果不放到一个inspector中的话，reparent的时候（它想折叠资源）会报错，影响体验。
						var inspector = EditorInspector.new()
						inspector.queue_redraw()
						inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
						inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
						inspector.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
						inspector.set_meta("col_index", left - 1)
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
						
						var plist = data._get_property_list().filter(func(v):
							return not (v["usage"] & PROPERTY_USAGE_CATEGORY or v["usage"] & PROPERTY_USAGE_GROUP \
								or v["usage"] & PROPERTY_USAGE_SUBGROUP))
						for prop in plist:
							var editor = EditorInspector.instantiate_property_editor(
								data, prop.type, prop.name, prop.hint, prop.hint_string, prop.usage)
							p_container.add_child(editor)
							editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
							#editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
							editor.add_theme_stylebox_override("bg_selected", StyleBoxEmpty.new())
							editor.set_object_and_property(data, prop.name)
							if prop.name.begins_with("_") and \
							not editor.name.contains("EditorPropertyMultilineText") \
							and not editor.name.contains("EditorPropertyArray"):
								editor.draw_label = false
							else:
								editor.label = prop.name
							editor.property_changed.connect(_prop_change.bind(data, editor))
							editor.selected.connect(_prop_selected.bind(editor, p_container))
							editor.update_property()
							
							# 1.可以让检查器中的修改反映到GraphNode中
							# 2.间接实现了EditorPropertyArray、EditorPropertyDictionary等元素操作比如交换位置、增删改等
							# NOTICE 如果在lambda中直接使用editor_property时，会在redraw的时候报错，因为editor_property被替换成新的控件了
							# (Lambda capture at index %d was freed. Passed "null" instead.)
							# 所以用bind传一下。。过于hack了也是。。
							var callable_ref = []
							var callable = func(_p, new, old, ep):
								if ep and is_instance_valid(ep):
									if new != old:
										ep.update_property()
								else:
									var list = data.get_signal_connection_list("value_changed")
									for i in list:
										if i.callable == callable_ref[0]:
											var bound_ep = (i.callable as Callable).get_bound_arguments()[0]
											if not bound_ep or not is_instance_valid(bound_ep):
												data.value_changed.disconnect(i.callable)
												
							callable_ref.push_back(callable.bind(editor))
							data.value_changed.connect(callable_ref[0])
							
							if editor.name.contains("EditorPropertyArray") or \
							editor.name.contains("EditorPropertyDictionary"):
								# 没展开的时候去掉背景色
								var btn = editor.find_child("@Button*", false, false)
								if btn:
									(btn as Button).pressed.connect(func():
										# 2说明没有展开，3说明展开了
										if editor.get_child_count(true) == 2:
											editor.add_theme_stylebox_override("bg_selected", StyleBoxEmpty.new())
									)
							elif editor.name.contains("EditorPropertyResource"):
								# 没展开的时候去掉背景色
								var btn = editor.find_child("@Button*", true, false)
								if btn:
									(btn as Button).pressed.connect(func():
										# 没找到子EditorInspector，说明没展开
										if not editor.find_child("@EditorInspector*", false, false):
											editor.add_theme_stylebox_override("bg_selected", StyleBoxEmpty.new())
									)
									
							# 自定义显示控件
							var ctl = data.get_custom_display_control(prop.name)
							if ctl:
								for i in editor.get_children(true):
									i.hide()
								if editor.get_child(0, true) is BoxContainer:
									var box = editor.get_child(0, true)
									box.show()
									for i in box.get_children(true):
										i.hide()
									box.add_child(ctl)
								else:
									editor.add_child(ctl)
					elif data is Control:
						if data.get_class() == "Control" and data.get_child_count() == 0:
							#has_content = false
							pass
						else:
							#has_content = true
							if data.size_flags_vertical == Control.SIZE_EXPAND_FILL:
								hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
						data.set_meta("col_index", left - 1)
						if data.get_parent() and data.get_parent() != hb:
							data.reparent(hb)
						else:
							hb.add_child(data)
			#if hb.get_child_count() == 0 or not has_content:
				#hb.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			#else:
				#hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	connect_focused_selected_propagate(self)
	
@warning_ignore("unused_parameter")
func _prop_change(property: StringName, value: Variant, field: StringName, 
changing: bool, dictionary_object: GDSQL.DictionaryObject, editor: EditorProperty):
	dictionary_object.set(property, value)
	if typeof(value) > TYPE_ARRAY:
		editor.update_property()
		
@warning_ignore("unused_parameter")
func _prop_selected(path: String, focusable_idx: int, editor: EditorProperty, editor_container: Control):
	for i in editor_container.get_children():
		if not i is EditorProperty or i == editor:
			continue
		if i.is_selected():
			i.deselect()
			
## 把要刷新的控件推送到队列中
func push_redraw_slot_control(slot_row_index, slot_col_index):
	_mutex.lock()
	var cols = _redraw_queue.get(slot_row_index, {})
	cols[slot_col_index] = true
	_redraw_queue[slot_row_index] = cols
	_mutex.unlock()
	
## 根据datas的行数，减少渲染旧的行。减少的行内如果有自定义组件，会直接被free。
func shrink_by_data_count():
	var datas_size = datas.size()
	if get_child_count() > datas_size:
		push_redraw_slot_control(datas_size, 0)
		
## 强制刷新某个栏位的控件。
func redraw_slot_control(slot_row_index, slot_col_index):
	# 记录焦点控件，用于恢复（如果不恢复，正在修改被刷新控件的内容，则会造成无法连续输入或用户输入后数据并没生效
	var focus_owner = get_viewport().gui_get_focus_owner()
	
	if slot_row_index >= datas.size():
		var removed = false
		for i in range(slot_row_index, get_child_count(), 1):
			var child = get_child(i)
			remove_child(child)
			child.queue_free()
			removed = true
			
		if removed and focus_owner:
			focus_owner.emit_signal("focus_entered") # 可以触发之前绑定的函数：editor_property_focused
			
		return
		
	var hb
	if slot_row_index >= get_child_count():
		var new_hb_count = slot_row_index - get_child_count() + 1
		for i in new_hb_count:
			hb = HBoxContainer.new()
			add_child(hb)
	else:
		hb = get_child(slot_row_index)
		
	# 如果请求刷新某hb里的内容，但是该hb里边的内容正在被编辑，就会造成无法输入。
	# 所以等失去焦点的时候再重绘或者要刷新的地方和正被编辑的地方无关时再重绘，免得影响连续输入或用户输入后数据并没生效。
	if focus_owner and hb.is_ancestor_of(focus_owner):
		push_redraw_slot_control(slot_row_index, slot_col_index)
		return
		
	# 比如原来datas长度是4，现在datas长度是2，现在请求刷新后两个，那么直接删除多余的控件
	if slot_col_index >= datas[slot_row_index].size():
		var remove = []
		for c in hb.get_children():
			if c.get_meta("col_index") >= slot_col_index:
				remove.add_child(c)
		for c in remove:
			hb.remove_child(c)
			c.queue_free()
			
		if focus_owner and not remove.is_empty():
			focus_owner.emit_signal("focus_entered") # 可以触发之前绑定的函数：editor_property_focused
			
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
			
	var to_remain = []
	var to_remove = []
	for c in hb.get_children():
		if c.get_meta("col_index") == slot_col_index:
			to_remove.push_back(c)
		else:
			to_remain.push_back(c)
			
	for c in to_remove:
		hb.remove_child(c)
		if not c.is_queued_for_deletion():
			c.queue_free()
			
	for c in to_remain:
		if c.get_meta("col_index") > slot_col_index:
			hb.remove_child(c) # 按照顺序，待会儿要重新添加在后面
			
	# 添加新的
	if data is String or data is int or data is float:
		if data is String and data == "":
			var c = Control.new()
			c.set_meta("col_index", slot_col_index)
			hb.add_child(c)
		else:
			var label = Label.new()
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if slot_row_index == 0 else HORIZONTAL_ALIGNMENT_RIGHT
			label.text = str(data)
			label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			label.localize_numeral_system = false
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.set_meta("col_index", slot_col_index)
			hb.add_child(label)
	elif data is Control:
		if data.get_class() == "Control" and data.get_child_count() == 0:
			pass
		else:
			if data.size_flags_vertical == Control.SIZE_EXPAND_FILL:
				hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
		data.set_meta("col_index", slot_col_index)
		if data.get_parent():
			if data.get_parent() != hb:
				data.reparent(hb)
		else:
			hb.add_child(data)
	elif data is GDSQL.DictionaryObject:
		# 一些控件依赖inspector，为了简化，所有情况都使用inspector
		var inspector = EditorInspector.new()
		inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		#inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
		inspector.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		inspector.set_meta("col_index", slot_col_index)
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
		
		var plist = data._get_property_list().filter(func(v):
			return not (v["usage"] & PROPERTY_USAGE_CATEGORY or v["usage"] & PROPERTY_USAGE_GROUP \
				or v["usage"] & PROPERTY_USAGE_SUBGROUP))
		for prop in plist:
			var editor = EditorInspector.instantiate_property_editor(
				data, prop.type, prop.name, prop.hint, prop.hint_string, prop.usage)
			p_container.add_child(editor)
			editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
			editor.add_theme_stylebox_override("bg_selected", StyleBoxEmpty.new())
			editor.set_object_and_property(data, prop.name)
			if prop.name.begins_with("_") and \
			not editor.name.contains("EditorPropertyMultilineText") \
			and not editor.name.contains("EditorPropertyArray"):
				editor.draw_label = false
			else:
				editor.label = prop.name
			editor.property_changed.connect(_prop_change.bind(data, editor))
			editor.selected.connect(_prop_selected.bind(editor, p_container))
			editor.update_property()
			
			# 1.可以让检查器中的修改反映到GraphNode中
			# 2.间接实现了EditorPropertyArray、EditorPropertyDictionary等元素操作比如交换位置、增删改等
			# NOTICE 如果在lambda中直接使用editor_property时，会在redraw的时候报错，因为editor_property被替换成新的控件了
			# (Lambda capture at index %d was freed. Passed "null" instead.)
			# 所以用bind传一下。。过于hack了也是。。
			var callable_ref = []
			var callable = func(_p, new, old, ep):
				if ep and is_instance_valid(ep):
					if new != old:
						ep.update_property()
				else:
					var list = data.get_signal_connection_list("value_changed")
					for i in list:
						if i.callable == callable_ref[0]:
							var bound_ep = (i.callable as Callable).get_bound_arguments()[0]
							if not bound_ep or not is_instance_valid(bound_ep):
								data.value_changed.disconnect(i.callable)
								
			callable_ref.push_back(callable.bind(editor))
			data.value_changed.connect(callable_ref[0])
			
			if editor.name.contains("EditorPropertyArray") or \
			editor.name.contains("EditorPropertyDictionary"):
				# 没展开的时候去掉背景色
				var btn = editor.find_child("@Button*", false, false)
				if btn:
					(btn as Button).pressed.connect(func():
						# 2说明没有展开，3说明展开了
						if editor.get_child_count(true) == 2:
							editor.add_theme_stylebox_override("bg_selected", StyleBoxEmpty.new())
					)
			elif editor.name.contains("EditorPropertyResource"):
				# 没展开的时候去掉背景色
				var btn = editor.find_child("@Button*", true, false)
				if btn:
					(btn as Button).pressed.connect(func():
						# 没找到子EditorInspector，说明没展开
						if not editor.find_child("@EditorInspector*", false, false):
							editor.add_theme_stylebox_override("bg_selected", StyleBoxEmpty.new())
					)
					
			# 自定义显示控件
			var ctl = data.get_custom_display_control(prop.name)
			if ctl:
				for i in editor.get_children(true):
					i.hide()
				if editor.get_child(0, true) is BoxContainer:
					var box = editor.get_child(0, true)
					box.show()
					for i in box.get_children(true):
						i.hide()
					box.add_child(ctl)
				else:
					editor.add_child(ctl)
	for c in to_remain:
		if c.get_meta("col_index") > slot_col_index:
			hb.add_child(c)
			
	# 上面的过程中几乎肯定会改变检查器当前编辑的对象，从而影响原来正被编辑的对象的修改，所以需要激活原来的对象编辑
	if focus_owner:
		focus_owner.emit_signal("focus_entered") # 可以触发之前绑定的函数：editor_property_focused
		
	redraw_slot.emit(slot_row_index, slot_col_index)
	
## 返回第一个匹配该属性名称的值
func get_prop_value(prop):
	for row_datas in datas:
		for data in row_datas:
			if data is GDSQL.DictionaryObject:
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
	raise_request.emit()
	
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
			disconnect_focused_selected_propagate(child)
			
func _on_resize_end(new_size: Vector2) -> void:
	size = new_size
	window_size = size
	
func _on_resize_request(new_minsize):
	size = new_minsize
	window_size = size
	
func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	if event.is_pressed() and event.double_click and \
	get_titlebar_hbox().get_rect().has_point(get_local_mouse_position()):
		max_btn.button_pressed = not max_btn.button_pressed
		get_viewport().set_input_as_handled()
		
func _on_button_debug_pressed() -> void:
	if not line_edit_debug.text.is_empty():
		var c = find_child(line_edit_debug.text, true, false)
		if c:
			EditorInterface.inspect_object(c)
	else:
		print_tree_pretty()
		
func _on_timer_timeout() -> void:
	if window_size == Vector2.ZERO:
		window_size = size
	if size != window_size:
		size = window_size
		
## 修复切换到别的地方再回来的时候大小发生了变化的问题
var _size_before_invisible: Vector2 = Vector2.ZERO
func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		if _size_before_invisible != Vector2.ZERO:
			size = _size_before_invisible
	else:
		_size_before_invisible = size
