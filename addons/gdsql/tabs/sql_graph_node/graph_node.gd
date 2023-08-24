@tool
extends GraphNode

var mgr: GDSQLWorkbenchManagerClass = Engine.get_singleton("GDSQLWorkbenchManager")

signal node_enabled
signal node_enable_status(enabled: bool)

@onready var check_button_enable: CheckButton = $CheckButtonEnable

## datas的元素是一个长度至少为2的数组，第一个元素是左侧输入port代表的数据，第二个元素是右侧输出port代表的数据。
## 当前两个元素都为null时，这行将不显示port，而显示从第三个元素所代表的控件。
## 元素是DictionaryObject时才会出现port，其他类型都不出现port，如果类型是字符串/数字，则会显示该字符串/数字，否则为空。
## 元素是DictionaryObject时，其所有属性将放到同一行进行显示。
## 元素是DictionaryObject时，若属性名称为下划线开头的，将隐藏属性名称，只保留属性值的设置界面。
## 左侧元素和右侧元素可以相同。
## 元素是Control时，添加到对应的行上。
var datas: Array[Array]:
	set(val):
		if datas != val:
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

func _ready() -> void:
	redraw()

func clear():
	for i in __property_old_parents:
		if i:
			disconnect_focused_propagate(i)
			if __property_old_parents[i].get_ref():
				i.reparent(__property_old_parents[i].get_ref())
			#if __property_old_parents[i] != null:
				#i.reparent(__property_old_parents[i])
			else:
				i.queue_free()
			
	__property_old_parents.clear()

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
			hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
							var label = Label.new()
							label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if left == 1 else HORIZONTAL_ALIGNMENT_RIGHT
							label.text = str(data)
							label.auto_translate = false
							label.localize_numeral_system = false
							label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
							hb.add_child(label)
					elif data is DictionaryObject:
						mgr.inspect_object(data)
						var properties = data._get_property_list().map(func(v): return v["name"])
						var editor_properties = mgr.editor_interface.get_inspector().find_children("@EditorProperty*", "", true, false)
						for i in properties.size():
							# 下划线开头的隐藏label。隐藏方法是把控件整个添加到一个能按比例隐藏子控件的控件中
							var editor_property = editor_properties[i]
							# 只有让检查器显示这个属性，才能修改这个属性。否则修改的是检查器当前显示的属性。
							connect_focused_propagate(editor_property, data)
							__property_old_parents[editor_property] = weakref(editor_property.get_parent())
							editor_property.size_flags_horizontal = Control.SIZE_EXPAND_FILL
							editor_property.add_theme_stylebox_override("bg_selected", StyleBoxEmpty.new())
							if (properties[i] as String).begins_with("_"):
								var container = preload("res://addons/gdsql/tabs/sql_graph_node/cut_control.tscn").instantiate()
								container.invisible_ratio = 0.5
								container.control = editor_property
								hb.add_child(container)
							else:
								editor_property.reparent(hb)
								
					elif data is Control:
						hb.add_child(data)
			add_child(hb)
		move_child(check_button_enable, get_child_count() - 1)
		
## 强制刷新某个栏位的控件
func redraw_slot_control(slot_row_index, slot_col_index):
	var data = datas[slot_row_index][slot_col_index]
	if data is DictionaryObject:
		var hb = get_child(slot_row_index)
		# 释放旧的
		for child in hb.get_children():
			var old_editor_property
			if child is EditorProperty:
				old_editor_property = child
			else:
				old_editor_property = child.control # child is a cut_control
				child.control = null
				
			disconnect_focused_propagate(old_editor_property)
			if __property_old_parents[old_editor_property].get_ref():
				if old_editor_property.get_parent():
					old_editor_property.reparent(__property_old_parents[old_editor_property].get_ref())
				else:
					__property_old_parents[old_editor_property].get_ref().add_child(old_editor_property)
				__property_old_parents.erase(old_editor_property)
			else:
				__property_old_parents.erase(old_editor_property)
				old_editor_property.queue_free()
				
		while hb.get_child_count() > 0:
			hb.remove_child(hb.get_child(0))
				
		# 添加新的
		mgr.inspect_object(data)
		var properties = data._get_property_list().map(func(v): return v["name"])
		var editor_properties = mgr.editor_interface.get_inspector().find_children("@EditorProperty*", "", true, false)
		for i in properties.size():
			# 下划线开头的隐藏label。隐藏方法是把控件整个添加到一个能按比例隐藏子控件的控件中
			var editor_property = editor_properties[i]
			# 只有让检查器显示这个属性，才能修改这个属性。否则修改的是检查器当前显示的属性。
			connect_focused_propagate(editor_property, data)
			__property_old_parents[editor_property] = weakref(editor_property.get_parent())
			editor_property.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			editor_property.add_theme_stylebox_override("bg_selected", StyleBoxEmpty.new())
			if (properties[i] as String).begins_with("_"):
				var container = preload("res://addons/gdsql/tabs/sql_graph_node/cut_control.tscn").instantiate()
				container.invisible_ratio = 0.5
				container.control = editor_property
				hb.add_child(container)
			else:
				editor_property.reparent(hb)
				
## 返回第一个匹配该属性名称的值
func get_prop_value(prop):
	for row_datas in datas:
		for data in row_datas:
			if data is DictionaryObject:
				if data._get(prop) != null:
					return data._get(prop)
	return null
	
func hide_property_control(index):
	var p = get_child(index)
	if p is HBoxContainer and p.get_child(0) is EditorProperty:
		p.get_child(0).get_child(0).hide()
		
func show_property_control(index):
	var p = get_child(index)
	if p is HBoxContainer and p.get_child(0) is EditorProperty:
		p.get_child(0).get_child(0).show()
	
func _on_check_button_enable_toggled(button_pressed: bool) -> void:
	enabled = button_pressed
	
func connect_focused_propagate(control: Control, data):
	for child in control.get_children(true):
		if child is Control:
			connect_focused_propagate(child, data)
			if child.mouse_filter != Control.MOUSE_FILTER_IGNORE and child.has_signal("focus_entered"):
				if not (child as Control).is_connected("focus_entered", editor_property_focused):
					child.focus_entered.connect(editor_property_focused.bind(data))
			
func disconnect_focused_propagate(control: Control):
	for child in control.get_children(true):
		if child is Control:
			disconnect_focused_propagate(child)
			if (child as Control).is_connected("focus_entered", editor_property_focused):
				child.focus_entered.disconnect(editor_property_focused)
	
func editor_property_focused(data):
	mgr.inspect_object(data)
	
func _exit_tree() -> void:
	clear()
