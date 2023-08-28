@tool
extends VSplitContainer

var mgr: GDSQLWorkbenchManagerClass = Engine.get_singleton("GDSQLWorkbenchManager")

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
				# 清空一些数据代理
				if from_node.has_meta("base_dao"):
					(from_node.get_meta("base_dao") as BaseDao).reset(true)
					from_node.remove_meta("base_dao")
				if from_node.has_meta("left_join"):
					(from_node.get_meta("left_join") as LeftJoin).clear_chain()
					from_node.remove_meta("left_join")
				from_node.queue_free()
		# 表示node是输入节点
		elif node.name == info["from_node"]:
			graph_edit.disconnect_node(info["from_node"], info["from_port"], info["to_node"], info["to_port"])
			
	# 清空一些数据代理
	if node.has_meta("base_dao"):
		(node.get_meta("base_dao") as BaseDao).reset(true)
		node.remove_meta("base_dao")
	if node.has_meta("left_join"):
		(node.get_meta("left_join") as LeftJoin).clear_chain()
		node.remove_meta("left_join")
			
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
	
func _on_button_add_node_left_join_pressed():
	graph_edit.grab_focus() # 激活绘图板的快捷键，比如delte， ctrl+C/V
	unselect_all_node()
	
	var graph_node = gen_left_join_node()
	graph_edit.add_child(graph_node)
	graph_node.position_offset = (graph_edit.get_rect().get_center() - graph_node.get_rect().size/2 + graph_edit.scroll_offset) / graph_edit.zoom
	
	
func gen_select_node() -> GraphNode:
	var databases = mgr.databases.keys()
	
	var schema_dict_obj = DictionaryObject.new({"Schema": "", "_password": ""}, {"Schema": {"hint": PROPERTY_HINT_ENUM, "hint_string": ",".join(databases)}, "_password": {"hint": PROPERTY_HINT_PASSWORD, "hint_string": "password"}})
	var table_dict_obj = DictionaryObject.new({"Table": "", "_alias": ""}, {"Table": {"hint": PROPERTY_HINT_ENUM, "hint_string": ""}, "_alias": {"hint": PROPERTY_HINT_PLACEHOLDER_TEXT, "hint_string": "alias"}})
	var fields_dict_obj = DictionaryObject.new({"Fields": ""}, {"Fields": {"hint": PROPERTY_HINT_MULTILINE_TEXT}})
	var where_dict_obj = DictionaryObject.new({"Where": ""}, {"Where": {"hint": PROPERTY_HINT_MULTILINE_TEXT}})
	var order_dict_obj = DictionaryObject.new({"Order By": ""}, {"Order By": {"hint": PROPERTY_HINT_MULTILINE_TEXT}})
	var limit_dict_obj = DictionaryObject.new({"Offset": 0, "Limit": 100})
	
	# 关联该节点的BaseDao
	var base_dao = BaseDao.new()
	base_dao.select("", true)
	base_dao.limit(0, 100)
	
	var graph_node = SQLGraphNode.instantiate()
	graph_node.set_meta("base_dao", base_dao)
	
	# 根据选择的数据库来更新表名备选项
	schema_dict_obj.value_changed.connect(func(prop, new_val, _old_val):
		match prop:
			"Schema":
				base_dao.use_db(mgr.databases[new_val]["path"])
				var tables = mgr.databases[new_val]["table_items"].keys()
				table_dict_obj.reset_hint({"Table": {"hint": PROPERTY_HINT_ENUM, "hint_string": ",".join(tables)}, "_alias": {"hint": PROPERTY_HINT_PLACEHOLDER_TEXT, "hint_string": "alias"}})
				graph_node.redraw_slot_control(3, 2) # table是第4行第3个控件。
			"_password":
				base_dao.set_password(new_val)
	)
	table_dict_obj.value_changed.connect(func(prop, new_val, _old_val):
		match prop:
			"Table":
				var db_info = mgr.databases[schema_dict_obj._get("Schema")]
				var table = db_info["table_items"][new_val]["file_name"]
				base_dao.from(table, table_dict_obj._get("_alias"))
			"_alias":
				base_dao.from(table_dict_obj._get("Table"), new_val)
	)
	fields_dict_obj.value_changed.connect(func(prop, new_val, _old_val):
		match prop:
			"Fields":
				base_dao.select(new_val, true)
	)
	where_dict_obj.value_changed.connect(func(prop, new_val, _old_val):
		match prop:
			"Where":
				base_dao.where(new_val)
	)
	order_dict_obj.value_changed.connect(func(prop, new_val, _old_val):
		match prop:
			"Order By":
				base_dao.order_by_str(new_val)
	)
	limit_dict_obj.value_changed.connect(func(prop, new_val, _old_val):
		match prop:
			"Offset":
				base_dao.limit(new_val, limit_dict_obj._get("Limit"))
			"Limit":
				base_dao.limit(limit_dict_obj._get("Offset"), new_val)
	)
	
	var btn_query = Button.new()
	btn_query.text = "query"
	btn_query.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_query.pressed.connect(on_select_node_query.bind(graph_node))
	btn_query.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	
	var separator = Control.new()
	separator.custom_minimum_size.y = 5
	
	var datas: Array[Array] = [
		["Union All", "Result"],
		["Left Join", null],
		[null, null, schema_dict_obj],
		[null, null, table_dict_obj],
		[null, null, fields_dict_obj],
		[null, null, where_dict_obj],
		[null, null, order_dict_obj],
		[null, null, limit_dict_obj],
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
	graph_node.close_request.connect(func():
		make_useless_of_select_node(graph_node)
		node_close(graph_node)
	)
	graph_node.node_enable_status.connect(func(enabled):
		btn_query.disabled = !enabled
		if enabled:
			make_useful_of_select_node(graph_node)
		else:
			make_useless_of_select_node(graph_node)
	)
	
	return graph_node
		
func gen_left_join_node() -> GraphNode:
	var databases = mgr.databases.keys()
	
	var schema_dict_obj = DictionaryObject.new({"Schema": "", "_password": ""}, {"Schema": {"hint": PROPERTY_HINT_ENUM, "hint_string": ",".join(databases)}, "_password": {"hint": PROPERTY_HINT_PASSWORD, "hint_string": "password"}})
	var table_dict_obj = DictionaryObject.new({"Table": "", "_alias": ""}, {"Table": {"hint": PROPERTY_HINT_ENUM, "hint_string": ""}, "_alias": {"hint": PROPERTY_HINT_PLACEHOLDER_TEXT, "hint_string": "alias"}})
	var cond_dict_obj = DictionaryObject.new({"On": ""}, {"On": {"hint": PROPERTY_HINT_MULTILINE_TEXT}})
	
	# 与该节点关联的LeftJoin对象
	var left_join_obj = LeftJoin.new()
	
	var graph_node = SQLGraphNode.instantiate()
	graph_node.set_meta("left_join", left_join_obj)
	
	# 根据选择的数据库来更新表名备选项
	schema_dict_obj.value_changed.connect(func(prop, new_val, _old_val):
		match prop:
			"Schema":
				left_join_obj.set_db(new_val)
				var tables = mgr.databases[new_val]["table_items"].keys()
				table_dict_obj.reset_hint({"Table": {"hint": PROPERTY_HINT_ENUM, "hint_string": ",".join(tables)}, "_alias": {"hint": PROPERTY_HINT_PLACEHOLDER_TEXT, "hint_string": "alias"}})
				graph_node.redraw_slot_control(2, 2) # table是第3行第3个控件。
			"_password":
				left_join_obj.set_password(new_val)
	)
	table_dict_obj.value_changed.connect(func(prop, new_val, _old_val):
		match prop:
			"Table":
				left_join_obj.set_table(new_val)
			"_alias":
				left_join_obj.set_alias(new_val)
	)
	cond_dict_obj.value_changed.connect(func(prop, new_val, _old_val):
		match prop:
			"On":
				left_join_obj.set_condition(new_val)
	)
	
	var btn_query = Button.new()
	btn_query.text = "query"
	btn_query.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_query.pressed.connect(on_select_node_query.bind(graph_node))
	
	var separator = Control.new()
	separator.custom_minimum_size.y = 5
	
	var datas: Array[Array] = [
		["Next Left Join", "Result"],
		[null, null, schema_dict_obj],
		[null, null, table_dict_obj],
		[null, null, cond_dict_obj]
	]
	graph_node.datas = datas
	graph_node.title = "Left Join"
	graph_node.ready.connect(func():
		graph_node.set_slot_type_left(0, 1) # Next Left Join's type is 1
		graph_node.set_slot_type_right(0, 1) # Result's type is 1
		graph_node.size.x = 650
		graph_node.selected = true
	)
	graph_node.set_meta("type", "Left Join")
	graph_node.set_meta("node", true)
	graph_node.close_request.connect(func():
		make_useless_of_left_join_node(graph_node)
		node_close(graph_node)
	)
	graph_node.node_enable_status.connect(func(enabled):
		if enabled:
			make_useful_of_left_join_node(graph_node)
		else:
			make_useless_of_left_join_node(graph_node)
	)
	
	return graph_node
	
## 生成一个【表格】节点
func gen_table_node(columns: Array, table_datas: Array) -> GraphNode:
	var graph_node = SQLGraphNode.instantiate()
	
	var margin_container = MarginContainer.new()
	margin_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin_container.add_theme_constant_override("margin_top", 10)
	margin_container.add_theme_constant_override("margin_bottom", 10)
	var table = preload("res://addons/gdsql/table.tscn").instantiate()
	table.editable = true
	table.columns = columns
	table.datas = table_datas
	margin_container.add_child(table)
	
	var datas: Array[Array] = [
		[margin_container, null]
	]
	graph_node.datas = datas
	graph_node.title = "Result"
	graph_node.ready.connect(func():
		graph_node.set_slot_type_left(0, 1) # Result's type is 1
		graph_node.size = Vector2(350, 400)
		graph_node.selected = true
	)
	graph_node.set_meta("type", "Result")
	graph_node.set_meta("node", true)
	graph_node.close_request.connect(node_close.bind(graph_node)) # 关闭事件
	
	return graph_node
	
func make_useful_of_select_node(graph_node: GraphNode):
	var to_nodes = get_to_nodes(graph_node, "Select")
	for node in to_nodes:
		(node.get_meta("base_dao") as BaseDao).set_union_all(graph_node.get_meta("base_dao") as BaseDao)
		
func make_useless_of_select_node(graph_node: GraphNode):
	var to_nodes = get_to_nodes(graph_node, "Select")
	for node in to_nodes:
		(node.get_meta("base_dao") as BaseDao).remove_union_all(graph_node.get_meta("base_dao") as BaseDao)
		
func make_useful_of_left_join_node(graph_node: GraphNode):
	var to_select_nodes = get_to_nodes(graph_node, "Select")
	for node in to_select_nodes:
		(node.get_meta("base_dao") as BaseDao).set_left_join(graph_node.get_meta("left_join") as LeftJoin)
	var to_left_join_nodes = get_to_nodes(graph_node, "Left Join")
	for node in to_left_join_nodes:
		(node.get_meta("left_join") as LeftJoin).set_left_join(graph_node.get_meta("left_join") as LeftJoin)
		
func make_useless_of_left_join_node(graph_node: GraphNode):
	var to_nodes = get_to_nodes(graph_node, "Select")
	for node in to_nodes:
		(node.get_meta("base_dao") as BaseDao).remove_left_join(graph_node.get_meta("left_join") as LeftJoin)
	var to_left_join_nodes = get_to_nodes(graph_node, "Left Join")
	for node in to_left_join_nodes:
		(node.get_meta("left_join") as LeftJoin).remove_left_join(graph_node.get_meta("left_join") as LeftJoin)
		
func set_input(to_port: int, release_position: Vector2, to_node: GraphNode, show_close: bool = false):
	var input_node: GraphNode
	var from_port = 0
	var xenophobic: bool # 是否排外
	var port_data = to_node.datas[to_port][0] # 0 is left port index; 1 is right port index
	match port_data:
		"Union All":
			xenophobic = true
			input_node = gen_select_node()
		"Left Join", "Next Left Join":
			xenophobic = true
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
	
## 获取接收输入数据的节点
func get_to_nodes(node: GraphNode, type: String = "") -> Array[GraphNode]:
	var ret: Array[GraphNode] = []
	for info in graph_edit.get_connection_list():
		if info["from_node"] == node.name:
			var to_node = graph_edit.get_node(str(info["to_node"])) as GraphNode
			if type == "" or type == to_node.get_meta("type"):
				ret.push_back(to_node)
	return ret
	
# Select 执行
# node: 被点击的select节点
func on_select_node_query(node: GraphNode):
	unselect_all_node()
	var from_to_map = {}
	var to_from_map = {}
	# 先做个映射
	for info in graph_edit.get_connection_list():
		var from_name = info["from_node"]
		var to_name = info["to_node"]
		var arr_tos_of_from = from_to_map.get(from_name, []) as Array
		var arr_froms_of_to = to_from_map.get(to_name, []) as Array
		arr_tos_of_from.push_back(to_name)
		arr_froms_of_to.push_back(from_name)
		from_to_map[from_name] = arr_tos_of_from
		to_from_map[to_name] = arr_froms_of_to
		
	# 找到源头（可能有多个源头，因为一个节点可能输入到多个节点上）
	var arr_source_node: Array = []
	_get_final_source(node.name, from_to_map, arr_source_node, "Select")
	
	# 每个源头都要query
	for node_name in arr_source_node:
		var source_node = graph_edit.get_node(str(node_name)) as GraphNode # 一个select node
		#var db_info = mgr.databases[source_node.get_prop_value("Schema")]
		#var dao: BaseDao = BaseDao.new()
		#dao.use_db(db_info["path"])
		#dao.set_password(source_node.get_prop_value("_password"))
		#dao.select(source_node.get_prop_value("Fields"), true)
		#dao.from(db_info["table_items"][source_node.get_prop_value("Table")]["file_name"], source_node.get_prop_value("_alias"))
		#dao.where(source_node.get_prop_value("Where"))
		#dao.order_by(source_node.get_prop_value("Order By"), source_node.get_prop_value("_order"))
		#dao.limit(source_node.get_prop_value("Offset"), source_node.get_prop_value("Limit"))
		var dao = source_node.get_meta("base_dao") as BaseDao
		var ret: Array = dao.query()
		
		var update_result = false
		if from_to_map.has(source_node.name):
			for to in from_to_map[source_node.name]:
				var to_node = graph_edit.get_node(str(to))
				if to_node.get_meta("type") == "Result":
					if to_node.enabled:
						var table = to_node.datas[0][0].get_child(0)
						table.columns = ret[0].map(func(v): return v["field_as"])
						table.datas = ret.slice(1) # TODO 可编辑，转成DictionaryObject
						update_result = true
					else:
						_on_graph_edit_disconnection_request(source_node.name, 0, to_node.name, 0)
					
		if not update_result:
			var table_node = gen_table_node(ret[0].map(func(v): return v["field_as"]), ret.slice(1))
			graph_edit.add_child(table_node)
			table_node.position_offset = source_node.position_offset + Vector2(source_node.size.x + 20, 0)
			_on_graph_edit_connection_request(source_node.name, 0, table_node.name, 0)
	
	
func _get_final_source(from, map: Dictionary, result: Array, node_type: String):
	var node = graph_edit.get_node(str(from))
	if node.get_meta("type") != node_type:
		return 0
		
	if not node.enabled:
		return -1
		
	if map.has(from):
		for to in map[from]:
			var ret = _get_final_source(to, map, result, node_type)
			if ret == 0:
				result.push_back(from)
				return 1
	else:
		result.push_back(from)
		return 1
	
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
	var t_node = graph_edit.get_node(str(to_node))
	## select 连 select（即union all）需要做成排他性的
	match f_node.get_meta("type"):
		"Select":
			match t_node.get_meta("type"):
				"Select":
					f_node.node_enabled.connect(node_enabled.bind(f_node)) # 互斥激活事件
		"Left Join":
			match t_node.get_meta("type"):
				"Select", "Left Join":
					f_node.node_enabled.connect(node_enabled.bind(f_node)) # 互斥激活事件
	f_node.enabled = true # 可以激活互斥并且促使数据关联


func _on_graph_edit_connection_drag_started(_from_node: StringName, _from_port: int, _is_output: bool) -> void:
	unselect_all_node()
	
func _on_graph_edit_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	graph_edit.disconnect_node(from_node, from_port, to_node, to_port)
	# 删除BaseDao和LeftJoin数据关联
	var f_node = graph_edit.get_node(str(from_node))
	var t_node = graph_edit.get_node(str(to_node))
	## select 连 select（即union all）
	match f_node.get_meta("type"):
		"Select":
			match t_node.get_meta("type"):
				"Select":
					(t_node.get_meta("base_dao") as BaseDao).remove_union_all(f_node.get_meta("base_dao") as BaseDao)
		"Left Join":
			match t_node.get_meta("type"):
				"Select":
					(t_node.get_meta("base_dao") as BaseDao).remove_left_join(f_node.get_meta("left_join") as LeftJoin)
				"Left Join":
					(t_node.get_meta("left_join") as LeftJoin).remove_left_join((f_node.get_meta("left_join") as LeftJoin))
					
func _exit_tree():
	for node in graph_edit.get_children():
		if node is GraphNode:
			node_close(node)
