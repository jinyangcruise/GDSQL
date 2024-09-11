@tool
extends MarginContainer

signal cornor_drag_start
signal cornor_drag_end
signal cornor_drag_moving(diff: Vector2)
signal cornor_double_clicked

var start_drag = false
#var start_drag_position = Vector2.ZERO
var init_diff = Vector2.ZERO

@onready var margin_container = $Panel/MarginContainer
@onready var drag_area = $Panel/MarginContainer/DragArea
@onready var center = $Panel/Center


func _on_drag_area_gui_input(event):
	if event is InputEventMouseButton:
		if start_drag:
			if not DisplayServer.mouse_get_button_state() & MOUSE_BUTTON_MASK_LEFT:
				start_drag = false
				on_stop_drag()
				return
		else:
			if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				if event.double_click:
					cornor_double_clicked.emit()
				else:
					start_drag = true
					init_diff = get_global_mouse_position() - center.global_position
					#start_drag_position = get_global_mouse_position()
					cornor_drag_start.emit()
					
	elif event is InputEventMouseMotion and start_drag:
		var diff = get_global_mouse_position() - center.global_position - init_diff
		#drag_area.global_position = get_global_mouse_position() + diff
		cornor_drag_moving.emit(diff)
		
func on_stop_drag():
	#margin_container.remove_child(drag_area)
	#margin_container.add_child(drag_area)
	cornor_drag_end.emit()
