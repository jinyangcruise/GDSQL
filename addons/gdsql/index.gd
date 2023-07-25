@tool
extends MarginContainer

@onready var tree_databases: Tree = $VBoxContainer/HSplitContainer/VBoxContainer/TreeDatabases
@onready var tab_container: TabContainer = $VBoxContainer/HSplitContainer/VSplitContainer/TabContainer

func _ready() -> void:
	tree_databases.new_schema.connect(tab_container.add_tab_new_schema)
	tab_container.add_new_schema.connect(tree_databases.add_db_to_config)
	tree_databases.add_db_to_config_success.connect(tab_container.close_content_window)

func _on_button_refresh_pressed() -> void:
	tree_databases.refresh()
