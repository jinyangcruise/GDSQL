@tool
extends MarginContainer

@onready var tree_databases: Tree = $VBoxContainer/HSplitContainer/VBoxContainer/TreeDatabases


func _on_button_refresh_pressed() -> void:
	tree_databases.refresh()
