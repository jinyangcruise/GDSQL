@tool
extends Control

@onready var dash_border = $MarginContainerForDrag/DashBorder
@onready var drag_area = $MarginContainer/Panel/MarginContainer/DragArea
@onready var margin_container = $MarginContainer/Panel/MarginContainer
@onready var margin_container_for_drag = $MarginContainerForDrag
@onready var panel = $MarginContainer/Panel


var start_drag = false
var start_drag_position = Vector2.ZERO

func _ready():
	position = Vector2(300, 600)

func _on_dash_border_resized():
	var a_material = dash_border.material as ShaderMaterial
	a_material.set_shader_parameter("size", dash_border.size)
	
	var count_x = int(floor(dash_border.size.x / 3.0))
	if count_x % 2 == 0:
		count_x += 1
	a_material.set_shader_parameter("dash_length_x", dash_border.size.x / float(count_x))
	
	var count_y = int(floor(dash_border.size.y / 3.0))
	if count_y % 2 == 0:
		count_y += 1
	a_material.set_shader_parameter("dash_length_y", dash_border.size.y / float(count_y))



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
				set_dash_border(true, 0.0)
				start_drag_position = get_global_mouse_position()
				
	elif event is InputEventMouseMotion and start_drag:
		drag_area.global_position = get_global_mouse_position()
		var diff = get_global_mouse_position() - start_drag_position
		if abs(diff.x) > abs(diff.y):
			if diff.x > 0:
				for cons in ["margin_left", "margin_top", "margin_bottom"]:
					margin_container_for_drag.remove_theme_constant_override(cons)
				margin_container_for_drag.add_theme_constant_override("margin_right", -diff.x)
			else:
				for cons in ["margin_right", "margin_top", "margin_bottom"]:
					margin_container_for_drag.remove_theme_constant_override(cons)
				margin_container_for_drag.add_theme_constant_override("margin_left", diff.x)
		else:
			if diff.y > 0:
				for cons in ["margin_top", "margin_left", "margin_right"]:
					margin_container_for_drag.remove_theme_constant_override(cons)
				margin_container_for_drag.add_theme_constant_override("margin_bottom", -diff.y)
			else:
				for cons in ["margin_bottom", "margin_left", "margin_right"]:
					margin_container_for_drag.remove_theme_constant_override(cons)
				margin_container_for_drag.add_theme_constant_override("margin_top", diff.y)
		
func on_stop_drag():
	margin_container.remove_child(drag_area)
	margin_container.add_child(drag_area)
	for i in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin_container_for_drag.remove_theme_constant_override(i)
	var sb = get_theme_stylebox("panel") as StyleBoxFlat
	size = dash_border.size + Vector2(sb.border_width_left + sb.border_width_right, sb.border_width_top + sb.border_width_bottom)
	set_dash_border(false, 0.0)
	
func set_border(border_alpha: float, width: int, expand: int):
	var sb = get_theme_stylebox("panel") as StyleBoxFlat
	sb.border_color.a = border_alpha
	sb.set_border_width_all(width)
	sb.set_expand_margin_all(expand)
	
func set_draw_center(draw_center: bool):
	var sb = get_theme_stylebox("panel") as StyleBoxFlat
	sb.draw_center = draw_center
	
func set_dash_border(border_show: bool, moving_speed: float):
	dash_border.visible = border_show
	var a_material = dash_border.material as ShaderMaterial
	a_material.set_shader_parameter("moving_speed", moving_speed)
	
func set_drag_area(area_show: bool):
	panel.visible = area_show
