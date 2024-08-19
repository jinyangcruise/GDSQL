@tool
## 本工具用于隐藏控件水平方向（左边）的一部分
extends Control

## 水平方向隐藏左半边的比例
@export var invisible_ratio: float = 0.5

var control: Control:
	set(val):
		control = val
		if is_inside_tree():
			if control == null:
				while container.get_child_count() > 0:
					container.remove_child(container.get_child(0))
			else:
				if not control.get_parent():
					container.add_child(control)
				elif control.get_parent() != container:
					control.reparent(container)
				control.position = Vector2.ZERO
				custom_minimum_size.y = control.size.y
				# 修复control从隐藏状态转为可见状态时，size发生变化引起的整体size变化的情况
				control.visibility_changed.connect(_on_control_visibibity_changed)
				#custom_minimum_size = control.size 会导致显示问题

@onready var container: Control = $Container

func _ready() -> void:
	if control:
		control = control
	_on_resized()

func _on_resized() -> void:
	if container:
		container.size = size
		if size_flags_horizontal & Control.SIZE_EXPAND:
			container.size.x = size.x / (1-invisible_ratio)
			container.position.x = -container.size.x * invisible_ratio
		#if size_flags_vertical & Control.SIZE_EXPAND:
			#container.size.y = size.y / (1-invisible_ratio)
			#container.position.y = -container.size.y * invisible_ratio
			#printt(2222222222, size_flags_horizontal)
			
		#printt("aqaaaaa", self, size, container.size, container.position, control.position)

func _on_control_visibibity_changed():
	if control:
		await get_tree().process_frame
		custom_minimum_size.y = control.size.y
