@tool
extends MarginContainer

signal cornor_drag_start
signal cornor_drag_end

var start_drag = false
var diff = Vector2.ZERO

@onready var margin_container = $Panel/MarginContainer
@onready var drag_area = $Panel/MarginContainer/DragArea

func _on_drag_area_gui_input(event):
	if event is InputEventMouseButton:
		if start_drag:
			if not DisplayServer.mouse_get_button_state() & MOUSE_BUTTON_MASK_LEFT:
				start_drag = false
				on_stop_drag()
				return
		else:
			if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				start_drag = true
				cornor_drag_start.emit()
				
	elif event is InputEventMouseMotion and start_drag:
		drag_area.global_position = get_global_mouse_position() + diff
				
func on_stop_drag():
	margin_container.remove_child(drag_area)
	margin_container.add_child(drag_area)
	cornor_drag_end.emit()
