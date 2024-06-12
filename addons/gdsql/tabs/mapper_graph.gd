@tool
extends VSplitContainer


var mgr: GDSQLWorkbenchManagerClass = Engine.get_singleton("GDSQLWorkbenchManager")


@onready var graph_edit: GraphEdit = $VBoxContainer/GraphEdit

func _ready() -> void:
	pass
	
func load_data(info: Dictionary):
	graph_edit.add_item(info, {})
