@tool
extends Control

@onready var margin_container = $MarginContainer

@export_enum("Singular:0", "Even:1") var left_mode: int = 0:
	set(val):
		left_mode = val
		if left_border:
			left_border.mode = val

@export_enum("Singular:0", "Even:1") var right_mode: int = 0:
	set(val):
		right_mode = val
		if right_border:
			right_border.mode = val

@export_enum("Singular:0", "Even:1") var top_mode: int = 0:
	set(val):
		top_mode = val
		if top_border:
			top_border.mode = val

@export_enum("Singular:0", "Even:1") var bottom_mode: int = 0:
	set(val):
		bottom_mode = val
		if bottom_border:
			bottom_border.mode = val

@export var width: float = 2.0:
	set(val):
		width = val
		if left_border:
			left_border.width = val
		if right_border:
			right_border.width = val
		if top_border:
			top_border.width = val
		if bottom_border:
			bottom_border.width = val
		
@export var color: Color = Color.WHITE:
	set(val):
		color = val
		if left_border:
			left_border.color = val
		if right_border:
			right_border.color = val
		if top_border:
			top_border.color = val
		if bottom_border:
			bottom_border.color = val
		
@export var show_left: bool = false:
	set(val):
		show_left = val
		var border = left_border
		if val:
			if border == null:
				border = preload("res://addons/gdsql/table/left_dash_border.tscn").instantiate()
				left_border = border
				border.width = width
				border.color = color
				if margin_container: margin_container.add_child(border)
			else:
				border.show()
		else:
			if border:
				border.hide()
				printt("border hide", border)
	
@export var show_right: bool = false:
	set(val):
		show_right = val
		var border = right_border
		if val:
			if border == null:
				border = preload("res://addons/gdsql/table/right_dash_border.tscn").instantiate()
				right_border = border
				border.width = width
				border.color = color
				if margin_container: margin_container.add_child(border)
			else:
				border.show()
		else:
			if border:
				border.hide()
		
@export var show_top: bool = false:
	set(val):
		show_top = val
		var border = top_border
		if val:
			if border == null:
				border = preload("res://addons/gdsql/table/top_dash_border.tscn").instantiate()
				top_border = border
				border.width = width
				border.color = color
				if margin_container: margin_container.add_child(border)
			else:
				border.show()
		else:
			if border:
				border.hide()
		
@export var show_bottom: bool = false:
	set(val):
		show_bottom = val
		var border = bottom_border
		if val:
			if border == null:
				border = preload("res://addons/gdsql/table/bottom_dash_border.tscn").instantiate()
				bottom_border = border
				border.width = width
				border.color = color
				if margin_container: margin_container.add_child(border)
			else:
				border.show()
		else:
			if border:
				border.hide()
		
@export var expand_margin_left: int = 0:
	set(val):
		expand_margin_left = val
		margin_container.add_theme_constant_override("margin_left", val)
		
@export var expand_margin_right: int = 0:
	set(val):
		expand_margin_right = val
		margin_container.add_theme_constant_override("margin_right", val)
		
@export var expand_margin_top: int = 0:
	set(val):
		expand_margin_top = val
		margin_container.add_theme_constant_override("margin_top", val)
		
@export var expand_margin_bottom: int = 0:
	set(val):
		expand_margin_bottom = val
		margin_container.add_theme_constant_override("margin_bottom", val)

var left_border
var right_border
var top_border
var bottom_border

func _ready():
	if left_border and left_border.get_parent() == null:
		margin_container.add_child(left_border)
	if right_border and right_border.get_parent() == null:
		margin_container.add_child(right_border)
	if top_border and top_border.get_parent() == null:
		margin_container.add_child(top_border)
	if bottom_border and bottom_border.get_parent() == null:
		margin_container.add_child(bottom_border)
