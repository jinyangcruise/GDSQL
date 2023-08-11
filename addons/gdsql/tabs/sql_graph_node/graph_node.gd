@tool
extends GraphNode

const __Singletons := preload("res://addons/gdsql/autoload/singletons.gd")
const __Manager := preload("res://addons/gdsql/singletons/gdsql_workbench_manager.gd")

signal node_enabled

@onready var check_button_enable: CheckButton = $CheckButtonEnable

## datas的元素是一个长度为2的数组，第一个元素是左侧输入port代表的数据，第二个元素是右侧输出port代表的数据。
## 元素是DictionaryObject时才会出现port，其他类型都不出现port，如果类型是字符串/数字，则会显示该字符串/数字，否则为空。
## 元素是DictionaryObject时，其所有属性将放到同一行进行显示。
## 元素是DictionaryObject时，若属性名称为下划线开头的，将隐藏属性名称，只保留属性值的设置界面。
## 左侧元素和右侧元素可以相同。
## 元素是Control时，添加到对应的行上。
## TODO 拖动port怎么引出节点？
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
				
var __property_old_parents = {}

func _ready() -> void:
	redraw()

func clear():
	for i in __property_old_parents:
		if __property_old_parents[i].get_ref():
			i.reparent(__property_old_parents[i].get_ref())
		else:
			i.queue_free()
			
	__property_old_parents.clear()

func redraw():
	clear()
	
	if datas and !datas.is_empty() and is_inside_tree():
		var mgr: __Manager = __Singletons.instance_of(__Manager, self)
		var graph_node = GraphNode.new()
		graph_node.show_close = true
		graph_node.resizable = true
		var test
		var index = -1
		for arr in datas:
			index += 1
			var hb = HBoxContainer.new()
			var left = 0
			for data in arr:
				left += 1
				if data != null:
					set_slot_enabled_left(index, true) if left == 1 else set_slot_enabled_right(index, true)
					if data is String or data is int or data is float:
						var label = Label.new()
						label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if left == 1 else HORIZONTAL_ALIGNMENT_RIGHT
						label.text = str(data)
						label.auto_translate = false
						label.localize_numeral_system = false
						label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
						hb.add_child(label)
					elif data is DictionaryObject:
						mgr.editor_interface.inspect_object(data, "", false)
						#var properties = data.get_property_list().filter(func(v): return v["usage"] & PROPERTY_USAGE_EDITOR).map(func(v): return v["name"])
						var properties = data._get_property_list().map(func(v): return v["name"])
						var editor_properties = mgr.editor_interface.get_inspector().find_children("@EditorProperty*", "", true, false)
						for i in properties.size():
							if (properties[i] as String).begins_with("_"):
								var container = MarginContainer.new()
								container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
								hb.add_child(container)
								for child in editor_properties[i].get_children():
									__property_old_parents[child] = weakref(editor_properties[i])
									child.reparent(container)
									child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
							else:
								var editor_property = editor_properties[i]
								__property_old_parents[editor_property] = weakref(editor_property.get_parent())
								editor_property.reparent(hb)
								editor_property.size_flags_horizontal = Control.SIZE_EXPAND_FILL
								editor_property.add_theme_stylebox_override("bg_selected", StyleBoxEmpty.new())
								
					elif data is Control:
						hb.add_child(data)
			add_child(hb)
		move_child(check_button_enable, get_child_count() - 1)

func _on_check_button_enable_toggled(button_pressed: bool) -> void:
	enabled = button_pressed
	
func _exit_tree() -> void:
	clear()
