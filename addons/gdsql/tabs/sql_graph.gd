@tool
extends VSplitContainer

const __Singletons := preload("res://addons/gdsql/autoload/singletons.gd")
const __Manager := preload("res://addons/gdsql/singletons/gdsql_workbench_manager.gd")

signal request_open_file(path: String)
signal change_tab_title(page: Control, title: String)

@onready var _graph_edit: GraphEdit = $VBoxContainer/GraphEdit
@onready var button_commit: Button = $VBoxContainer/HFlowContainer/ButtonCommit
@onready var button_rollback: Button = $VBoxContainer/HFlowContainer/ButtonRollback
@onready var button_auto_commit: Button = $VBoxContainer/HFlowContainer/ButtonAutoCommit

var SQLGraphNode= preload("res://addons/gdsql/tabs/sql_graph_node/graph_node.tscn")

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
	
	var graph_node = gen_select_node()
	graph_edit.add_child(graph_node)
	graph_node.position_offset = (graph_edit.get_rect().get_center() - graph_node.get_rect().size/2 + graph_edit.scroll_offset) / graph_edit.zoom
	
func gen_select_node() -> GraphNode:
	var mgr: __Manager = __Singletons.instance_of(__Manager, self)
	var databases = mgr.databases.map(func(v): return v["name"])
	
	var schema_dict_obj = DictionaryObject.new({"Schema": "", "_password": ""}, {"Schema": {"hint": PROPERTY_HINT_ENUM, "hint_string": ",".join(databases)}, "_password": {"hint": PROPERTY_HINT_PASSWORD, "hint_string": "password"}})
	var table_dict_obj = DictionaryObject.new({"Table": "", "_alias": ""}, {"Table": {"hint": PROPERTY_HINT_ENUM, "hint_string": ""}, "_alias": {"hint": PROPERTY_HINT_PLACEHOLDER_TEXT, "hint_string": "alias"}})
	
	var graph_node = SQLGraphNode.instantiate()
	
	# 根据选择的数据库来更新表名备选项
	schema_dict_obj.value_changed.connect(func(prop, new_val, _old_val):
		if prop == "Schema":
			var tables = []
			for i in mgr.databases:
				if i["name"] == new_val:
					tables = i["table_items"].map(func(v): return v["table_name"])
					break
			table_dict_obj.reset_hint({"Table": {"hint": PROPERTY_HINT_ENUM, "hint_string": ",".join(tables)}, "_alias": {"hint": PROPERTY_HINT_PLACEHOLDER_TEXT, "hint_string": "alias"}})
			graph_node.redraw_slot_control(3, 2) # table是第4行第3个控件。
	)
	
	var btn_query = Button.new()
	btn_query.text = "query"
	btn_query.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_query.pressed.connect(on_select_node_query.bind(graph_node))
	
	var separator = Control.new()
	separator.custom_minimum_size.y = 5
	
	var datas: Array[Array] = [
		["Union All", "Result"],
		["Left Join", null],
		[null, null, schema_dict_obj, null],
		[null, null, table_dict_obj, null],
		[null, null, DictionaryObject.new({"Fields": ""}, {"Fields": {"hint": PROPERTY_HINT_MULTILINE_TEXT}}), null],
		[null, null, DictionaryObject.new({"Where": ""}, {"Where": {"hint": PROPERTY_HINT_MULTILINE_TEXT}}), null],
		[null, null, DictionaryObject.new({"Order By": "", "_order": "ASC"}, {"_order": {"hint": PROPERTY_HINT_ENUM, "hint_string": "ASC,DESC"}}), null],
		[null, null, DictionaryObject.new({"Offset": 0}), null],
		[null, null, DictionaryObject.new({"Limit": 100}), null],
		[null, null, separator],
		[null, null, btn_query]
	]
	graph_node.datas = datas
	graph_node.title = "Select"
	graph_node.ready.connect(func():
		graph_node.set_slot_type_left(0, 0) # Union All's type is 0
		graph_node.set_slot_type_left(1, 1) # Left Join's type is 1
		graph_node.set_slot_type_right(0, 0) # Result's type is 0
		graph_node.size.x = 650
		graph_node.selected = true
	)
	graph_node.set_meta("type", "Select")
	graph_node.set_meta("node", true)
	graph_node.close_request.connect(node_close.bind(graph_node)) # 关闭事件
	
	return graph_node
	
func gen_left_join_node() -> GraphNode:
	var mgr: __Manager = __Singletons.instance_of(__Manager, self)
	var databases = mgr.databases.map(func(v): return v["name"])
	
	var schema_dict_obj = DictionaryObject.new({"Schema": "", "_password": ""}, {"Schema": {"hint": PROPERTY_HINT_ENUM, "hint_string": ",".join(databases)}, "_password": {"hint": PROPERTY_HINT_PASSWORD, "hint_string": "password"}})
	var table_dict_obj = DictionaryObject.new({"Table": "", "_alias": ""}, {"Table": {"hint": PROPERTY_HINT_ENUM, "hint_string": ""}, "_alias": {"hint": PROPERTY_HINT_PLACEHOLDER_TEXT, "hint_string": "alias"}})
	
	var graph_node = SQLGraphNode.instantiate()
	
	# 根据选择的数据库来更新表名备选项
	schema_dict_obj.value_changed.connect(func(prop, new_val, _old_val):
		if prop == "Schema":
			var tables = []
			for i in mgr.databases:
				if i["name"] == new_val:
					tables = i["table_items"].map(func(v): return v["table_name"])
					break
			table_dict_obj.reset_hint({"Table": {"hint": PROPERTY_HINT_ENUM, "hint_string": ",".join(tables)}, "_alias": {"hint": PROPERTY_HINT_PLACEHOLDER_TEXT, "hint_string": "alias"}})
			graph_node.redraw_slot_control(2, 2) # table是第3行第3个控件。
	)
	
	var btn_query = Button.new()
	btn_query.text = "query"
	btn_query.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_query.pressed.connect(on_select_node_query.bind(graph_node))
	
	var separator = Control.new()
	separator.custom_minimum_size.y = 5
	
	var datas: Array[Array] = [
		[null, "Result"],
		[null, null, schema_dict_obj, null],
		[null, null, table_dict_obj, null],
		[null, null, DictionaryObject.new({"On": ""}, {"On": {"hint": PROPERTY_HINT_MULTILINE_TEXT}}), null]
	]
	graph_node.datas = datas
	graph_node.title = "Left Join"
	graph_node.ready.connect(func():
		graph_node.set_slot_type_right(0, 1) # Result's type is 1
		graph_node.size.x = 650
		graph_node.selected = true
	)
	graph_node.set_meta("type", "Left Join")
	graph_node.set_meta("node", true)
	graph_node.close_request.connect(node_close.bind(graph_node)) # 关闭事件
	
	return graph_node
	
func set_input(to_port: int, release_position: Vector2, to_node: GraphNode, show_close: bool = false):
	var input_node: GraphNode
	var from_port = 0
	var xenophobic: bool # 是否排外
	var port_data = to_node.datas[to_port][0] # 0 is left port index; 1 is right port index
	match port_data:
		"Union All":
			xenophobic = true
			input_node = gen_select_node()
		"Left Join":
			xenophobic = false
			input_node = gen_left_join_node()
		#_:
			#if port_data is DictionaryObject:
				#var dict_obj = port_data as DictionaryObject
				#var props = dict_obj._get_property_list()
				#var graph_node = SQLGraphNode.instantiate()
				#if props.size() == 0:
					#return
#
				#input_node = graph_node
				#var datas: Array[Array] = [[null, port_data.duplicate(true)]]
				#graph_node.datas = datas
				#graph_node.title = props[0]["name"]
				#graph_node.size.x = 400
				#to_node.hide_property_control(to_port)
				#match graph_node.title:
					#"Schema", "Table", "Fields", "Offset", "Limit":
						#xenophobic = true
					#"Where", "Order By":
						#xenophobic = false
					#_:
						#push_warning("please specify xenophobic of this type of node:" + graph_node.title)
			#else:
				#push_warning("no input node match this port_data:" + var_to_str(port_data))
			
	if input_node:
		#input_node.set_slot_type_right(from_port, to_node.get_slot_type_left(to_port))
		handle_input_node(input_node, to_node.name, from_port, to_port, release_position, show_close, xenophobic)
	
# Select 执行
func on_select_node_query(node: GraphNode):
	printt("query...")
	var schema
	for info in graph_edit.get_connection_list():
		if node.name == info["to_node"]:
			var from_node = graph_edit.get_node(str(info["from_node"]))
			# TODO
	
func unselect_all_node():
	for i in graph_edit.get_children():
		if i.has_meta("node"):
			i.selected = false

		
func handle_input_node(input_node: GraphNode, connected_node_name, from_port, to_port, release_position, show_close, xenophobic):
	graph_edit.add_child(input_node)
	input_node.set_meta("type", input_node.title)
	input_node.set_meta("node", true)
	input_node.position_offset = release_position # (release_position + graph_edit.scroll_offset) / graph_edit.zoom
	input_node.show_close = show_close
	if not input_node.is_connected("close_request", node_close):
		input_node.close_request.connect(node_close.bind(input_node)) # 关闭事件
	if xenophobic:
		input_node.node_enabled.connect(node_enabled.bind(input_node)) # 互斥激活事件
	graph_edit.connect_node(input_node.name, from_port, connected_node_name, to_port)
	input_node.enabled = true # 触发同一端口的其余输入端口失效
	

func _on_graph_edit_connection_from_empty(to_node: StringName, to_port: int, release_position: Vector2) -> void:
	# 该信号给出的release_position和实际的position_offset不是一个概念，需要做转化
	# WARNING 暂不清楚引擎开发团队是否会修改这个东西，需要注意
	release_position = (release_position + graph_edit.scroll_offset) / graph_edit.zoom
	var node = graph_edit.get_node(str(to_node))
	assert(node.has_meta("type"), "node dose not have meta: type")
	match node.get_meta("type"):
		"Select":
			set_input(to_port, release_position, node, true)

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


func _on_graph_edit_connection_drag_started(_from_node: StringName, _from_port: int, _is_output: bool) -> void:
	unselect_all_node()


func _on_graph_edit_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	graph_edit.disconnect_node(from_node, from_port, to_node, to_port)
