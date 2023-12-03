@tool
extends Control

@export_enum("Singular:0", "Even:1") var mode: int = 0:
	set(val):
		mode = val
		queue_redraw()

@export var width: float = 2.0:
	set(val):
		width = val
		queue_redraw()
		
@export var color: Color = Color.WHITE:
	set(val):
		color = val
		queue_redraw()

@export var margin_left: int = 0:
	set(val):
		margin_left = val
		queue_redraw()
		
@export var margin_right: int = 0:
	set(val):
		margin_right = val
		queue_redraw()
		
@export var margin_top: int = 0:
	set(val):
		margin_top = val
		queue_redraw()
		
@export var margin_bottom: int = 0:
	set(val):
		margin_bottom = val
		queue_redraw()

func _draw():
	var length = size.y + margin_top + margin_bottom
	var count = int(floor(length / width))
	if count % 2 == mode:
		count += 1
	var a_width = length / float(count)
	
	draw_dashed_line(Vector2.ZERO - Vector2(margin_left, margin_top) + Vector2(width/2, 0), 
		Vector2(0, size.y) - Vector2(margin_left, -margin_bottom) + Vector2(width/2, 0), color, a_width, a_width, false)

