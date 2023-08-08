@tool
extends VSplitContainer

signal request_open_file(path: String)
signal change_tab_title(page: Control, title: String)

@onready var _graph_edit: GraphEdit = $VBoxContainer/GraphEdit
@onready var button_commit: Button = $VBoxContainer/HFlowContainer/ButtonCommit
@onready var button_rollback: Button = $VBoxContainer/HFlowContainer/ButtonRollback
@onready var button_auto_commit: Button = $VBoxContainer/HFlowContainer/ButtonAutoCommit


var graph_edit: GraphEdit:
	get:
		return _graph_edit
		
func _ready() -> void:
	button_commit.disabled = button_auto_commit.button_pressed
	button_rollback.disabled = button_auto_commit.button_pressed
	
func _on_button_auto_commit_toggled(button_pressed: bool) -> void:
	button_commit.disabled = button_pressed
	button_rollback.disabled = button_pressed
	
func _on_button_open_pressed() -> void:
	var editor_file_dialog = EditorFileDialog.new()
	editor_file_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	editor_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	editor_file_dialog.add_filter("*.gdsql", "GDSQL File")
	editor_file_dialog.file_selected.connect(func(path: String):
		request_open_file.emit(path)
	)
	add_child(editor_file_dialog)
	editor_file_dialog.popup_centered_ratio(0.7)
	editor_file_dialog.close_requested.connect(func():
		editor_file_dialog.queue_free()
	)
	
func _on_button_save_pressed() -> void:
	# 本身就是一个已经保存的文件，就直接保存
	if get_meta("is_file"):
		var file = FileAccess.open(get_meta("file_path"), FileAccess.WRITE)
		file.store_string(graph_edit.text) # TODO 怎么保存图？
		change_tab_title.emit(self, get_meta("file_name"))
		return
		
	var editor_file_dialog = EditorFileDialog.new()
	editor_file_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	editor_file_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	editor_file_dialog.add_filter("*.gdsql", "GDSQL File")
	editor_file_dialog.file_selected.connect(func(path: String):
		var file = FileAccess.open(path, FileAccess.WRITE)
		file.store_string(graph_edit.text)
		var sp = path.rsplit("/", true, 1)
		var file_name = sp[sp.size()-1]
		change_tab_title.emit(self, file_name)
		set_meta("is_file", true)
		set_meta("file_name", file_name)
		set_meta("file_path", path)
	)
	add_child(editor_file_dialog)
	editor_file_dialog.popup_centered_ratio(0.7)
	editor_file_dialog.close_requested.connect(func():
		editor_file_dialog.queue_free()
	)
	
## 关闭一个节点的时候，把没有关闭按钮的输入节点一起关闭
func node_close(node: GraphNode):
	for info in graph_edit.get_connection_list():
		if node.name == info["to_node"]:
			var from_node = graph_edit.get_node(str(info["from_node"]))
			if not from_node.show_close:
				graph_edit.disconnect_node(info["from_node"], info["from_port"], info["to_node"], info["to_port"])
				from_node.queue_free()
	node.queue_free()


func _on_button_add_node_select_pressed() -> void:
	unselect_all_node()
	var node: GraphNode = preload("res://addons/gdsql/tabs/sql_graph_node/graph_node_select.tscn").instantiate()
	node.set_meta("type", "select")
	node.set_meta("node", true)
	node.close_request.connect(node_close.bind(node)) # 关闭事件
	graph_edit.add_child(node)
	node.selected = true
	node.position_offset = (graph_edit.get_rect().get_center() - node.get_rect().size + graph_edit.scroll_offset) / graph_edit.zoom
	var base_pos = node.position_offset
	for i in 11:
		set_input_of_select(i, Vector2(base_pos.x - 800, base_pos.y + (i - 4) * 150), node)
		
func unselect_all_node():
	for i in graph_edit.get_children():
		if i.has_meta("node"):
			i.selected = false

func set_input_of_select(to_port: int, release_position: Vector2, select_node: GraphNode):
	var pre_node: GraphNode
	match to_port:
		0:# Union
			pass
		1:# Schema
			pre_node = preload("res://addons/gdsql/tabs/sql_graph_node/graph_node_option_button.tscn").instantiate()
			pre_node.title = "Schema"
		2:# Password
			pre_node = preload("res://addons/gdsql/tabs/sql_graph_node/graph_node_line_edit_secret.tscn").instantiate()
			pre_node.title = "Password"
		3:# Table
			pre_node = preload("res://addons/gdsql/tabs/sql_graph_node/graph_node_option_button.tscn").instantiate()
			pre_node.title = "Table"
		4:# Table Alias
			pre_node = preload("res://addons/gdsql/tabs/sql_graph_node/graph_node_line_edit.tscn").instantiate()
			pre_node.title = "Table Alias"
		5:# Fields
			pre_node = preload("res://addons/gdsql/tabs/sql_graph_node/graph_node_text_edit.tscn").instantiate()
			pre_node.title = "Fields"
		6:# Where
			pre_node = preload("res://addons/gdsql/tabs/sql_graph_node/graph_node_text_edit.tscn").instantiate()
			pre_node.title = "Where"
		7:# Order By
			pre_node = preload("res://addons/gdsql/tabs/sql_graph_node/graph_node_line_edit.tscn").instantiate()
			pre_node.title = "Order By"
		8:# Order
			pre_node = preload("res://addons/gdsql/tabs/sql_graph_node/graph_node_option_button.tscn").instantiate()
			pre_node.title = "Order"
		9:# Offset
			pre_node = preload("res://addons/gdsql/tabs/sql_graph_node/graph_node_spin_box.tscn").instantiate()
			pre_node.title = "Offset"
		10:# Limit
			pre_node = preload("res://addons/gdsql/tabs/sql_graph_node/graph_node_spin_box.tscn").instantiate()
			pre_node.title = "Limit"
		_:
			push_error("not support this, larger than 10")
			
	if pre_node:
		graph_edit.add_child(pre_node)
		pre_node.set_meta("node", true)
		pre_node.selected = true
		pre_node.position_offset = release_position
		pre_node.show_close = false
		graph_edit.connect_node(pre_node.name, 0, select_node.name, to_port)

func _on_graph_edit_connection_from_empty(to_node: StringName, to_port: int, release_position: Vector2) -> void:
	var node = graph_edit.get_node(str(to_node))
	assert(node.has_meta("type"), "node dose not have meta: type")
	match node.get_meta("type"):
		"select":
			set_input_of_select(to_port, release_position, node)
