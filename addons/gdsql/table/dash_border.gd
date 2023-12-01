@tool
extends Control

@export var show_left: bool = false:
	set(val):
		show_left = val
		var a_material = panel_dash_border.material as ShaderMaterial
		a_material.set_shader_parameter("show_left", show_left)
	
@export var show_right: bool = false:
	set(val):
		show_right = val
		var a_material = panel_dash_border.material as ShaderMaterial
		a_material.set_shader_parameter("show_right", show_right)
		
@export var show_top: bool = false:
	set(val):
		show_top = val
		var a_material = panel_dash_border.material as ShaderMaterial
		a_material.set_shader_parameter("show_top", show_top)
		
@export var show_bottom: bool = false:
	set(val):
		show_bottom = val
		var a_material = panel_dash_border.material as ShaderMaterial
		a_material.set_shader_parameter("show_bottom", show_bottom)

@onready var panel_dash_border = $PanelDashBorder

const line_width = 2.0

func _on_panel_dash_border_resized():
	if panel_dash_border:
		var a_material = panel_dash_border.material as ShaderMaterial
		a_material.set_shader_parameter("size", panel_dash_border.size)
		
		var count_x = int(floor(panel_dash_border.size.x / line_width))
		if count_x % 2 == 1:
			count_x += 1
		a_material.set_shader_parameter("dash_length_x", panel_dash_border.size.x / float(count_x))
		
		var count_y = int(floor(panel_dash_border.size.y / line_width))
		if count_y % 2 == 1:
			count_y += 1
		a_material.set_shader_parameter("dash_length_y", panel_dash_border.size.y / float(count_y))
