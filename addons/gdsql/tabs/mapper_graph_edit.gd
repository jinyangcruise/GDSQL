@tool
extends GraphEdit

signal change_tab_title(page: Control, title: String)

var SQLGraphNode = preload("res://addons/gdsql/tabs/sql_graph_node/graph_node.tscn")

const SB_PANEL = preload("res://addons/gdsql/tabs/sql_graph_node/sb_panel.stylebox")
const SB_PANEL_SELECTED = preload("res://addons/gdsql/tabs/sql_graph_node/sb_panel_selected.stylebox")
const SB_SELECT_TITLEBAR = preload("res://addons/gdsql/tabs/sql_graph_node/sb_select_titlebar.stylebox")
const SB_SELECT_TITLEBAR_SELECTED = preload("res://addons/gdsql/tabs/sql_graph_node/sb_select_titlebar_selected.stylebox")

const TEXT_ENUM = preload("res://addons/gdsql/custom_control/text_enum.tscn")

static var copied_nodes: Dictionary

const SHORTCUT_SELECTALL = preload("res://addons/gdsql/tabs/sql_graph_node/shortcut_selectall.tres")
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
	TYPE_PACKED_VECTOR4_ARRAY: Color.FUCHSIA,
	TYPE_PACKED_COLOR_ARRAY: Color.YELLOW,
}

enum LINK_TYPE {
	NONE = 0,
	ASSOCIATION = 1,
	COLLECTION_ARRAY,
	LINK_HELPER, # 用于关联表（一对一或一对多，取决于后续表的选择），关联表中的数据不会生成实体类
}

var drag_dirty = false
var drag_buffer: Array
var cached_theme_base_scale = 1.0
var frame_node_id_to_link_to
var nodes_link_to_frame_buffer: Array
var include_file_index = -1

func _init() -> void:
	graph_elements_linked_to_frame_request.connect(_nodes_linked_to_frame_request)
	
func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		cached_theme_base_scale = get_theme_default_base_scale()
		
func _exit_tree():
	for node in get_children():
		if node is GraphNode:
			node_close(node)
	
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	# { "type": "files", "files": ["res://src/dao/t_hero.gdmappergraph"], "from": @Tree@6840:<Tree#603409380691> }
	if data is Dictionary:
		if data.has("type") and data.has("files") and data.get("type") == "files":
			for i in data.get("files"):
				if i is String:
					if i.ends_with(".gdmappergraph"):
						return true
	return data is Dictionary and data.get("__table_item", false)
	
func _drop_data(at_position: Vector2, data: Variant) -> void:
	if data is Dictionary:
		if data.has("type") and data.has("files") and data.get("type") == "files":
			for i in data.get("files"):
				if i is String and i.ends_with(".gdmappergraph"):
					GDSQL.WorkbenchManager.open_mapper_graph_file_tab.emit(i)
			return
			
		if data.get("__table_item", false):
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
asize = null, pos_offset = null, aname = "", path = "/root"):
	grab_focus() # 激活绘图板的快捷键，比如delte， ctrl+C/V
	unselect_all_node()
	
	data = data as Dictionary
	
	var graph_node = SQLGraphNode.instantiate() as GraphNode
	graph_node.set_meta("data", data)
	graph_node.set_meta("extra", extra)
	graph_node.set_meta("include_path", path)
	
	if aname != "":
		graph_node.name = aname
		
	# 等待页面就绪
	if not get_rect().has_area():
		await resized
		
	var datas: Array[Array] = []
	
	var type = extra.get("link_type", LINK_TYPE.NONE)
	graph_node.set_meta("extra_enabled", true) # NOTICE 改为了永远显示
	var prop_type = extra.get("link_prop_type", "") # gdscript type or class name
	var prop_name = extra.get("link_prop", "")
	
	var ob_link_type = OptionButton.new()
	ob_link_type.fit_to_longest_item = false
	ob_link_type.add_item("NONE", LINK_TYPE.NONE)
	if type == LINK_TYPE.NONE:
		ob_link_type.set_item_disabled(0, true)
	ob_link_type.add_item("ASSOCIATION", LINK_TYPE.ASSOCIATION)
	ob_link_type.add_item("COLLECTION_ARRAY", LINK_TYPE.COLLECTION_ARRAY)
	ob_link_type.add_separator("table for linking two tables")
	ob_link_type.add_item("LINK_HELPER", LINK_TYPE.LINK_HELPER)
	for i in ob_link_type.item_count:
		if ob_link_type.get_item_id(i) == type:
			ob_link_type.selected = i
		if type == LINK_TYPE.NONE:
			ob_link_type.set_item_disabled(i, i != 0)
		else:
			ob_link_type.set_item_disabled(i, i == 0)
			
	ob_link_type.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var association_class_name = LineEdit.new()
	association_class_name.caret_blink = true
	association_class_name.placeholder_text = "Class name"
	association_class_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	association_class_name.custom_minimum_size.x = 150
	association_class_name.tooltip_text = (
		"Class name of the property.\n'Entity' is not needed.")
	association_class_name.text = extra.get("association_class_name", data.table_name.to_pascal_case())
	
	var text_enum_suggestion = TEXT_ENUM.instantiate()
	text_enum_suggestion.ready.connect(func():
		text_enum_suggestion.setup(GDSQL.DataTypeDef.DATA_TYPE_COMMON_NAMES.keys(), true)
		text_enum_suggestion._custom_value_submitted(prop_type)
		for i in ob_link_type.item_count:
			if ob_link_type.get_item_id(i) == type:
				ob_link_type.item_selected.emit(i)
				break
	)
	text_enum_suggestion.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_enum_suggestion.custom_minimum_size.x = 150
	text_enum_suggestion.tooltip_text = "Type of the element of collection."
	text_enum_suggestion.visible = false
	
	var le_prop_name = LineEdit.new()
	le_prop_name.text = prop_name
	le_prop_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	le_prop_name.placeholder_text = "Property name"
	le_prop_name.tooltip_text = "Property Name"
	
	ob_link_type.item_selected.connect(func(index):
		match ob_link_type.get_item_id(index):
			LINK_TYPE.NONE:
				association_class_name.show()
				text_enum_suggestion.hide()
				le_prop_name.hide()
			LINK_TYPE.ASSOCIATION:
				association_class_name.show()
				text_enum_suggestion.hide()
				le_prop_name.show()
			LINK_TYPE.COLLECTION_ARRAY:
				association_class_name.hide()
				text_enum_suggestion.show()
				le_prop_name.show()
			LINK_TYPE.LINK_HELPER:
				association_class_name.hide()
				text_enum_suggestion.hide()
				le_prop_name.hide()
			_:
				push_error("Invalid index %s mapper_graph_edit.gd in 183." % index)
	)
	
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
			GDSQL.DataTypeDef.DATA_TYPE_COMMON_NAMES.find_key(i["Data Type"])]
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
	add_child(graph_node, true)
	graph_node.dragged.connect(_node_dragged.bind(graph_node))
	return graph_node
	
func add_frame(title: String, pos_offset = null, aname = "", support_drag_into = false):
	grab_focus() # 激活绘图板的快捷键，比如delte， ctrl+C/V
	unselect_all_node()
	
	# 等待页面就绪
	if not get_rect().has_area():
		await resized
		
	var graph_frame := GraphFrame.new()
	graph_frame.title = title
	if aname != "":
		graph_frame.name = aname
		
	if pos_offset == null:
		graph_frame.position_offset = (get_rect().get_center() - \
			graph_frame.get_rect().size/2 + scroll_offset) / zoom
	else:
		graph_frame.position_offset = pos_offset
		
	if support_drag_into:
		var frame_hint_label = Label.new()
		frame_hint_label.focus_mode = Control.FOCUS_ACCESSIBILITY
		graph_frame.add_child(frame_hint_label)
		
		frame_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		frame_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		frame_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		frame_hint_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		frame_hint_label.text = tr("Drag and drop nodes here to attach them.")
		frame_hint_label.modulate = Color(1.0, 1.0, 1.0, 0.3)
		graph_frame.autoshrink_enabled = true
		graph_frame.custom_minimum_size = Vector2(600, 400)
	else:
		graph_frame.autoshrink_enabled = true
		
	graph_frame.set_meta("support_drag_into", support_drag_into)
	add_child(graph_frame, true)
	return graph_frame
	
func include_file(file_path: String, p_path = "/root", pos_offset = null,
first_node_position_offset = null, p_name = "", depth = 0, include_connections = []):
	if file_path == "":
		return
		
	if depth > 1024:
		push_error("Depth is greater than 1024! A recursive include exist, maybe!")
		return
		
	if depth == 0 and p_path == "/root":
		p_path += "/%s" % get_include_count()
		
	if pos_offset == null:
		pos_offset = get_rect().get_center()
		first_node_position_offset = pos_offset
		
	var config = GDSQL.ImprovedConfigFile.new()
	config.load(file_path)
	var nodes = config.get_value("data", "nodes", {})
	var cons = config.get_value("data", "connections", [])
	
	var include_index = get_next_include_index()
	
	# 连接数据中的序号进行偏移
	for c in cons:
		if not c.has("from_include_path"):
			continue
		c.from_include_index += include_index + 1
		c.to_include_index += include_index + 1
		if c.from_node.contains("_include_"):
			c.from_node = c.from_node.substr(0, c.from_node.find("_include_")) + ("_include_%s" % c.from_include_index)
		else:
			c.from_node += "_include_%s" % c.from_include_index
		if c.to_node.contains("_include_"):
			c.to_node = c.to_node.substr(0, c.to_node.find("_include_")) + ("_include_%s" % c.to_include_index)
		else:
			c.to_node += "_include_%s" % c.to_include_index
			
	var graph_frame = await add_frame(file_path, pos_offset, p_name, false)
	graph_frame.set_meta("include_depth", depth)
	graph_frame.set_meta("include_index", include_index)
	
	var added_nodes = await _load_nodes(nodes, cons, pos_offset,
		false, false, p_path, include_index, include_connections)
		
	var includes = config.get_value("data", "include_files", {})
	var sub_frames = {}
	for i in includes:
		var path = p_path + "/" + str(i)
		var sub_frame = await include_file(includes[i].file_path, path,
			includes[i].position_offset + pos_offset, 
			includes[i].first_node_position_offset + first_node_position_offset,
			includes[i].name, depth + 1, include_connections)
		sub_frames[i] = sub_frame
		
	for anode in added_nodes:
		attach_graph_element_to_frame(anode.name, graph_frame.name)
		
	for i in sub_frames:
		attach_graph_element_to_frame(sub_frames[i].name, graph_frame.name)
		
	if depth == 0 and not include_connections.is_empty():
		for info in include_connections:
			_on_graph_edit_connection_request(info.from_node, info.from_port, info.to_node, info.to_port)
			
	# Make sure position not move.
	if not added_nodes.is_empty():
		var first_node_pos_conf = nodes[nodes.keys().front()].position_offset
		for i in includes:
			var frame_name = sub_frames[i].name
			var include_first_node_should_at_pos = includes[i].first_node_position_offset - \
				first_node_pos_conf + added_nodes[0].position_offset
			var diff = null
			for e_name in get_attached_nodes_of_frame(frame_name):
				var element = get_node(str(e_name))
				if element is GraphNode:
					if diff == null:
						diff = include_first_node_should_at_pos - element.position_offset
					element.position_offset += diff
			if diff != null:
				for e_name in get_attached_nodes_of_frame(frame_name):
					var element = get_node(str(e_name))
					if element is GraphFrame:
						_set_position_of_frame_attached_nodes(element, diff)
						
	return graph_frame
	
func _set_position_of_frame_attached_nodes(p_frame: GraphFrame, diff: Vector2) -> void:
	for attached_node_name in get_attached_nodes_of_frame(p_frame.name):
		var attached_node: GraphElement = get_node_or_null(str(attached_node_name))
		if not attached_node:
			continue
			
		#var pos: Vector2 = (attached_node.position_offset * zoom + diff) / zoom
		var pos: Vector2 = attached_node.position_offset + diff
		# 异或，即当两个值不同时结果为 true，相同时结果为 false。
		if snapping_enabled != Input.is_key_pressed(KEY_CTRL):
			pos = pos.snapped(Vector2(snapping_distance, snapping_distance))
			
		if attached_node is GraphNode:
			attached_node.position_offset = pos
		if attached_node is GraphFrame:
			_set_position_of_frame_attached_nodes(attached_node, diff)
			
func _nodes_linked_to_frame_request(p_nodes: Array, p_frame: StringName):
	frame_node_id_to_link_to = p_frame
	nodes_link_to_frame_buffer = p_nodes.duplicate()
	
func _node_dragged(p_from: Vector2, p_to: Vector2, p_node: Node):
	drag_buffer.push_back([p_node, p_from / cached_theme_base_scale, p_to / cached_theme_base_scale]);
	if not drag_dirty:
		_nodes_dragged.call_deferred()
	drag_dirty = true
	
func _nodes_dragged():
	drag_dirty = false;
	# TODO undo redo 所以暂时用不上drag_buffer
	drag_buffer.clear()
	
	if not nodes_link_to_frame_buffer.is_empty():
		var frame = get_node(str(frame_node_id_to_link_to)) as GraphFrame
		if frame.get_meta("support_drag_into", false):
			for i in nodes_link_to_frame_buffer:
				attach_graph_element_to_frame(i, frame_node_id_to_link_to)
			frame.get_child(0).hide()
			
		nodes_link_to_frame_buffer.clear()
		
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
func _load_nodes(nodes: Dictionary, p_connections: Array, pos_offset: Vector2,
auto_name: bool, select_all: bool = false, p_path: String = "/root",
p_include_file_index: int = -1, include_connections: Array = []):
	var ret_nodes = []
	var node_name_map = {} # 旧name => 新name
	var node_sizes = {}
	for node_name in nodes:
		var data = nodes[node_name].data
		var props = nodes[node_name].props
		var extra = nodes[node_name].extra
		var asize = nodes[node_name].size
		var position_offset = nodes[node_name].position_offset + pos_offset
		var a_name = "MapperGraph" if auto_name else node_name
		if p_path != "/root":
			a_name += "_include_%s" % p_include_file_index
		var node = await add_item(data, props, extra, asize, position_offset, a_name, p_path)
		node.set_meta("include_index", p_include_file_index)
		node.set_meta("original_name", node_name)
		ret_nodes.push_back(node)
		node_name_map[node_name] = node.name
		node_sizes[node.name] = asize
		
	# make connections
	var tos = {}
	for info in p_connections:
		# 涉及include的，后续特殊处理。
		if info.has("from_include_path") or info.has("to_include_path"):
			tos[str(info.to_node)] = 1
			include_connections.push_back(info)
			continue
		var from = node_name_map[info.from_node]
		var to = node_name_map[info.to_node]
		tos[str(to)] = 1
		_on_graph_edit_connection_request(from, info.from_port, to, info.to_port)
		
	for node_name in nodes:
		var a_node_name = node_name_map[node_name]
		var node = get_node(str(a_node_name)) as GraphNode
		node.enabled = nodes[node_name].enabled
		
	for i in node_name_map:
		var n = str(node_name_map[i])
		if not tos.has(n):
			update_extra_controls_to_none(get_node(n))
		else:
			update_extra_controls_to_others(get_node(n))
			
	if select_all:
		for i in node_name_map:
			get_node(str(node_name_map[i])).selected = true
			
	return ret_nodes
	
func get_nodes_params(only_selected = false):
	var all_data = {}
	for graph_node in get_children():
		if not graph_node is GraphNode:
			continue
		if only_selected and not graph_node.selected:
			continue
		if graph_node.get_meta("include_path", "/root") != "/root":
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
	
func get_inlcude_params(only_selected = false):
	var all_data = {}
	for graph_frame in get_children():
		if not graph_frame is GraphFrame:
			continue
			
		if graph_frame.get_meta("include_depth") != 0:
			continue
			
		graph_frame = graph_frame as GraphFrame
		if only_selected and not graph_frame.selected:
			continue
			
		var first_node_position_offset = null
		var first_node = null
		for i in get_attached_nodes_of_frame(graph_frame.name):
			if get_node(str(i)) is GraphNode:
				first_node_position_offset = get_node(str(i)).position_offset
				first_node = get_node(str(i))
				break
		if not first_node_position_offset:
			first_node_position_offset = graph_frame.position_offset
			
		all_data[graph_frame.get_meta("include_index")] = {
			"file_path": graph_frame.title,
			"position_offset": graph_frame.position_offset,
			"name": graph_frame.name.validate_node_name(),
			"first_node_position_offset": first_node_position_offset,
			"first_node": "%s:%s" % [first_node, first_node.title],
		}
		
	return all_data
	
## 获取包含的include的文件数量，不包括嵌套的。
func get_include_count() -> int:
	var ret = 0
	for graph_frame in get_children():
		if not graph_frame is GraphFrame:
			continue
		if graph_frame.get_meta("include_depth") != 0:
			continue
		ret += 1
	return ret
	
func get_next_include_index() -> int:
	var arr_index = []
	for graph_frame in get_children():
		if not graph_frame is GraphFrame:
			continue
		if not graph_frame.has_meta("include_index"):
			printt("?FDFsdf", graph_frame, graph_frame.title)
		arr_index.push_back(graph_frame.get_meta("include_index"))
		
	var index = -1
	while true:
		index += 1
		if not arr_index.has(index):
			return index
	push_error("Bug?")
	return -1
	
func get_connection_params(only_selected = false):
	var ret = []
	for v in get_connection_list():
		if only_selected and (not get_node(str(v.from_node)).selected or
		not get_node(str(v.to_node)).selected):
			continue
			
		var from_include_path = get_node(str(v.from_node)).get_meta("include_path", "/root")
		var to_include_path = get_node(str(v.to_node)).get_meta("include_path", "/root")
		if from_include_path == "/root" or to_include_path == "/root" or \
		(longest_common_path_prefix(from_include_path, to_include_path) == "/root"):
			v["from_node"] = v["from_node"].validate_node_name()
			v["to_node"] = v["to_node"].validate_node_name()
			v["from_include_path"] = from_include_path
			v["to_include_path"] = to_include_path
			v["from_include_index"] = get_node(str(v.from_node)).get_meta("include_index", -1)
			v["to_include_index"] = get_node(str(v.to_node)).get_meta("include_index", -1)
			ret.push_back(v)
	return ret
	
func longest_common_path_prefix(path1: String, path2: String) -> String:
	var parts1 = path1.trim_prefix("/").split("/")
	var parts2 = path2.trim_prefix("/").split("/")
	
	var common = []
	for i in min(parts1.size(), parts2.size()):
		if parts1[i] == parts2[i]:
			common.append(parts1[i])
		else:
			break
			
	return "/" + "/".join(common) if not common.is_empty() else ""
	
func is_helper_node(node: GraphNode) -> bool:
	for arr: Array in node.datas:
		if arr.size() == 6:
			if (arr[2] as OptionButton).get_selected_id() == LINK_TYPE.LINK_HELPER:
				return true
	return false
	
func get_node_extra(node: GraphNode) -> Dictionary:
	var extra = {}
	for arr: Array in node.datas:
		if arr.size() == 6:
			extra["link_type"] = (arr[2] as OptionButton).get_selected_id()
			if extra["link_type"] == LINK_TYPE.ASSOCIATION \
			or extra["link_type"] == LINK_TYPE.NONE:
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
	
func _on_graph_edit_connection_request(from_node: StringName, from_port: int,
to_node: StringName, to_port: int) -> void:
	connect_node(from_node, from_port, to_node, to_port)
	mark_modified()
	
func mark_modified(_whatever = null):
	if owner.get_meta("is_file", false):
		owner.change_tab_title.emit(owner, owner.get_meta("file_name") + "*")
		
func select_all_node():
	for i in get_children():
		if i is GraphElement:
			i.selected = true
			
func unselect_all_node():
	for i in get_children():
		if i is GraphElement:
			i.selected = false
			
func get_selected_nodes():
	return get_children().filter(func(v):
		return v is GraphElement and v.selected
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
	GDSQL.WorkbenchManager.create_confirmation_dialog(
		split_for_long_content(
			"Are you sure to delete selected nodes `%s`?" % ", ".join(titles)),
		func():
			for i in nodes:
				var node = get_node(str(i))
				if node is GraphNode:
					node_close(node)
				elif node is GraphFrame:
					pass
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
	# TODO 是否有例外的情况：当请求连接的多个节点拥有共同的同一个来源节点时，就能连到同一个节点上？
	# 也就是说请求连接的多个节点都是helper时，且它们有共同的同一个来源
	#var alreay = false
	# 先连接这次的，再取消以前的，因为_on_disconnection_request会判断是否有接入的线，从而
	# 决定是否显示extra controls
	connect_node(from_node, from_port, to_node, to_port)
	var graph_node = get_node(str(to_node)) as GraphNode
	for i in get_connection_list():
		if i.to_node == to_node and i.from_node != from_node:
			#alreay = true
			_on_disconnection_request(i.from_node, i.from_port, i.to_node,
				i.to_port, graph_node.size, false)
				
	update_extra_controls_to_others(graph_node)
	update_slot_status(graph_node)
	# to的一方，增加选项，让用户选择和输入关联属性和属性类型
	#if graph_node.has_meta("extra_controls"):
		#var extra_controls = graph_node.get_meta("extra_controls")
		#graph_node.remove_meta("extra_controls")
		#var datas = (graph_node.datas as Array).duplicate()
		#datas.push_front(extra_controls)
		#graph_node.datas = datas
		#graph_node.set_meta("extra_enabled", true)
		#update_slot_status(graph_node)
	#elif not graph_node.get_meta("extra_enabled", false):
		#var type = LINK_TYPE.ASSOCIATION
		#var prop_type = "Nil"
		#var prop_name = ""
		#
		#var ob_link_type = OptionButton.new()
		#ob_link_type.add_item("NONE", 0)
		#ob_link_type.set_item_disabled(0, true)
		#ob_link_type.add_item("ASSOCIATION", LINK_TYPE.ASSOCIATION)
		#ob_link_type.add_item("COLLECTION_ARRAY", LINK_TYPE.COLLECTION_ARRAY)
		#ob_link_type.add_separator("table for linking two tables")
		#ob_link_type.add_item("ASSOCIATION_HELPER", LINK_TYPE.LINK_HELPER)
		#for i in ob_link_type.item_count:
			#if ob_link_type.get_item_id(i) == type:
				#ob_link_type.selected = i
				#break
		#ob_link_type.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		#ob_link_type.fit_to_longest_item = false
		#
		#var association_class_name = LineEdit.new()
		#association_class_name.caret_blink = true
		#association_class_name.placeholder_text = "Class name"
		#association_class_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		#association_class_name.custom_minimum_size.x = 150
		#association_class_name.tooltip_text = (
			#"Class name of the property.\n'Entity' is not needed.")
		#
		#var text_enum_suggestion = TEXT_ENUM.instantiate()
		#text_enum_suggestion.ready.connect(func():
			#text_enum_suggestion.setup(GDSQL.DataTypeDef.DATA_TYPE_COMMON_NAMES.keys(), true)
			#text_enum_suggestion.value = prop_type
			#text_enum_suggestion.update_property()
		#)
		#text_enum_suggestion.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		#text_enum_suggestion.custom_minimum_size.x = 150
		#text_enum_suggestion.tooltip_text = "Type of the element of collection."
		#text_enum_suggestion.visible = false
		#
		#var le_prop_name = LineEdit.new()
		#le_prop_name.text = prop_name
		#le_prop_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		#le_prop_name.placeholder_text = "Property name"
		#le_prop_name.tooltip_text = "Property Name"
		#
		#ob_link_type.item_selected.connect(func(index):
			#match ob_link_type.get_item_id(index):
				#LINK_TYPE.ASSOCIATION:
					#association_class_name.show()
					#text_enum_suggestion.hide()
					#le_prop_name.show()
				#LINK_TYPE.COLLECTION_ARRAY:
					#association_class_name.hide()
					#text_enum_suggestion.show()
					#le_prop_name.show()
				#LINK_TYPE.LINK_HELPER:
					#association_class_name.hide()
					#text_enum_suggestion.hide()
					#le_prop_name.hide()
				#_:
					#push_error("Invalid index %s mapper_graph_edit.gd in 521." % index)
		#)
		#
		#association_class_name.text_changed.connect(func(new_text: String):
			#if new_text.countn(le_prop_name.text) > 0 or \
			#le_prop_name.text.countn(new_text) > 0 or \
			#new_text.to_snake_case().begins_with(le_prop_name.text) or \
			#le_prop_name.text.begins_with(new_text.to_snake_case()):
				#le_prop_name.text = new_text.to_snake_case()
		#)
		#
		#var datas = (graph_node.datas as Array).duplicate()
		#datas.push_front([null, null, ob_link_type, association_class_name, 
			#text_enum_suggestion, le_prop_name])
		#graph_node.datas = datas
		#graph_node.set_meta("extra_enabled", true)
		#update_slot_status(graph_node)
		
	#if not alreay:
		#graph_node.set_deferred("size", Vector2(graph_node.size.x + 200, graph_node.size.y))
	
	mark_modified()
	
func _on_disconnection_request(from_node: StringName, from_port: int,
to_node: StringName, to_port: int, _asize = null, _by_mouse = true) -> void:
	disconnect_node(from_node, from_port, to_node, to_port)
	
	# 如果没有连入的线，则隐藏选项
	var tos = {}
	for info in get_connection_list():
		tos[info.to_node] = 1
	if not tos.has(to_node):
		#hide_extra_control(get_node(str(to_node)), asize, by_mouse)
		update_extra_controls_to_none(get_node(str(to_node)))
	else:
		update_extra_controls_to_others(get_node(str(to_node)))
		
	mark_modified()
	
func update_extra_controls_to_none(graph_node: GraphNode):
	# [null, null, ob_link_type, association_class_name, text_enum_suggestion, le_prop_name]
	var controls = graph_node.datas[0]
	var ob_link_type = controls[2]
	
	if ob_link_type.selected != 0:
		graph_node.set_meta("_last_ob_link_type_selected_id", ob_link_type.get_item_id(ob_link_type.selected))
	for i in ob_link_type.item_count:
		if ob_link_type.get_item_id(i) == LINK_TYPE.NONE:
			ob_link_type.selected = i
			ob_link_type.item_selected.emit(i)
		ob_link_type.set_item_disabled(i, i != 0)
		
func update_extra_controls_to_others(graph_node: GraphNode):
	# [null, null, ob_link_type, association_class_name, text_enum_suggestion, le_prop_name]
	var controls = graph_node.datas[0]
	var ob_link_type = controls[2]
	
	if ob_link_type.selected == 0:
		for i in ob_link_type.item_count:
			if ob_link_type.get_item_id(i) == \
			graph_node.get_meta("_last_ob_link_type_selected_id", LINK_TYPE.ASSOCIATION):
				ob_link_type.selected = i
				ob_link_type.item_selected.emit(i)
			ob_link_type.set_item_disabled(i, i == 0)
			
#func hide_extra_control(graph_node: GraphNode, asize = null, by_mouse = true):
	#if graph_node.get_meta("extra_enabled", false):
		#if by_mouse:
			## 如果立即更新，就会由于graph_node高度产生变化，让鼠标直接连接到了下一个接口上，
			## 所以等鼠标离得远一些再更新，或者10秒后再更新
			#var mouse_pos = get_global_mouse_position()
			#var time = Time.get_ticks_msec()
			#while get_global_mouse_position().distance_squared_to(mouse_pos) < 400 \
			#and Time.get_ticks_msec() - time < 10_000:
				#await get_tree().process_frame
		## 在鼠标以比较快的速度连到下方的接口时，又拉开，可能导致删除了多次控件，检查一下
		#if not (graph_node.datas[0].size() == 6 and graph_node.datas[0][0] == null \
		#and graph_node.datas[0][1] == null):
			#return
		#var datas = (graph_node.datas as Array).duplicate()
		#var extra_controls = datas.pop_front()
		#graph_node.datas = datas
		#graph_node.set_meta("extra_controls", extra_controls)
		#graph_node.set_meta("extra_enabled", false)
		## shrink
		#if asize:
			#graph_node.set_deferred("size", Vector2(asize.x, 0))
		#else:
			#graph_node.set_deferred("size", Vector2(graph_node.size.x, 0))
		#update_slot_status(graph_node)
		
func _on_copy_nodes_request(p_copied_data = null) -> void:
	var selected_nodes_params = get_nodes_params(true)
	if selected_nodes_params.is_empty():
		return
	if p_copied_data == null:
		copied_nodes = {
			"nodes": selected_nodes_params,
			"connections": get_connection_params(true),
			"include_files": get_inlcude_params(true),
		}
	else:
		p_copied_data["nodes"] = selected_nodes_params
		p_copied_data["connections"] = get_connection_params(true)
		p_copied_data["include_files"] = get_inlcude_params(true)
		
func _on_paste_nodes_request(p_copied_data = null) -> void:
	if p_copied_data == null:
		if copied_nodes.is_empty():
			return
		_load_nodes(copied_nodes.nodes, copied_nodes.connections, Vector2(40, 40) * copied_nodes.nodes.size(), true, true)
		for i in copied_nodes.nodes:
			copied_nodes.nodes[i].position_offset += Vector2(40, 40) * copied_nodes.nodes.size()
	else:
		_load_nodes(p_copied_data.nodes, p_copied_data.connections, Vector2(40, 40) * p_copied_data.nodes.size(), true, true)
		for i in p_copied_data.nodes:
			p_copied_data.nodes[i].position_offset += Vector2(40, 40) * p_copied_data.nodes.size()
			
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
		
	if not event is InputEventKey:
		return
		
	var k = event as InputEventKey
	if not k.is_pressed():
		return
		
	if not get_viewport().gui_get_focus_owner():
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
