@tool
extends GraphEdit

signal change_tab_title(page: Control, title: String)
var mgr: GDSQLWorkbenchManagerClass = Engine.get_singleton("GDSQLWorkbenchManager")

var SQLGraphNode = preload("res://addons/gdsql/tabs/sql_graph_node/graph_node.tscn")

const SB_PANEL = preload("res://addons/gdsql/tabs/sql_graph_node/sb_panel.stylebox")
const SB_PANEL_SELECTED = preload("res://addons/gdsql/tabs/sql_graph_node/sb_panel_selected.stylebox")
const SB_SELECT_TITLEBAR = preload("res://addons/gdsql/tabs/sql_graph_node/sb_select_titlebar.stylebox")
const SB_SELECT_TITLEBAR_SELECTED = preload("res://addons/gdsql/tabs/sql_graph_node/sb_select_titlebar_selected.stylebox")

const TEXT_ENUM = preload("res://addons/gdsql/custom_control/text_enum.tscn")

var copied_nodes: Dictionary

const SHORTCUT_SELECTALL = preload("res://addons/gdsql/tabs/sql_graph_node/shortcut_selectall.tres")
const SHORTCUT_UNDO = preload("res://addons/gdsql/tabs/sql_graph_node/shortcut_undo.tres")
const SHORTCUT_QUERY = preload("res://addons/gdsql/tabs/sql_graph_node/shortcut_query.tres")

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

enum LINK_TYPE {
	NONE,
	ASSOCIATION,
	COLLECTION_ARRAY,
}

func _exit_tree():
	for node in get_children():
		if node is GraphNode:
			node_close(node)
	mgr = null
	
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("__table_item", false)
	
func _drop_data(at_position: Vector2, data: Variant) -> void:
	add_item(data, {}, {}, null, at_position / zoom + scroll_offset / zoom)
	
func _shortcut_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	# 避免用户误操作把别的操作撤销掉
	if event.is_pressed():
		if SHORTCUT_UNDO.matches_event(event):
			printt("Not support undo.")
			get_viewport().set_input_as_handled()
		elif SHORTCUT_SELECTALL.matches_event(event):
			select_all_node()
			get_viewport().set_input_as_handled()
			
#{
	#"__table_item": true,
	#"db_name": db_name,
	#"table_name": table_name,
	#"comment": "",
	#"columns": databases[db_name]["tables"][table_name]["columns"],
#}
func add_item(data: Dictionary, props: Dictionary, extra: Dictionary = {}, 
asize = null, pos_offset = null, aname = ""):
	grab_focus() # 激活绘图板的快捷键，比如delte， ctrl+C/V
	unselect_all_node()
	
	data = data as Dictionary
	
	var graph_node = SQLGraphNode.instantiate() as GraphNode
	graph_node.set_meta("data", data)
	graph_node.set_meta("extra", extra)
	
	if aname != "":
		graph_node.title = aname
		
	# 等待页面就绪
	if not get_rect().has_area():
		await resized
		
	var datas: Array[Array] = []
	
	if not extra.is_empty():
		var type = extra.get("link_type", LINK_TYPE.NONE)
		if type != LINK_TYPE.NONE:
			graph_node.set_meta("extra_enabled", true)
			var prop_type = extra.get("link_prop_type", "") # gdscript type or class name
			var prop_name = extra.get("link_prop", "")
			
			var ob_link_type = OptionButton.new()
			ob_link_type.add_item("ASSOCIATION", LINK_TYPE.ASSOCIATION)
			ob_link_type.add_item("COLLECTION_ARRAY", LINK_TYPE.COLLECTION_ARRAY)
			ob_link_type.selected = 0 if type == LINK_TYPE.ASSOCIATION else 1
			ob_link_type.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
			var association_class_name = LineEdit.new()
			association_class_name.caret_blink = true
			association_class_name.placeholder_text = "Class name"
			association_class_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			association_class_name.custom_minimum_size.x = 150
			association_class_name.tooltip_text = (
				"Class name of the property.\n'Entity' is not needed.")
			association_class_name.text = extra.get("association_class_name", "")
			
			var text_enum_suggestion = TEXT_ENUM.instantiate()
			text_enum_suggestion.ready.connect(func():
				text_enum_suggestion.setup(DataTypeDef.DATA_TYPE_COMMON_NAMES.keys(), true)
				text_enum_suggestion._custom_value_submitted(prop_type)
				ob_link_type.item_selected.emit(0 if type == LINK_TYPE.ASSOCIATION else 1)
			)
			text_enum_suggestion.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			text_enum_suggestion.custom_minimum_size.x = 150
			text_enum_suggestion.tooltip_text = "Type of the element of collection."
			text_enum_suggestion.visible = false
			
			ob_link_type.item_selected.connect(func(index):
				if index == 0:
					association_class_name.show()
					text_enum_suggestion.hide()
				else:
					association_class_name.hide()
					text_enum_suggestion.show()
			)
			
			var le_prop_name = LineEdit.new()
			le_prop_name.text = prop_name
			le_prop_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			le_prop_name.placeholder_text = "Property name"
			le_prop_name.tooltip_text = "Property Name"
			
			association_class_name.text_changed.connect(func(new_text: String):
				if new_text.countn(le_prop_name.text) > 0 or \
				le_prop_name.text.countn(new_text) > 0 or \
				new_text.to_snake_case().begins_with(le_prop_name.text) or \
				le_prop_name.text.begins_with(new_text.to_snake_case()):
					le_prop_name.text = new_text.to_snake_case()
			)
			
			datas.push_back([null, null, ob_link_type, association_class_name, 
				text_enum_suggestion, le_prop_name])
			
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
		update_slot_status(graph_node)
		
		if asize == null:
			graph_node.size.x = 650
		else:
			graph_node.set_deferred("size", asize)
			
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
	
func update_slot_status(graph_node: GraphNode):
	var index = 0 if graph_node.get_meta("extra_enabled", false) else -1
	if index == 0:
		graph_node.set_slot_enabled_left(index, false)
		graph_node.set_slot_enabled_right(index, false)
		
	var data = graph_node.get_meta("data")
	for i: Dictionary in data.columns:
		index += 1
		var data_type = i.get("Data Type")
		if data_type in VALID_PORT_COLOR:
			graph_node.set_slot_type_left(index, 0)
			graph_node.set_slot_type_right(index, 0)
			graph_node.set_slot_color_left(index, VALID_PORT_COLOR[data_type])
			graph_node.set_slot_color_right(index, VALID_PORT_COLOR[data_type])
			
## genarate nodes
func _load_nodes(nodes: Dictionary, connections: Array, pos_offset: Vector2, 
auto_name: bool, select_all = false):
	var node_name_map = {} # 旧name => 新name
	var node_sizes = {}
	for node_name in nodes:
		var data = nodes[node_name]["data"]
		var props = nodes[node_name]["props"]
		var extra = nodes[node_name]["extra"]
		var asize = nodes[node_name]["size"]
		var position_offset = nodes[node_name]["position_offset"] + pos_offset * nodes.size()
		var a_name = "" if auto_name else node_name
		var node = await add_item(data, props, extra, asize, position_offset, a_name)
		node_name_map[node_name] = node.name
		node_sizes[node.name] = asize
		
	# make connections
	var tos = {}
	for info in connections:
		var from = node_name_map[info["from_node"]]
		var to = node_name_map[info["to_node"]]
		tos[str(to)] = 1
		_on_graph_edit_connection_request(from, info["from_port"], to, info["to_port"])
		
	# enable会影响connection对象间的数据关联，最好最后设置
	for node_name in nodes:
		var a_node_name = node_name_map[node_name]
		var node = get_node(str(a_node_name)) as GraphNode
		node.enabled = nodes[node_name]["enabled"]
		
	# 孤立的node，不要显示额外控件
	for i in node_name_map:
		var n = str(node_name_map[i])
		if not tos.has(n):
			hide_extra_control(get_node(n), node_sizes[n])
			
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
		var extra = {}
		for arr: Array in graph_node.datas:
			if arr.size() == 2:
				props[arr[0].text] = arr[1].text
			elif arr.size() == 4:
				props[arr[2].text] = arr[3].text
			elif arr.size() == 6:
				extra["link_type"] = (arr[2] as OptionButton).get_selected_id()
				if extra["link_type"] == LINK_TYPE.ASSOCIATION:
					extra["link_prop_type"] = (arr[3] as LineEdit).text
				else:
					extra["link_prop_type"] = arr[4].get_selected_text()
				extra["link_prop"] = (arr[5] as LineEdit).text.strip_edges()
				extra["association_class_name"] = (arr[3] as LineEdit).text
			else:
				assert(false, "Inner error check this in mapper_graph_edit.gd")
				
		# validate一下，不然会存在@符号，再次设置name的时候会被替换为下划线
		all_data[graph_node.name.validate_node_name()] = { 
			"data": graph_node.get_meta("data"),
			"props": props,
			"extra": extra,
			"size": graph_node.size,
			"position_offset": graph_node.position_offset,
			"enabled": graph_node.enabled,
		}
		
	return all_data
	
func get_node_extra(node: GraphNode) -> Dictionary:
	var extra = {}
	for arr: Array in node.datas:
		if arr.size() == 6:
			extra["link_type"] = (arr[2] as OptionButton).get_selected_id()
			if extra["link_type"] == LINK_TYPE.ASSOCIATION:
				extra["link_prop_type"] = (arr[3] as LineEdit).text
			else:
				extra["link_prop_type"] = arr[4].get_selected_text()
			extra["link_prop"] = (arr[5] as LineEdit).text.strip_edges()
			break
	return extra
	
func get_node_props(node: GraphNode) -> Dictionary:
	var props = {}
	for arr: Array in node.datas:
		if arr.size() == 2:
			props[arr[0].text] = arr[1].text
		elif arr.size() == 4:
			props[arr[2].text] = arr[3].text
	return props
	
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
	
func _on_graph_edit_connection_request(from_node: StringName, from_port: int, 
to_node: StringName, to_port: int) -> void:
	connect_node(from_node, from_port, to_node, to_port)
	mark_modified()
	
func mark_modified(_whatever = null):
	if owner.get_meta("is_file", false):
		owner.change_tab_title.emit(owner, owner.get_meta("file_name") + "*")
		
func select_all_node():
	for i in get_children():
		if i is GraphNode:
			i.selected = true
			
func unselect_all_node():
	for i in get_children():
		if i is GraphNode:
			i.selected = false
			
func get_selected_nodes():
	return get_children().filter(func(v):
		return v is GraphNode and v.selected
	)
	
## 关闭一个节点的时候，把没有关闭按钮的输入节点一起关闭
func node_close(node: GraphNode):
	for info in get_connection_list():
		# 表示node是被输入的节点
		if node.name == info["to_node"]:
			disconnect_node(info["from_node"], info["from_port"], 
				info["to_node"], info["to_port"])
		# 表示node是输入节点
		elif node.name == info["from_node"]:
			disconnect_node(info["from_node"], info["from_port"], 
				info["to_node"], info["to_port"])
			
	node.queue_free()
	
func _on_delete_nodes_request(nodes: Array[StringName]) -> void:
	var titles = nodes.map(func(v): return get_node(str(v)).title)
	mgr.create_confirmation_dialog(
		split_for_long_content(
			"Are you sure to delete selected nodes `%s`?" % ", ".join(titles)),
		func():
			for i in nodes:
				var node = get_node(str(i))
				node_close(node)
				node.queue_free()
			mark_modified()
	)
	
func split_for_long_content(content: String) -> String:
	const l = 70
	var total_l = content.length()
	if total_l <= l:
		return content
	var arr = []
	var start = 0
	while true:
		arr.push_back(content.substr(start, l))
		if start + l >= total_l:
			break
		start += l
	return "\n".join(arr)
	
func _on_connection_request(from_node: StringName, from_port: int, 
to_node: StringName, to_port: int) -> void:
	if from_node == to_node:
		return
		
	# 两个节点之间可以连多条线，但是不允许多个节点连出到同一个节点。
	# 对to节点来说，只允许from一个节点，所以把前面的先去掉
	#var alreay = false
	var graph_node = get_node(str(to_node)) as GraphNode
	for i in get_connection_list():
		if i.to_node == to_node and i.from_node != from_node:
			#alreay = true
			_on_disconnection_request(i.from_node, i.from_port, i.to_node, 
				i.to_port, graph_node.size)
				
	connect_node(from_node, from_port, to_node, to_port)
	
	# to的一方，增加选项，让用户选择和输入关联属性和属性类型
	if graph_node.has_meta("extra_controls"):
		var extra_controls = graph_node.get_meta("extra_controls")
		graph_node.remove_meta("extra_controls")
		var datas = (graph_node.datas as Array).duplicate()
		datas.push_front(extra_controls)
		graph_node.datas = datas
		graph_node.set_meta("extra_enabled", true)
		update_slot_status(graph_node)
	elif not graph_node.get_meta("extra_enabled", false):
		var type = LINK_TYPE.ASSOCIATION
		var prop_type = "Nil"
		var prop_name = ""
		
		var ob_link_type = OptionButton.new()
		ob_link_type.add_item("ASSOCIATION", LINK_TYPE.ASSOCIATION)
		ob_link_type.add_item("COLLECTION_ARRAY", LINK_TYPE.COLLECTION_ARRAY)
		ob_link_type.selected = 0 if type == LINK_TYPE.ASSOCIATION else 1
		ob_link_type.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ob_link_type.fit_to_longest_item = false
		
		var association_class_name = LineEdit.new()
		association_class_name.caret_blink = true
		association_class_name.placeholder_text = "Class name"
		association_class_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		association_class_name.custom_minimum_size.x = 150
		association_class_name.tooltip_text = (
			"Class name of the property.\n'Entity' is not needed.")
		
		var text_enum_suggestion = TEXT_ENUM.instantiate()
		text_enum_suggestion.ready.connect(func():
			text_enum_suggestion.setup(DataTypeDef.DATA_TYPE_COMMON_NAMES.keys(), true)
			text_enum_suggestion.value = prop_type
			text_enum_suggestion.update_property()
		)
		text_enum_suggestion.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text_enum_suggestion.custom_minimum_size.x = 150
		text_enum_suggestion.tooltip_text = "Type of the element of collection."
		text_enum_suggestion.visible = false
		
		ob_link_type.item_selected.connect(func(index):
			if index == 0:
				association_class_name.show()
				text_enum_suggestion.hide()
			else:
				association_class_name.hide()
				text_enum_suggestion.show()
		)
		
		var le_prop_name = LineEdit.new()
		le_prop_name.text = prop_name
		le_prop_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		le_prop_name.placeholder_text = "Property name"
		le_prop_name.tooltip_text = "Property Name"
		
		association_class_name.text_changed.connect(func(new_text: String):
			if new_text.countn(le_prop_name.text) > 0 or \
			le_prop_name.text.countn(new_text) > 0 or \
			new_text.to_snake_case().begins_with(le_prop_name.text) or \
			le_prop_name.text.begins_with(new_text.to_snake_case()):
				le_prop_name.text = new_text.to_snake_case()
		)
		
		var datas = (graph_node.datas as Array).duplicate()
		datas.push_front([null, null, ob_link_type, association_class_name, 
			text_enum_suggestion, le_prop_name])
		graph_node.datas = datas
		graph_node.set_meta("extra_enabled", true)
		update_slot_status(graph_node)
		
	#if not alreay:
		#graph_node.set_deferred("size", Vector2(graph_node.size.x + 200, graph_node.size.y))
	
	mark_modified()
	
func _on_disconnection_request(from_node: StringName, from_port: int, 
to_node: StringName, to_port: int, asize = null) -> void:
	disconnect_node(from_node, from_port, to_node, to_port)
	
	# 如果没有连入的线，则隐藏选项
	var tos = {}
	for info in get_connection_list():
		tos[info.to_node] = 1
	if not tos.has(to_node):
		hide_extra_control(get_node(str(to_node)), asize)
		
	mark_modified()
	
func hide_extra_control(graph_node: GraphNode, asize = null):
	if graph_node.get_meta("extra_enabled", false):
		var datas = (graph_node.datas as Array).duplicate()
		var extra_controls = datas.pop_front()
		graph_node.datas = datas
		graph_node.set_meta("extra_controls", extra_controls)
		graph_node.set_meta("extra_enabled", false)
		# shrink
		if asize:
			graph_node.set_deferred("size", Vector2(asize.x, 0))
		else:
			graph_node.set_deferred("size", Vector2(graph_node.size.x, 0))
		update_slot_status(graph_node)
		
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
		_load_nodes(copied_nodes.data, copied_nodes.connections, Vector2(40, 40), 
			true, true)
		for i in copied_nodes.data:
			copied_nodes.data[i].position_offset += Vector2(40, 40) * copied_nodes.data.size()
	else:
		_load_nodes(p_copied_data.data, p_copied_data.connections, Vector2(40, 40), 
			true, true)
		for i in p_copied_data.data:
			p_copied_data.data[i].position_offset += Vector2(40, 40) * p_copied_data.data.size()
			
func _on_duplicate_nodes_request() -> void:
	var tmp_data = {}
	_on_copy_nodes_request(tmp_data)
	_on_paste_nodes_request(tmp_data)
	
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
		
	var selected_nodes = get_selected_nodes()
	if selected_nodes.is_empty():
		return
		
	if event.is_pressed() and SHORTCUT_QUERY.matches_event(event):
		for node in selected_nodes:
			for arr in node.datas:
				for i in arr:
					if i is Button and (i as Button).text.to_lower() in ["apply", "query"]:
						(i as Button).pressed.emit()
		get_viewport().set_input_as_handled()
		return
		
	if not event is InputEventKey:
		return
		
	var k = event as InputEventKey
	if not k.is_pressed():
		return
		
	if is_ancestor_of(get_viewport().gui_get_focus_owner()):
		return
		
	var distance = snapping_distance if snapping_enabled else 1
	if k.keycode == KEY_UP:
		for node in selected_nodes:
			node.position_offset.y -= distance
		get_viewport().set_input_as_handled()
	elif k.keycode == KEY_DOWN:
		for node in selected_nodes:
			node.position_offset.y += distance
		get_viewport().set_input_as_handled()
	elif k.keycode == KEY_LEFT:
		for node in selected_nodes:
			node.position_offset.x -= distance
		get_viewport().set_input_as_handled()
	elif k.keycode == KEY_RIGHT:
		for node in selected_nodes:
			node.position_offset.x += distance
		get_viewport().set_input_as_handled()
