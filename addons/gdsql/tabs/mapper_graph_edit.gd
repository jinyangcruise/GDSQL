@tool
extends GraphEdit

signal change_tab_title(page: Control, title: String)
var mgr: GDSQLWorkbenchManagerClass = Engine.get_singleton("GDSQLWorkbenchManager")

var SQLGraphNode = preload("res://addons/gdsql/tabs/sql_graph_node/graph_node.tscn")

const SB_PANEL = preload("res://addons/gdsql/tabs/sql_graph_node/sb_panel.stylebox")
const SB_PANEL_SELECTED = preload("res://addons/gdsql/tabs/sql_graph_node/sb_panel_selected.stylebox")
const SB_SELECT_TITLEBAR = preload("res://addons/gdsql/tabs/sql_graph_node/sb_select_titlebar.stylebox")
const SB_SELECT_TITLEBAR_SELECTED = preload("res://addons/gdsql/tabs/sql_graph_node/sb_select_titlebar_selected.stylebox")

var copied_nodes: Dictionary

const SHORTCUT_UNDO = preload("res://addons/gdsql/tabs/sql_graph_node/shortcut_undo.tres")

const VALID_PORT_COLOR = {
	TYPE_NIL: Color.ALICE_BLUE,
	TYPE_BOOL: Color.ANTIQUE_WHITE,
	TYPE_INT: Color.AQUA,
	TYPE_FLOAT: Color.AQUAMARINE,
	TYPE_STRING: Color.BLUE_VIOLET,
	TYPE_VECTOR2: Color.BROWN,
	TYPE_VECTOR2I: Color.BURLYWOOD,
	TYPE_RECT2: Color.CADET_BLUE,
	TYPE_RECT2I: Color.CHARTREUSE,
	TYPE_VECTOR3: Color.CHOCOLATE,
	TYPE_VECTOR3I: Color.CORAL,
	TYPE_TRANSFORM2D: Color.CORNFLOWER_BLUE,
	TYPE_VECTOR4: Color.CORNSILK,
	TYPE_VECTOR4I: Color.CRIMSON,
	TYPE_PLANE: Color.CYAN,
	TYPE_QUATERNION: Color.DARK_BLUE,
	TYPE_AABB: Color.DARK_CYAN,
	TYPE_BASIS: Color.DARK_GOLDENROD,
	TYPE_TRANSFORM3D: Color.DARK_GREEN,
	TYPE_PROJECTION: Color.DARK_KHAKI,
	TYPE_COLOR: Color.DARK_MAGENTA,
	TYPE_STRING_NAME: Color.DARK_OLIVE_GREEN,
	TYPE_NODE_PATH: Color.DARK_ORANGE,
	TYPE_RID: Color.DARK_ORCHID,
	TYPE_OBJECT: Color.DARK_RED,
	TYPE_CALLABLE: Color.DARK_SALMON,
	TYPE_SIGNAL: Color.DARK_SEA_GREEN,
	TYPE_DICTIONARY: Color.DARK_SLATE_BLUE,
	TYPE_ARRAY: Color.DARK_SLATE_GRAY,
	TYPE_PACKED_BYTE_ARRAY: Color.DARK_TURQUOISE,
	TYPE_PACKED_INT32_ARRAY: Color.DARK_VIOLET,
	TYPE_PACKED_INT64_ARRAY: Color.DEEP_PINK,
	TYPE_PACKED_FLOAT32_ARRAY: Color.DEEP_SKY_BLUE,
	TYPE_PACKED_FLOAT64_ARRAY: Color.DODGER_BLUE,
	TYPE_PACKED_STRING_ARRAY: Color.FIREBRICK,
	TYPE_PACKED_VECTOR2_ARRAY: Color.FLORAL_WHITE,
	TYPE_PACKED_VECTOR3_ARRAY: Color.FOREST_GREEN,
	TYPE_PACKED_COLOR_ARRAY: Color.YELLOW,
}

func _exit_tree():
	for node in get_children():
		if node is GraphNode:
			node_close(node)
	mgr = null
	
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("__table_item", false)
	
func _drop_data(at_position: Vector2, data: Variant) -> void:
	add_item(data, {}, null, at_position / zoom + scroll_offset / zoom)
	
func _shortcut_input(event: InputEvent) -> void:
	if not visible:
		return
	# 避免用户误操作把别的操作撤销掉
	if event.is_pressed() and SHORTCUT_UNDO.matches_event(event):
		printt("Not support undo.")
		get_viewport().set_input_as_handled()
		
func add_item(data: Dictionary, props: Dictionary, asize = null, pos_offset = null, aname = ""):
	grab_focus() # 激活绘图板的快捷键，比如delte， ctrl+C/V
	unselect_all_node()
	
	data = data as Dictionary
	
	var graph_node = SQLGraphNode.instantiate() as GraphNode
	graph_node.set_meta("data", data)
	
	if aname != "":
		graph_node = aname
		
	# 等待页面就绪
	if not get_rect().has_area():
		await resized
		
	if asize != null:
		graph_node.set_deferred("size", asize)
		
	var datas: Array[Array] = []
	for i: Dictionary in data.columns:
		var label_col_name = Label.new()
		label_col_name.text = i.get("Column Name")
		var j = i.duplicate()
		j["Data Type"] = '%s(%s)' % [i["Data Type"], 
			DataTypeDef.DATA_TYPE_COMMON_NAMES.find_key(i["Data Type"])]
		label_col_name.tooltip_text = var_to_str(j)
		label_col_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label_col_name.mouse_filter = Control.MOUSE_FILTER_PASS
		var line_edit_prop = LineEdit.new()
		if props.has(i.get("Column Name")):
			line_edit_prop.text = props[i.get("Column Name")]
		else:
			line_edit_prop.text = i.get("Column Name").to_snake_case()
		line_edit_prop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if i.get("Data Type") in VALID_PORT_COLOR:
			datas.push_back([label_col_name, line_edit_prop])
		else:
			datas.push_back([null, null, label_col_name, line_edit_prop])
			
	graph_node.datas = datas
	graph_node.title = "%s.%s" % [data.db_name, data.table_name]
	graph_node.add_theme_stylebox_override("panel", SB_PANEL)
	graph_node.add_theme_stylebox_override("panel_selected", SB_PANEL_SELECTED)
	graph_node.add_theme_stylebox_override("titlebar", SB_SELECT_TITLEBAR)
	graph_node.add_theme_stylebox_override("titlebar_selected", SB_SELECT_TITLEBAR_SELECTED)
	graph_node.ready.connect(func():
		var index = -1
		for i: Dictionary in data.columns:
			index += 1
			var data_type = i.get("Data Type")
			if data_type in VALID_PORT_COLOR:
				graph_node.set_slot_type_left(index, 0)
				graph_node.set_slot_type_right(index, 0)
				graph_node.set_slot_color_left(index, VALID_PORT_COLOR[data_type])
				graph_node.set_slot_color_right(index, VALID_PORT_COLOR[data_type])
		graph_node.size.x = 650
		graph_node.selected = true
		
		if pos_offset == null:
			graph_node.position_offset = (get_rect().get_center() - \
				graph_node.get_rect().size/2 + scroll_offset) / zoom
		else:
			graph_node.position_offset = pos_offset
	)
	graph_node.delete_request.connect(func():
		node_close(graph_node)
	)
	add_child(graph_node)
	return graph_node
	
## genarate nodes
func _load_nodes(nodes: Dictionary, connections: Array, pos_offset: Vector2, auto_name: bool, select_all = false):
	var node_name_map = {} # 旧name => 新name
	for node_name in nodes:
		var data = nodes[node_name]["data"]
		var props = nodes[node_name]["props"]
		var asize = nodes[node_name]["size"]
		var position_offset = nodes[node_name]["position_offset"] + pos_offset
		var a_name = "" if auto_name else node_name
		var node = await add_item(data, props, asize, position_offset, a_name)
		node_name_map[node_name] = node.name
		
	# make connections
	for info in connections:
		var from = node_name_map[info["from_node"]]
		var to = node_name_map[info["to_node"]]
		_on_graph_edit_connection_request(from, info["from_port"], to, info["to_port"])
		
	# enable会影响connection对象间的数据关联，最好最后设置
	for node_name in nodes:
		var a_node_name = node_name_map[node_name]
		var node = get_node(str(a_node_name)) as GraphNode
		node.enabled = nodes[node_name]["enabled"]
		
	if select_all:
		for i in node_name_map:
			get_node(str(node_name_map[i])).selected = true
			
func get_nodes_params(only_selected = false):
	var all_data = {}
	for graph_node in get_children():
		if not graph_node is GraphNode:
			continue
		if only_selected and not graph_node.selected:
			continue
			
		var props = {}
		for arr: Array in graph_node.datas:
			if arr.size() == 2:
				props[arr[0].text] = arr[1].text
			else:
				props[arr[2].text] = arr[3].text
				
		all_data[graph_node.name.validate_node_name()] = { # validate一下，不然会存在@符号，再次设置name的时候会被替换为下划线
			"data": graph_node.get_meta("data"),
			"props": props,
			"size": graph_node.size,
			"position_offset": graph_node.position_offset,
			"enabled": graph_node.enabled,
		}
		
	return all_data
	
func get_connections_only_selected():
	var ret = []
	var conns = get_connection_list()
	for c in conns:
		if get_node(str(c.from_node)).selected and\
		get_node(str(c.to_node)).selected:
			c.from_node = (c.from_node as String).validate_node_name()
			c.to_node = (c.to_node as String).validate_node_name()
			ret.push_back(c)
	return ret
	
func _on_graph_edit_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	connect_node(from_node, from_port, to_node, to_port)
	mark_modified()
	
func mark_modified(_whatever = null):
	if get_meta("is_file", false):
		change_tab_title.emit(self, get_meta("file_name") + "*")
		
func unselect_all_node():
	for i in get_children():
		if i is GraphNode:
			i.selected = false
			
## 关闭一个节点的时候，把没有关闭按钮的输入节点一起关闭
func node_close(node: GraphNode):
	for info in get_connection_list():
		# 表示node是被输入的节点
		if node.name == info["to_node"]:
			disconnect_node(info["from_node"], info["from_port"], info["to_node"], info["to_port"])
		# 表示node是输入节点
		elif node.name == info["from_node"]:
			disconnect_node(info["from_node"], info["from_port"], info["to_node"], info["to_port"])
			
	node.queue_free()
	
func split_for_tooltip(tooltip: String) -> String:
	const l = 30
	var total_l = tooltip.length()
	if total_l <= l:
		return tooltip
	var arr = []
	var start = 0
	while true:
		arr.push_back(tooltip.substr(start, l))
		if start + l >= total_l:
			break
		start += l
	return "\n".join(arr)
	
func _on_delete_nodes_request(nodes: Array[StringName]) -> void:
	var titles = nodes.map(func(v): return get_node(str(v)).title)
	mgr.create_confirmation_dialog("Are you sure to delete selected nodes `%s`?" % ", ".join(titles),
		func():
			for i in nodes:
				var node = get_node(str(i))
				node_close(node)
				node.queue_free()
			mark_modified()
	)
	
func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	if from_node == to_node:
		return
	connect_node(from_node, from_port, to_node, to_port)
	mark_modified()
	
func _on_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	disconnect_node(from_node, from_port, to_node, to_port)
	mark_modified()
	
func _on_copy_nodes_request(p_copied_data = null) -> void:
	var selected_nodes_params = get_nodes_params(true)
	if selected_nodes_params.is_empty():
		return
	if p_copied_data == null:
		copied_nodes = {
			"data": selected_nodes_params,
			"connections": get_connections_only_selected(),
		}
	else:
		p_copied_data["data"] = selected_nodes_params
		p_copied_data["connections"] = get_connections_only_selected()
		
func _on_paste_nodes_request(p_copied_data = null) -> void:
	if p_copied_data == null:
		if copied_nodes.is_empty():
			return
		_load_nodes(copied_nodes.data, copied_nodes.connections, Vector2(40, 40), true, true)
		for i in copied_nodes.data:
			copied_nodes.data[i].position_offset += Vector2(40, 40)
	else:
		_load_nodes(p_copied_data.data, p_copied_data.connections, Vector2(40, 40), true, true)
		for i in p_copied_data.data:
			p_copied_data.data[i].position_offset += Vector2(40, 40)
			
func _on_duplicate_nodes_request() -> void:
	var tmp_data = {}
	_on_copy_nodes_request(tmp_data)
	_on_paste_nodes_request(tmp_data)
