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
		# 表示node是被输入的节点
		if node.name == info["to_node"]:
			var from_node = graph_edit.get_node(str(info["from_node"]))
			graph_edit.disconnect_node(info["from_node"], info["from_port"], info["to_node"], info["to_port"])
			if not from_node.show_close:
				from_node.queue_free()
		# 表示node是输入节点
		elif node.name == info["from_node"]:
			graph_edit.disconnect_node(info["from_node"], info["from_port"], info["to_node"], info["to_port"])
			
	node.queue_free()
	
## 如果node是排外的输入节点，激活该节点的时候，把同一个输入端口的其他节点关闭
func node_enabled(node: GraphNode):
	var arr = {}
	for info in graph_edit.get_connection_list():
		if node.name == info["from_node"]:
			if not arr.has(info["to_node"]):
				arr[info["to_node"]] = {}
			arr[info["to_node"]][info["to_port"]] = true
			
	for to_node in arr:
		for to_port in arr[to_node]:
			for info in graph_edit.get_connection_list():
				if info["to_node"] == to_node and info["to_port"] == to_port and info["from_node"] != node.name:
					var from_node = graph_edit.get_node(str(info["from_node"]))
					from_node.enabled = false


func _on_button_add_node_select_pressed() -> void:
	graph_edit.grab_focus() # 激活绘图板的快捷键，比如delte， ctrl+C/V
	unselect_all_node()
	var node: GraphNode = preload("res://addons/gdsql/tabs/sql_graph_node/graph_node_select.tscn").instantiate()
	node.set_meta("type", "select")
	node.set_meta("node", true)
	node.close_request.connect(node_close.bind(node)) # 关闭事件
	node.query.connect(on_select_node_query.bind(node))
	graph_edit.add_child(node)
	node.selected = true
	node.position_offset = (graph_edit.get_rect().get_center() - node.get_rect().size + graph_edit.scroll_offset) / graph_edit.zoom
	var base_pos = node.position_offset
	var position_offsets = [
		Vector2	(0, 0),#	union all
		Vector2	(0, 0),#	left join
		Vector2	(-603, -305.5),#	GraphNodeOptionButton
		#Vector2	(-383, -275.5),#	GraphNodeLineEditSecret
		Vector2	(-603, -135.5),#	@GraphNode@174675
		Vector2	(-603, 4.5),#	GraphNodeTextEdit
		Vector2	(-603, 184.5),#	@GraphNode@174686
		Vector2	(-603, 364.5),#	@GraphNode@174687
		Vector2	(-603, 554.5),#	GraphNodeSpinBox
		Vector2	(-383, 554.5),#	@GraphNode@174699
	]
	for i in 9:
		set_input_of_select(i, base_pos + position_offsets[i], node, true)
		
# Select 执行
func on_select_node_query(node: GraphNode):
	var schema
	for info in graph_edit.get_connection_list():
		if node.name == info["to_node"]:
			var from_node = graph_edit.get_node(str(info["from_node"]))
			# TODO
	
func unselect_all_node():
	for i in graph_edit.get_children():
		if i.has_meta("node"):
			i.selected = false

func set_input_of_select(to_port: int, release_position: Vector2, select_node: GraphNode, show_close: bool = false):
	var pre_node: GraphNode
	var from_port = 0
	var xenophobic: bool # 是否排外
	match to_port:
		0:# Union All
			xenophobic = false
		1:# Left Join
			xenophobic = false
		2:# Schema
			xenophobic = true
			pre_node = preload("res://addons/gdsql/tabs/sql_graph_node/graph_node_schema.tscn").instantiate()
			pre_node.title = "Schema"
			pre_node.set_slot_type_left(0, 1000+to_port) # schema节点的密码插槽类型设置为schema节点的输出插槽的index+1000
		3:# Table
			xenophobic = true
			pre_node = preload("res://addons/gdsql/tabs/sql_graph_node/graph_node_table.tscn").instantiate()
			pre_node.title = "Table"
		4:# Fields
			xenophobic = true
			pre_node = preload("res://addons/gdsql/tabs/sql_graph_node/graph_node_text_edit.tscn").instantiate()
			pre_node.title = "Fields"
		5:# Where
			xenophobic = false
			pre_node = preload("res://addons/gdsql/tabs/sql_graph_node/graph_node_text_edit.tscn").instantiate()
			pre_node.title = "Where"
		6:# Order By
			xenophobic = false
			pre_node = preload("res://addons/gdsql/tabs/sql_graph_node/graph_node_order_by.tscn").instantiate()
			pre_node.title = "Order By"
		7:# Offset
			xenophobic = true
			pre_node = preload("res://addons/gdsql/tabs/sql_graph_node/graph_node_spin_box.tscn").instantiate()
			pre_node.title = "Offset"
		8:# Limit
			xenophobic = true
			pre_node = preload("res://addons/gdsql/tabs/sql_graph_node/graph_node_spin_box.tscn").instantiate()
			pre_node.title = "Limit"
		_:
			push_error("not support this, larger than 10")
			
	if pre_node:
		pre_node.set_slot_type_right(from_port, select_node.get_slot_type_left(to_port)) # select节点的每个输入节点的输出插槽类型设置为select插槽的index值
		handle_input_node(pre_node, select_node.name, from_port, to_port, release_position, show_close, xenophobic)
		
func handle_input_node(input_node: GraphNode, connected_node_name, from_port, to_port, release_position, show_close, xenophobic):
	graph_edit.add_child(input_node)
	input_node.set_meta("type", input_node.title)
	input_node.set_meta("node", true)
	input_node.selected = true
	input_node.position_offset = release_position # (release_position + graph_edit.scroll_offset) / graph_edit.zoom
	input_node.show_close = show_close
	input_node.close_request.connect(node_close.bind(input_node)) # 关闭事件
	if xenophobic:
		input_node.node_enabled.connect(node_enabled.bind(input_node)) # 互斥激活事件
	graph_edit.connect_node(input_node.name, from_port, connected_node_name, to_port)
	input_node.enabled = true # 触发同一端口的其余输入端口失效
		
func set_input_of_schema(to_port: int, release_position: Vector2, schema_node: GraphNode, show_close: bool = false):
	var pre_node: GraphNode
	var from_port = 0
	var xenophobic: bool # 是否排外
	match to_port:
		0:# Password
			xenophobic = true
			pre_node = preload("res://addons/gdsql/tabs/sql_graph_node/graph_node_line_edit_secret.tscn").instantiate()
			pre_node.title = "Password"
		_:
			push_error("not support this, larger than 10")
			
	if pre_node:
		pre_node.set_slot_type_right(from_port, schema_node.get_slot_type_left(to_port))
		handle_input_node(pre_node, schema_node.name, from_port, to_port, release_position, show_close, xenophobic)

func _on_graph_edit_connection_from_empty(to_node: StringName, to_port: int, release_position: Vector2) -> void:
	# 该信号给出的release_position和实际的position_offset不是一个概念，需要做转化
	# WARNING 暂不清楚引擎开发团队是否会修改这个东西，需要注意
	release_position = (release_position + graph_edit.scroll_offset) / graph_edit.zoom
	var node = graph_edit.get_node(str(to_node))
	assert(node.has_meta("type"), "node dose not have meta: type")
	match node.get_meta("type"):
		"select":
			set_input_of_select(to_port, release_position, node, true)
		"Schema":
			set_input_of_schema(to_port, release_position, node, true)

## delete快捷键删除node
func _on_graph_edit_delete_nodes_request(nodes: Array) -> void:
	var titles = nodes.map(func(v): return graph_edit.get_node(str(v)).title)
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = "Are you sure to delete selected nodes `%s`?" \
		% ", ".join(titles)
	dialog.confirmed.connect(func():
		for i in nodes:
			node_close(graph_edit.get_node(str(i)))
	)
	add_child(dialog)
	dialog.popup_centered()
	dialog.close_requested.connect(func():
		dialog.queue_free()
	)


func _on_graph_edit_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	graph_edit.connect_node(from_node, from_port, to_node, to_port)
	var f_node = graph_edit.get_node(str(from_node))
	f_node.enabled = true
