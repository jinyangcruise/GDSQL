@tool
extends VSplitContainer

const DATA_EXTENSION = ".gsql"

var mgr: GDSQLWorkbenchManagerClass = Engine.get_singleton("GDSQLWorkbenchManager")

signal request_open_file(path: String)
signal change_tab_title(page: Control, title: String)

@onready var _graph_edit: GraphEdit = $VBoxContainer/GraphEdit
@onready var button_commit: Button = $VBoxContainer/HFlowContainer/ButtonCommit
@onready var button_rollback: Button = $VBoxContainer/HFlowContainer/ButtonRollback
@onready var button_auto_commit: Button = $VBoxContainer/HFlowContainer/ButtonAutoCommit

var SQLGraphNode = preload("res://addons/gdsql/tabs/sql_graph_node/graph_node.tscn")

const SB_PANEL = preload("res://addons/gdsql/tabs/sql_graph_node/sb_panel.stylebox")
const SB_PANEL_SELECTED = preload("res://addons/gdsql/tabs/sql_graph_node/sb_panel_selected.stylebox")
const SB_SELECT_TITLEBAR = preload("res://addons/gdsql/tabs/sql_graph_node/sb_select_titlebar.stylebox")
const SB_SELECT_TITLEBAR_SELECTED = preload("res://addons/gdsql/tabs/sql_graph_node/sb_select_titlebar_selected.stylebox")
const SB_DELETE_TITLEBAR = preload("res://addons/gdsql/tabs/sql_graph_node/sb_delete_titlebar.stylebox")
const SB_DELETE_TITLEBAR_SELECTED = preload("res://addons/gdsql/tabs/sql_graph_node/sb_delete_titlebar_selected.stylebox")
const SB_INSERT_TITLEBAR = preload("res://addons/gdsql/tabs/sql_graph_node/sb_insert_titlebar.stylebox")
const SB_INSERT_TITLEBAR_SELECTED = preload("res://addons/gdsql/tabs/sql_graph_node/sb_insert_titlebar_selected.stylebox")
const SB_LEFT_JOIN_TITLEBAR = preload("res://addons/gdsql/tabs/sql_graph_node/sb_left_join_titlebar.stylebox")
const SB_LEFT_JOIN_TITLEBAR_SELECTED = preload("res://addons/gdsql/tabs/sql_graph_node/sb_left_join_titlebar_selected.stylebox")
const SB_UPDATE_TITLEBAR = preload("res://addons/gdsql/tabs/sql_graph_node/sb_update_titlebar.stylebox")
const SB_UPDATE_TITLEBAR_SELECTED = preload("res://addons/gdsql/tabs/sql_graph_node/sb_update_titlebar_selected.stylebox")
const SB_RESULT_TITLEBAR = preload("res://addons/gdsql/tabs/sql_graph_node/sb_result_titlebar.stylebox")
const SB_RESULT_TITLEBAR_SELECTED = preload("res://addons/gdsql/tabs/sql_graph_node/sb_result_titlebar_selected.stylebox")
const SB_SQL_TITLEBAR = preload("res://addons/gdsql/tabs/sql_graph_node/sb_sql_titlebar.stylebox")
const SB_SQL_TITLEBAR_SELECTED = preload("res://addons/gdsql/tabs/sql_graph_node/sb_sql_titlebar_selected.stylebox")

static var copied_nodes: Dictionary

const SHORTCUT_SELECTALL = preload("res://addons/gdsql/tabs/sql_graph_node/shortcut_selectall.tres")
const SHORTCUT_UNDO = preload("res://addons/gdsql/tabs/sql_graph_node/shortcut_undo.tres")
const SHORTCUT_QUERY = preload("res://addons/gdsql/tabs/sql_graph_node/shortcut_query.tres")

var graph_edit: GraphEdit:
	get:
		return _graph_edit
		
func _ready() -> void:
	button_commit.disabled = button_auto_commit.button_pressed
	button_rollback.disabled = button_auto_commit.button_pressed
	
	
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
			
func _on_button_auto_commit_toggled(button_pressed: bool) -> void:
	button_commit.disabled = button_pressed
	button_rollback.disabled = button_pressed
	
	
func _on_button_open_pressed() -> void:
	var editor_file_dialog = EditorFileDialog.new()
	editor_file_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	editor_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	editor_file_dialog.add_filter("*.gdsqlgraph", "GDSQL Graph File")
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
		var config = ImprovedConfigFile.new()
		config.set_value("data", "nodes", get_nodes_params())
		config.set_value("data", "connections", graph_edit.get_connection_list().map(func(v):
			v["from_node"] = v["from_node"].validate_node_name()
			v["to_node"] = v["to_node"].validate_node_name()
			return v
		))
		
		# 防止报错导致丢失文件中的旧数据
		if config.get_value("data", "nodes", null) == null or\
			config.get_value("data", "connections", null) == null:
			return
			
		config.save(get_meta("file_path"))
		change_tab_title.emit(self, get_meta("file_name"))
		return
		
	_on_button_save_as_pressed()

func _on_button_save_as_pressed():
	var editor_file_dialog = EditorFileDialog.new()
	editor_file_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	editor_file_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	editor_file_dialog.add_filter("*.gdsqlgraph", "GDSQL GRAPH File")
	editor_file_dialog.file_selected.connect(func(path: String):
		var config = ImprovedConfigFile.new()
		config.set_value("data", "nodes", get_nodes_params())
		config.set_value("data", "connections", graph_edit.get_connection_list().map(func(v):
			v["from_node"] = v["from_node"].validate_node_name()
			v["to_node"] = v["to_node"].validate_node_name()
			return v
		))
		
		# 防止报错导致丢失文件中的旧数据
		if config.get_value("data", "nodes", null) == null or\
			config.get_value("data", "connections", null) == null:
			return
			
		config.save(path)
		var file_name = path.get_file()
		change_tab_title.emit(self, file_name)
		set_meta("type", "sql_graph")
		set_meta("is_file", true)
		set_meta("file_path", path)
		set_meta("file_name", file_name)
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
			#var from_node = graph_edit.get_node(str(info["from_node"]))
			graph_edit.disconnect_node(info["from_node"], info["from_port"], info["to_node"], info["to_port"])
			#godot团队移出了show_close属性
			#if not from_node.show_close:
				## 清空一些数据代理
				#if from_node.has_meta("base_dao"):
					#(from_node.get_meta("base_dao") as BaseDao).reset(true)
					#from_node.remove_meta("base_dao")
				#if from_node.has_meta("left_join"):
					#(from_node.get_meta("left_join") as LeftJoin).clear_chain()
					#from_node.remove_meta("left_join")
				#from_node.queue_free()
		# 表示node是输入节点
		elif node.name == info["from_node"]:
			graph_edit.disconnect_node(info["from_node"], info["from_port"], info["to_node"], info["to_port"])
			
		# 删除BaseDao和LeftJoin数据关联
		var f_node = graph_edit.get_node(str(info.from_node))
		var t_node = graph_edit.get_node(str(info.to_node))
		# select 连 select（即union all）
		match f_node.get_meta("type"):
			"Select":
				match t_node.get_meta("type"):
					"Select":
						(t_node.get_meta("base_dao") as BaseDao).remove_union_all(f_node.get_meta("base_dao") as BaseDao)
					"Result":
						# 如果有修改数据的按钮，需要屏蔽
						var graph_datas = t_node.datas
						if graph_datas.size() > 1:
							#┖╴@HBoxContainer                  get_child(-2)
								#┖╴@HFlowContainer             get_child(0)
									#┠╴@Button
									#┠╴@Button
									#┖╴@Button
							var flow_container = t_node.get_child(-2).get_child(0)
							for i in flow_container.get_children():
								i.disabled = true
							var table = graph_datas[0][0].get_child(0)
							for i in table.datas:
								(i as DictionaryObject).reset_read_only(true)
			"Left Join":
				match t_node.get_meta("type"):
					"Select":
						(t_node.get_meta("base_dao") as BaseDao).remove_left_join(f_node.get_meta("left_join") as LeftJoin)
					"Left Join":
						(t_node.get_meta("left_join") as LeftJoin).remove_left_join((f_node.get_meta("left_join") as LeftJoin))
						
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
	graph_node.position_offset = \
		(graph_edit.get_rect().get_center() - graph_node.get_rect().size/2 + graph_edit.scroll_offset) / graph_edit.zoom
		
	mark_modified()
	
func _on_button_add_node_left_join_pressed():
	graph_edit.grab_focus() # 激活绘图板的快捷键，比如delte， ctrl+C/V
	unselect_all_node()
	
	var graph_node = gen_left_join_node()
	graph_edit.add_child(graph_node)
	graph_node.position_offset = \
		(graph_edit.get_rect().get_center() - graph_node.get_rect().size/2 + graph_edit.scroll_offset) / graph_edit.zoom
		
	mark_modified()
		
func _on_button_add_node_insert_pressed():
	graph_edit.grab_focus() # 激活绘图板的快捷键，比如delte， ctrl+C/V
	unselect_all_node()
	
	var graph_node = gen_insert_node()
	graph_edit.add_child(graph_node)
	graph_node.position_offset = \
		(graph_edit.get_rect().get_center() - graph_node.get_rect().size/2 + graph_edit.scroll_offset) / graph_edit.zoom
		
	mark_modified()

func _on_button_add_node_update_pressed():
	graph_edit.grab_focus() # 激活绘图板的快捷键，比如delte， ctrl+C/V
	unselect_all_node()
	
	var graph_node = gen_update_node()
	graph_edit.add_child(graph_node)
	graph_node.position_offset = \
		(graph_edit.get_rect().get_center() - graph_node.get_rect().size/2 + graph_edit.scroll_offset) / graph_edit.zoom
		
	mark_modified()

func _on_button_add_node_delete_pressed():
	graph_edit.grab_focus() # 激活绘图板的快捷键，比如delte， ctrl+C/V
	unselect_all_node()
	
	var graph_node = gen_delete_node()
	graph_edit.add_child(graph_node)
	graph_node.position_offset = \
		(graph_edit.get_rect().get_center() - graph_node.get_rect().size/2 + graph_edit.scroll_offset) / graph_edit.zoom
		
	mark_modified()
	
func _on_button_add_node_sql_pressed():
	graph_edit.grab_focus() # 激活绘图板的快捷键，比如delte， ctrl+C/V
	unselect_all_node()
	
	var graph_node = gen_sql_node()
	graph_edit.add_child(graph_node)
	graph_node.position_offset = \
		(graph_edit.get_rect().get_center() - graph_node.get_rect().size/2 + graph_edit.scroll_offset) / graph_edit.zoom
		
	mark_modified()
	
func _on_button_add_node_link_pressed():
	graph_edit.grab_focus() # 激活绘图板的快捷键，比如delte， ctrl+C/V
	unselect_all_node()
	
	var graph_node = gen_link_node()
	graph_edit.add_child(graph_node)
	graph_node.position_offset = \
		(graph_edit.get_rect().get_center() - graph_node.get_rect().size/2 + graph_edit.scroll_offset) / graph_edit.zoom
		
	mark_modified()
	
func add_select_node(schema = "", table = "", fields = "*", where = "", group_by = "", order_by = "", offset = 0, 
limit = 100, alias = "", password = "", asize = null, pos_offset = null, aname = "", query = true):
	graph_edit.grab_focus() # 激活绘图板的快捷键，比如delte， ctrl+C/V
	unselect_all_node()
	
	var graph_node = gen_select_node()
	if aname != "":
		graph_node.name = aname
	graph_edit.add_child(graph_node)
	
	# 等待页面就绪
	if not graph_edit.get_rect().has_area():
		await graph_edit.resized
		
	if pos_offset == null:
		graph_node.position_offset = \
			(graph_edit.get_rect().get_center() - graph_node.get_rect().size/2 + graph_edit.scroll_offset) / graph_edit.zoom
	else:
		graph_node.position_offset = pos_offset
		
	if asize != null:
		graph_node.set_deferred("size", asize)
	
	var schema_dict_obj: DictionaryObject = graph_node.datas[2][2]
	var table_dict_obj: DictionaryObject = graph_node.datas[3][2]
	var fields_dict_obj: DictionaryObject = graph_node.datas[4][2]
	var where_dict_obj: DictionaryObject = graph_node.datas[5][2]
	var groupby_dict_obj: DictionaryObject = graph_node.datas[6][2]
	var order_dict_obj: DictionaryObject = graph_node.datas[7][2]
	var limit_dict_obj: DictionaryObject = graph_node.datas[8][2]
	#var separetor: Control = graph_node.datas[9][2]
	var btn_query: Button = graph_node.datas[10][2]
	
	if schema != schema_dict_obj._get("Schema"):
		schema_dict_obj._set("Schema", schema)
	if password != schema_dict_obj._get("_password"):
		schema_dict_obj._set("_password", password)
	if table != table_dict_obj._get("Table"):
		table_dict_obj._set("Table", table)
	if alias != table_dict_obj._get("_alias"):
		table_dict_obj._set("_alias", alias)
	if fields != fields_dict_obj._get("Fields"):
		fields_dict_obj._set("Fields", fields)
	if where != where_dict_obj._get("Where"):
		where_dict_obj._set("Where", where)
	if group_by != groupby_dict_obj._get("Group By"):
		groupby_dict_obj._set("Group By", group_by)
	if order_by != order_dict_obj._get("Order By"):
		order_dict_obj._set("Order By", order_by)
	if limit != limit_dict_obj._get("Offset"):
		limit_dict_obj._set("Offset", offset)
	if offset != limit_dict_obj._get("Limit"):
		limit_dict_obj._set("Limit", limit)
		
	if query:
		btn_query.emit_signal("pressed")
		
	return graph_node
	
func gen_select_node() -> GraphNode:
	var databases = mgr.databases.keys()
	
	var schema_dict_obj = DictionaryObject.new(
		{"Schema": "", "_password": ""}, 
		{"Schema": {"hint": PROPERTY_HINT_ENUM, "hint_string": ",".join(databases)}, 
		"_password": {"hint": PROPERTY_HINT_PASSWORD, "hint_string": "password"}})
	var table_dict_obj = DictionaryObject.new(
		{"Table": "", "_alias": ""}, 
		{"Table": {"hint": PROPERTY_HINT_ENUM, "hint_string": ""}, 
		"_alias": {"hint": PROPERTY_HINT_PLACEHOLDER_TEXT, "hint_string": "alias"}})
	var fields_dict_obj = DictionaryObject.new({"Fields": "*"}, {"Fields": {"hint": PROPERTY_HINT_MULTILINE_TEXT}})
	var where_dict_obj = DictionaryObject.new({"Where": ""}, {"Where": {"hint": PROPERTY_HINT_MULTILINE_TEXT}})
	var groupby_dict_obj = DictionaryObject.new({"Group By": ""})
	var order_dict_obj = DictionaryObject.new({"Order By": ""})
	var limit_dict_obj = DictionaryObject.new({"Offset": 0, "Limit": 100})
	
	# 关联该节点的BaseDao
	var base_dao = BaseDao.new()
	base_dao.select("*", true)
	base_dao.limit(0, 100)
	
	var graph_node = SQLGraphNode.instantiate()
	graph_node.set_meta("base_dao", base_dao)
	graph_node.node_enable_status.connect(mark_modified)
	
	# 根据选择的数据库来更新表名备选项
	schema_dict_obj.value_changed.connect(func(prop, new_val, _old_val):
		graph_node.push_redraw_slot_control(2, 2) # 如果不是通过点击的控件修改的dict obj，就需要重绘一下。这里偷个懒，直接重绘。
		match prop:
			"Schema":
				base_dao.use_db(mgr.databases[new_val]["data_path"])
				var tables = mgr.databases[new_val]["tables"].keys()
				table_dict_obj.reset_hint(
					{"Table": {"hint": PROPERTY_HINT_ENUM, "hint_string": ",".join(tables)}, 
					"_alias": {"hint": PROPERTY_HINT_PLACEHOLDER_TEXT, "hint_string": "alias"}})
				table_dict_obj._set("Table", "", true) # 强制设置（可以避免值没变化导致没有发出信号）
			"_password":
				base_dao.set_password(new_val)
	)
	table_dict_obj.value_changed.connect(func(prop, new_val, _old_val):
		graph_node.push_redraw_slot_control(3, 2)
		match prop:
			"Table":
				base_dao.set_table(new_val + DATA_EXTENSION)
			"_alias":
				base_dao.set_table_alias(new_val)
	)
	fields_dict_obj.value_changed.connect(func(prop, new_val, _old_val):
		graph_node.push_redraw_slot_control(4, 2)
		match prop:
			"Fields":
				base_dao.select(new_val, true)
	)
	where_dict_obj.value_changed.connect(func(prop, new_val, _old_val):
		graph_node.push_redraw_slot_control(5, 2)
		match prop:
			"Where":
				base_dao.set_where(new_val)
	)
	groupby_dict_obj.value_changed.connect(func(prop, new_val, _old_val):
		graph_node.push_redraw_slot_control(6, 2)
		match prop:
			"Group By":
				base_dao.group_by_str(new_val)
	)
	order_dict_obj.value_changed.connect(func(prop, new_val, _old_val):
		graph_node.push_redraw_slot_control(7, 2)
		match prop:
			"Order By":
				base_dao.order_by_str(new_val)
	)
	limit_dict_obj.value_changed.connect(func(prop, new_val, _old_val):
		graph_node.push_redraw_slot_control(8, 2)
		match prop:
			"Offset":
				base_dao.limit(new_val, limit_dict_obj._get("Limit"))
			"Limit":
				base_dao.limit(limit_dict_obj._get("Offset"), new_val)
	)
	
	var btn_query = Button.new()
	btn_query.text = "query"
	btn_query.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_query.pressed.connect(on_select_node_query.bind(graph_node, true))
	btn_query.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	
	var separator = Control.new()
	separator.custom_minimum_size.y = 10
	var separator2 = Control.new()
	separator2.custom_minimum_size.y = 10
	
	var datas: Array[Array] = [
		["Union All", "Result"],
		["Left Join", null],
		[null, null, schema_dict_obj],
		[null, null, table_dict_obj],
		[null, null, fields_dict_obj],
		[null, null, where_dict_obj],
		[null, null, groupby_dict_obj],
		[null, null, order_dict_obj],
		[null, null, limit_dict_obj],
		[null, null, separator],
		[null, null, btn_query],
		[null, null, separator2]
	]
	graph_node.datas = datas
	graph_node.title = "Select"
	graph_node.add_theme_stylebox_override("panel", SB_PANEL)
	graph_node.add_theme_stylebox_override("panel_selected", SB_PANEL_SELECTED)
	graph_node.add_theme_stylebox_override("titlebar", SB_SELECT_TITLEBAR)
	graph_node.add_theme_stylebox_override("titlebar_selected", SB_SELECT_TITLEBAR_SELECTED)
	graph_node.ready.connect(func():
		graph_node.set_slot_type_left(0, 0) # Union All's type is 0
		graph_node.set_slot_type_left(1, 1) # Left Join's type is 1
		graph_node.set_slot_type_right(0, 0) # Result's type is 0
		graph_node.size.x = 650
		graph_node.selected = true
	)
	graph_node.set_meta("type", "Select")
	graph_node.set_meta("node", true)
	graph_node.delete_request.connect(func():
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
	
func add_left_join_node(schema = "", password = "", table = "", alias = "", 
cond = "", asize = null, pos_offset = null, aname = ""):
	graph_edit.grab_focus() # 激活绘图板的快捷键，比如delte， ctrl+C/V
	unselect_all_node()
	
	var graph_node = gen_left_join_node()
	if aname != "":
		graph_node.name = aname
	graph_edit.add_child(graph_node)
	
	# 等待页面就绪
	if not graph_edit.get_rect().has_area():
		await graph_edit.resized
		
	if pos_offset == null:
		graph_node.position_offset = \
			(graph_edit.get_rect().get_center() - graph_node.get_rect().size/2 + graph_edit.scroll_offset) / graph_edit.zoom
	else:
		graph_node.position_offset = pos_offset
		
	if asize != null:
		graph_node.set_deferred("size", asize)
	
	var schema_dict_obj: DictionaryObject = graph_node.datas[1][2]
	var table_dict_obj: DictionaryObject = graph_node.datas[2][2]
	var cond_dict_obj: DictionaryObject = graph_node.datas[3][2]
	
	if schema != schema_dict_obj._get("Schema"):
		schema_dict_obj._set("Schema", schema)
	if password != schema_dict_obj._get("_password"):
		schema_dict_obj._set("_password", password)
	if table != table_dict_obj._get("Table"):
		table_dict_obj._set("Table", table)
	if alias != table_dict_obj._get("_alias"):
		table_dict_obj._set("_alias", alias)
	if cond != cond_dict_obj._get("On"):
		cond_dict_obj._set("On", cond)
		
	return graph_node
	
func gen_left_join_node() -> GraphNode:
	var databases = mgr.databases.keys()
	
	var schema_dict_obj = DictionaryObject.new(
		{"Schema": "", "_password": ""}, 
		{"Schema": {"hint": PROPERTY_HINT_ENUM, "hint_string": ",".join(databases)}, 
		"_password": {"hint": PROPERTY_HINT_PASSWORD, "hint_string": "password"}})
	var table_dict_obj = DictionaryObject.new(
		{"Table": "", "_alias": ""}, 
		{"Table": {"hint": PROPERTY_HINT_ENUM, "hint_string": ""}, 
		"_alias": {"hint": PROPERTY_HINT_PLACEHOLDER_TEXT, "hint_string": "alias"}})
	var cond_dict_obj = DictionaryObject.new({"On": ""}, {"On": {"hint": PROPERTY_HINT_MULTILINE_TEXT}})
	
	# 与该节点关联的LeftJoin对象
	var left_join_obj = LeftJoin.new()
	
	var graph_node = SQLGraphNode.instantiate()
	graph_node.set_meta("left_join", left_join_obj)
	graph_node.node_enable_status.connect(mark_modified)
	
	# 根据选择的数据库来更新表名备选项
	schema_dict_obj.value_changed.connect(func(prop, new_val, _old_val):
		graph_node.push_redraw_slot_control(1, 2)
		match prop:
			"Schema":
				left_join_obj.set_db(mgr.databases[new_val]["data_path"])
				var tables = mgr.databases[new_val]["tables"].keys()
				table_dict_obj.reset_hint(
					{"Table": {"hint": PROPERTY_HINT_ENUM, "hint_string": ",".join(tables)}, 
					"_alias": {"hint": PROPERTY_HINT_PLACEHOLDER_TEXT, "hint_string": "alias"}})
				table_dict_obj._set("Table", "", true)
			"_password":
				left_join_obj.set_password(new_val)
	)
	table_dict_obj.value_changed.connect(func(prop, new_val, _old_val):
		graph_node.push_redraw_slot_control(2, 2) # table是第3行第3个控件。
		match prop:
			"Table":
				left_join_obj.set_table(new_val + DATA_EXTENSION)
			"_alias":
				left_join_obj.set_alias(new_val)
	)
	cond_dict_obj.value_changed.connect(func(prop, new_val, _old_val):
		graph_node.push_redraw_slot_control(3, 2)
		match prop:
			"On":
				left_join_obj.set_condition(new_val)
	)
	
	var separator = Control.new()
	separator.custom_minimum_size.y = 20
	
	var datas: Array[Array] = [
		["Next Left Join", "Result"],
		[null, null, schema_dict_obj],
		[null, null, table_dict_obj],
		[null, null, cond_dict_obj],
		[null, null, separator]
	]
	graph_node.datas = datas
	graph_node.title = "Left Join"
	graph_node.add_theme_stylebox_override("panel", SB_PANEL)
	graph_node.add_theme_stylebox_override("panel_selected", SB_PANEL_SELECTED)
	graph_node.add_theme_stylebox_override("titlebar", SB_LEFT_JOIN_TITLEBAR)
	graph_node.add_theme_stylebox_override("titlebar_selected", SB_LEFT_JOIN_TITLEBAR_SELECTED)
	graph_node.ready.connect(func():
		graph_node.set_slot_type_left(0, 1) # Next Left Join's type is 1
		graph_node.set_slot_type_right(0, 1) # Result's type is 1
		graph_node.size.x = 650
		graph_node.selected = true
	)
	graph_node.set_meta("type", "Left Join")
	graph_node.set_meta("node", true)
	graph_node.delete_request.connect(func():
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
	
func add_table_node(columns: Array, table_datas: Array, is_union_all: bool, join_conds: Array, v_scroll_h: int, asize = null, pos_offset = null, aname = ""):
	graph_edit.grab_focus() # 激活绘图板的快捷键，比如delte， ctrl+C/V
	unselect_all_node()
	
	var graph_node = gen_table_node(columns, table_datas, is_union_all, join_conds, v_scroll_h)
	if aname != "":
		graph_node.name = aname
	graph_edit.add_child(graph_node)
	
	# 等待页面就绪
	if not graph_edit.get_rect().has_area():
		await graph_edit.resized
		
	if pos_offset == null:
		graph_node.position_offset = \
			(graph_edit.get_rect().get_center() - graph_node.get_rect().size/2 + graph_edit.scroll_offset) / graph_edit.zoom
	else:
		graph_node.position_offset = pos_offset
		
	if asize != null:
		graph_node.set_deferred("size", asize)
		
	return graph_node
	
	
## 生成一个【表格】节点
func gen_table_node(columns: Array, table_datas: Array, is_union_all: bool, join_conds: Array, v_scroll_h: int = 0, old_graph_node: GraphNode = null) -> GraphNode:
#region 每列的属性名称要重新定义
	var single_table_query = join_conds.is_empty() # 是否为单表查询
	var hint = {} # 每列的hint
	var map_table_path_index = {} # 临时变量：记录每个表分组的序号
	var last_table_path = "" # 临时变量：记录上一列的表路径
	var last_prefix = "" # 临时变量：记录上一列使用的名称前缀
	var dealed_columns = {} # 临时变量：记录已经处理过的真实列名
	var real_col_name_name = {} # 临时变量：记录列名对应的真实列名
	var new_column_prop_name = [] # 保存包含用于分组的属性和数据列的所有属性
	var table_primary_index = {} # 保存每个表的主键在new_column_prop_name中的序号
	var table_col_index = {} # 保存每个表的键在new_column_prop_name中的序号
	var table_alias_fields = {} # 临时变量：记录所有的t.xxx及其第一次出现时的序号（序号是columns中的序号）
	var uneditable_index = [] # 保存不能被编辑的列序号（假设值不是null）（序号是columns中的序号）
	
	# 联表查询不能修改主键和关联字段，找到这些字段
	if not single_table_query:
		for i in columns.size():
			if columns[i]["is_field"]:
				var ta = columns[i]["table_alias"] + "." + columns[i]["Column Name"]
				if not table_alias_fields.has(ta): # 重复的不记录是因为重复的本来就不可编辑
					table_alias_fields[ta] = i
				if columns[i]["PK"]:
					uneditable_index.push_back(i) # 不考虑用户select重复的主键了，不影响效果
					
		# 找到join_conds中的t.xxx
		var regex_field = RegEx.new()
		regex_field.compile("([a-zA-Z_]+[0-9a-zA-Z_]*\\.[a-zA-Z_]+[0-9a-zA-Z_]*)")
		for i in join_conds:
			var matches = regex_field.search_all(i)
			for a_match in matches:
				var s = a_match.get_string(0)
				if not s.is_empty() and table_alias_fields.has(s):
					uneditable_index.push_back(table_alias_fields[s]) # 就不去重了，不影响效果
					
	for j in columns.size():
		var table_path
		# 表中的字段
		if columns[j]["is_field"]:
			table_path = columns[j]["db_name"] + " " + columns[j]["table_name"].get_basename() # 实际上用的是数据库名称（而不是路径）+表名（去后缀）
			if not table_primary_index.has(columns[j]["db_path"] + columns[j]["table_name"]): # 这里用的是数据库的路径+表名
				table_primary_index[columns[j]["db_path"] + columns[j]["table_name"]] = -1
		else:
			table_path = "ComputingData"
			
		# 分组名称
		var prefix
		if table_path == last_table_path:
			prefix = last_prefix
		else:
			prefix = table_path
			if map_table_path_index.has(table_path):
				prefix += "@" + str(map_table_path_index[table_path])
				map_table_path_index[table_path] += 1
			else:
				map_table_path_index[table_path] = 2 # 可以使未来重复的分组名称后缀从2开始命名
			new_column_prop_name.push_back({"type": "group", "prop": prefix})
			hint[prefix] = {"hint_string": prefix + " ", "usage": PROPERTY_USAGE_GROUP} # 如此，检查器就可以省略属性的prefix
			
		last_table_path = table_path
		last_prefix = prefix
		
		# 属性名称
		var real_column_name = table_path + " " + columns[j]["Column Name"]
		if dealed_columns.has(real_column_name):
			var col_name = prefix + " " + columns[j]["Column Name"] + " (Copy" + str(dealed_columns[real_column_name]) + ")"
			new_column_prop_name.push_back({"type": j, "prop": col_name, "col_name": columns[j]["Column Name"],
				"table_path": columns[j]["db_path"] + columns[j]["table_name"]}) # 记录j列数据的属性名称等信息
			hint[col_name] = {"link": real_col_name_name[real_column_name]}
			dealed_columns[real_column_name] += 1
		else:
			var col_name = prefix + " " + columns[j]["Column Name"]
			new_column_prop_name.push_back({"type": j, "prop": col_name, "col_name": columns[j]["Column Name"],
				"table_path": columns[j]["db_path"] + columns[j]["table_name"]}) # 记录j列数据的属性名称等信息
			if columns[j]["is_field"]:
				hint[col_name] = {"hint": columns[j]["Hint"], 
					"hint_string": columns[j]["Hint String"], "type": columns[j]["Data Type"]}
				# 记录键位置信息
				table_col_index[col_name] = new_column_prop_name.size() - 1
				# 记录主键信息
				if columns[j]["PK"]:
					table_primary_index[columns[j]["db_path"] + columns[j]["table_name"]] = table_col_index[col_name] # 主键位置
			else:
				hint[col_name] = {"usage": PROPERTY_USAGE_READ_ONLY | PROPERTY_USAGE_EDITOR}
			real_col_name_name[real_column_name] = col_name
			dealed_columns[real_column_name] = 2 # 可以使未来重复的变量名称后缀从2开始命名
#endregion
			
#region table graph node UI
	var graph_node = old_graph_node
	var table
	var graph_datas: Array[Array]
	if graph_node == null:
		graph_node = SQLGraphNode.instantiate()
		graph_node.node_enable_status.connect(mark_modified)
	
		var margin_container = MarginContainer.new()
		margin_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		margin_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
		margin_container.add_theme_constant_override("margin_top", 10)
		margin_container.add_theme_constant_override("margin_bottom", 10)
		table = preload("res://addons/gdsql/table.tscn").instantiate()
		table.show_frame = true
		table.size_flags_vertical = Control.SIZE_EXPAND_FILL
		margin_container.add_child(table)
		table.set_meta("columns", columns)
		table.column_tips = columns.map(func(v): 
			return type_string(v["Data Type"]) if v.has("Data Type") else "")
		table.columns = columns.map(func(v): return v["field_as"])
		
		var flow_container = HFlowContainer.new()
		flow_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		flow_container.alignment = FlowContainer.ALIGNMENT_END
		flow_container.ready.connect(func():
			flow_container.get_parent_control().size_flags_vertical = Control.SIZE_FILL
		, CONNECT_ONE_SHOT)
		
		var btn_export = Button.new()
		btn_export.text = "export"
		btn_export.pressed.connect(func():
			var _columns = table.get_meta("columns")
			mgr.open_select_data_export_tab.emit(_columns, table.datas.map(extract_table_data_call.bind(_columns)))
		)
		flow_container.add_child(btn_export)
		
		var separator = Control.new()
		separator.custom_minimum_size.y = 80
		
		graph_datas = [
			[margin_container, null],
			[null, null, flow_container], # buttons
			[null, null, separator], # separetor
		]
		
		graph_node.title = "Result"
		graph_node.add_theme_stylebox_override("panel", SB_PANEL)
		graph_node.add_theme_stylebox_override("panel_selected", SB_PANEL_SELECTED)
		graph_node.add_theme_stylebox_override("titlebar", SB_RESULT_TITLEBAR)
		graph_node.add_theme_stylebox_override("titlebar_selected", SB_RESULT_TITLEBAR_SELECTED)
		graph_node.ready.connect(func():
			graph_node.set_slot_type_left(0, 1) # Result's type is 1
			graph_node.size = Vector2(500, 600)
			#graph_node.selected = true
		)
		graph_node.set_meta("type", "Result")
		graph_node.set_meta("node", true)
		graph_node.delete_request.connect(node_close.bind(graph_node)) # 关闭事件
	else:
		#graph_node.selected = true
		graph_datas = graph_node.datas
		table = graph_datas[0][0].get_child(0) # [0][0]是margin_container
		table.set_meta("columns", columns)
		table.column_tips = columns.map(func(v): 
			return type_string(v["Data Type"]) if v.has("Data Type") else "")
		table.columns = columns.map(func(v): return v["field_as"])
		table.size_flags_vertical = Control.SIZE_EXPAND_FILL
		# 除了最后一个导出按钮，其他按钮删除
		var flow_container: HFlowContainer = graph_datas[1][2]
		while flow_container.get_child_count() > 1:
			var child = flow_container.get_child(0)
			flow_container.remove_child(child)
			child.queue_free()
		for i in table.row_deleted.get_connections():
			# 由于按钮释放了，原来connect的引用的按钮无法再使用，disconnect掉，后面会重新连接
			table.row_deleted.disconnect(i["callable"])
#endregion
			
	# 非unionall就可以编辑。
	graph_node.set_meta("is_union_all", is_union_all)
	graph_node.set_meta("join_conds", join_conds)
	table.editable = not is_union_all
	table.show_menu = true
	table.support_multi_rows_selected = true # 支持批量操作
	# 只有单表查询才支持右键删除。联表查询无法知道用户想删除哪个表的数据，即便能勾选要执行的命令，也容易误操作
	table.support_delete_row = single_table_query
	
	if table.editable:
		# 用于把修改数据按照表路径做归类
		# return：{
			#"res://src/config/c_skill.gsql": {
				#"PK_key": "id",
				#"PK_value_new": 7,
				#"PK_value_old": 6,
				#"modified": {
					#"id": {
						#"new": 7,
						#"old": 6
					#}
				#}
			#}
		#}
		var group_modified_data_call = func(data: DictionaryObject) -> Dictionary:
			var tables = {} # 更新数据可能涉及多个表，所以把modified_data按表分类
			var modified_data = data.get_modified_value()
			var all_data = data.get_visible_data()
			for prop in all_data:
				var col_info = new_column_prop_name[table_col_index[prop]]
				var table_path = col_info["table_path"]
				if not tables.has(table_path):
					tables[table_path] = {}
					var primary_index = table_primary_index[table_path]
					var primary_key
					var primary_value_new
					var primary_value_old
					if primary_index != -1:
						var primary_info = new_column_prop_name[primary_index]
						primary_key = primary_info["col_name"]
						primary_value_new = data._get(primary_info["prop"])
						primary_value_old = primary_value_new \
							if not modified_data.has(primary_info["prop"]) \
							else modified_data[primary_info["prop"]]["old"]
					tables[table_path]["PK_key"] = primary_key
					tables[table_path]["PK_value_new"] = primary_value_new
					tables[table_path]["PK_value_old"] = primary_value_old
					tables[table_path]["modified"] = {}
					tables[table_path]["all"] = {}
				tables[table_path]["all"][col_info["col_name"]] = all_data[prop]
				if modified_data.has(prop):
					tables[table_path]["modified"][col_info["col_name"]] = modified_data[prop] # {"new":xx, "old":xx}
			return tables
			
		# 更新apply和revert两个按钮状态
		var btn_ref: Array[Button] = []
		btn_ref.resize(2)
		var update_btn_disable_status = func(_prop, _new_val, _old_val):
			# 如果有删除的行，btn_revert肯定需要激活，不用再检查表中的数据了
			if not table.get_meta("deleted_datas", {}).is_empty():
				return
				
			for j: DictionaryObject in table.datas:
				if not j.get_modified_new_value().is_empty():
					if btn_ref and btn_ref.size() == 2 and is_instance_valid(btn_ref[0]) and is_instance_valid(btn_ref[1]):
						btn_ref[0].disabled = false
						btn_ref[1].disabled = false
					return
			if btn_ref and btn_ref.size() == 2 and is_instance_valid(btn_ref[0]) and is_instance_valid(btn_ref[1]):
				btn_ref[0].disabled = true
				btn_ref[1].disabled = true
			
		# 加俩按钮:1.新建一条数据；2.应用
		var btn_apply = Button.new()
		btn_ref[0] = btn_apply
		btn_apply.text = "apply"
		btn_apply.disabled = true
		btn_apply.pressed.connect(func():
			var daos: Array[BaseDao] = []
			# 整条被删的数据。【WARNING】规定联表查询时禁止删除操作（屏蔽右键删除功能）
			var deleted_datas = table.get_meta("deleted_datas", {})
			for i in deleted_datas:
				var data: DictionaryObject = deleted_datas[i]
				var grouped_modified_data = group_modified_data_call.call(data)
				for table_path: String in grouped_modified_data:
					var base_dao = BaseDao.new()
					base_dao.use_db(table_path.get_base_dir()).delete_from(table_path.get_file())
					if grouped_modified_data[table_path]["PK_key"] == null:
						base_dao.set_meta("lackWhere", true)
					else:
						base_dao.where("%s == %s" % [grouped_modified_data[table_path]["PK_key"], 
							var_to_str(grouped_modified_data[table_path]["PK_value_old"])])
					base_dao.set_meta("dict_obj_id", data.get_instance_id())
					daos.push_back(base_dao)
					
				
			# 要更新部分字段的数据
			for i: DictionaryObject in table.datas:
				var grouped_modified_data = group_modified_data_call.call(i)
				for table_path: String in grouped_modified_data:
					var modified_data = grouped_modified_data[table_path]
					if modified_data["modified"].is_empty():
						continue
						
					var db_path = table_path.get_base_dir()
					if not db_path.ends_with("/"): db_path += "/"
					var table_name = table_path.get_file()
					# 新增（用户在联表查询结果中new新数据时，在new的这行数据中对联表旧数据进行修改的可能性不大，所以逻辑中忽略这种奇怪的操作）
					var insert_call = func():
						# 把该表设置过的所有字段取出
						var values = {}
						for col_name in modified_data["modified"]:
							values[col_name] = modified_data["modified"][col_name]["new"]
						var base_dao = BaseDao.new()
						base_dao.use_db(db_path).insert_into(table_name).values(values)
						base_dao.set_meta("dict_obj_id", i.get_instance_id())
						daos.push_back(base_dao)
						
					if i.has_meta("new"):
						# 单表查询时，由用户自己负责
						if single_table_query:
							insert_call.call()
						# 联表查询时，修改数据若包含主键，那可以先检查一下（主键）是不是在数据库已经存在，如果存在就不需要新增了。
						# 实际上，联表查询时，用户输入了主键如果在数据库里存在，则提示用户有误。如果不存在，就算新增数据。
						# 新增数据如果没有包含主键呢？可能一：主键自增，用户可以不设置；可能二：需要用户填写主键但未填，那么query时会报错。
						else:
							var primary_key = modified_data["PK_key"]
							var primary_value = modified_data["PK_value_new"]
							if primary_key != null and modified_data["modified"].has(primary_key):
								if exist_callable(db_path, table_name, primary_key, primary_value):
									continue
									
							insert_call.call()
					# 非新增，也就是更新（用户联表查询时，有产生新增数据的可能性，比如修改全为null值的表，所以要考虑这种情况）
					else:
						var primary_key = modified_data["PK_key"]
						var primary_value = modified_data["PK_value_old"]
						var update_call = func():
							var data = {}
							for key in modified_data["modified"]:
								data[key] = modified_data["modified"][key]["new"]
							var base_dao = BaseDao.new().use_db(db_path).update(table_name).sets(data)
							if primary_key == null:
								base_dao.set_meta("lackWhere", true)
							else:
								base_dao.where("%s == %s" % [primary_key, var_to_str(primary_value)])
							base_dao.set_meta("dict_obj_id", i.get_instance_id())
							daos.push_back(base_dao)
							
						# 单表查询时的所有情况
						if single_table_query:# or primary_key == null or not modified_data["modified"].has(primary_key):
							update_call.call()
						# 联表查询涉及主键修改的情况。只有一种被允许的情况，那就是该主键的旧值为null（实际上该主键所属表的其他字段都是null）。
						# 这样的话，用户修改该主键的值，只能是新建一条数据。
						# 其他情况涉及逻辑冲突，所以禁止用户在联表查询中进行修改主键和关联键的行为（通过hint的usage禁止）。
						# TODO 如果用户需要删除关联，考虑右键菜单加入删除关联。
						else:
							if primary_key == null or primary_value == null or modified_data["modified"].has(primary_key):
								insert_call.call()
							# 更新非主键字段、非关联键字段
							else:
								update_call.call()
						
			# 弹对话框让用户选择更新哪些数据
			var arr: Array[Array] = [["Please confirm:"]]
			var table_2 = preload("res://addons/gdsql/table.tscn").instantiate()
			table_2.ratios = [15.0, 0.4, 2.0, 4.0, 8.0] as Array[float]
			table_2.columns = ["#", "action", "extra info", "do", "status"]
			table_2.column_tips = ["", "", "If necessary.", "Only execute checked actions.", "Execute status."]
			var check_all_btn = CheckBox.new()
			check_all_btn.text = "Check all"
			check_all_btn.button_pressed = true
			check_all_btn.toggled.connect(func(toggled_on):
				for row in table_2.datas:
					if not (row[3] as CheckBox).disabled:
						(row[3] as CheckBox).button_pressed = toggled_on
			)
			var datas = []
			var k = 0
			for i: BaseDao in daos:
				var row = [k+1, i.get_query_cmd()]
				if i.has_meta("lackWhere"):
					var line_edit = LineEdit.new()
					line_edit.placeholder_text = "Conditions for this action if necessary."
					row.push_back(line_edit)
				else:
					row.push_back("")
					
				var cb = CheckBox.new()
				cb.button_pressed = true
				cb.set_meta("index", k)
				cb.toggled.connect(func(toggled_on):
					if toggled_on:
						for a_row in table_2.datas:
							if not (a_row[3] as CheckBox).disabled:
								if not (a_row[3] as CheckBox).button_pressed:
									check_all_btn.set_pressed_no_signal(false)
									return
						check_all_btn.set_pressed_no_signal(true)
					else:
						check_all_btn.set_pressed_no_signal(false)
				)
				row.push_back(cb)
				
				var pb = ProgressBar.new()
				row.push_back(pb)
				datas.push_back(row)
				k += 1
			table_2.datas = datas
			table_2.show_menu = true
			table_2.support_delete_row = false
			table_2.ready.connect(func():
				table_2.get_parent_control().size_flags_vertical = Control.SIZE_EXPAND_FILL
			, CONNECT_ONE_SHOT)
			arr.push_back([table_2])
			arr.push_back([check_all_btn])
			
			# 只执行用户勾选的项目。执行成功的项目标绿进度100%；执行失败的项目标红。
			# 可以多次执行，直到没有可勾选的项目。
			var dialog_ref: Array[ConfirmationDialog] = []
			var confirmed = func():
				# 该按钮名称是关闭，则直接关闭，否则执行命令
				if dialog_ref[0].ok_button_text == "close":
					# 更新按钮状态
					update_btn_disable_status.call("", 0, 0) # 随便传几个参数
					return [false, false] # 不涉及defered函数，所以第二个参数传的没什么意义
					
				# sql query
				var index = -1
				for i: BaseDao in daos:
					index += 1
					if not (table_2.datas[index][3] as CheckBox).button_pressed:
						continue
					if (table_2.datas[index][4] as ProgressBar).value == 100:
						continue
					var begin_time = Time.get_unix_time_from_system()
					var ret = i.query()
					if ret != null:
						if ret.ok():
							var dict_obj_id = i.get_meta("dict_obj_id")
							var dict_obj = instance_from_id(dict_obj_id) as DictionaryObject
							
							# remove deleted data
							if i.get_cmd().to_lower().contains("delete"):
								var key = table.get_meta("deleted_datas", {}).find_key(dict_obj)
								if key != null:
									table.get_meta("deleted_datas").erase(key)
									
							else:
								# commit data of modified row
								dict_obj.commit()
								
								# remove meta of new-created row
								if dict_obj.has_meta("new"):
									dict_obj.remove_meta("new")
								
							# log and UI
							mgr.add_log_history.emit("OK", begin_time, i.get_query_cmd(), 
								"%d row(s) affected" % ret.get_affected_rows(), ret.get_cost_time())
							(table_2.datas[index][4] as ProgressBar).value = 100
							(table_2.datas[index][4] as ProgressBar).modulate = Color.GREEN
							(table_2.datas[index][3] as CheckBox).button_pressed = false
							(table_2.datas[index][3] as CheckBox).disabled = true
						else:
							mgr.add_log_history.emit("Err", begin_time, i.get_query_cmd(), 
								ret.get_err(), ret.get_cost_time())
							(table_2.datas[index][4] as ProgressBar).modulate = Color.RED
					else:
						mgr.add_log_history.emit("Err", begin_time, i.get_query_cmd(), "something wrong")
						(table_2.datas[index][4] as ProgressBar).modulate = Color.RED
						
				var can_execute = false
				for row in table_2.datas:
					if not (row[3] as CheckBox).disabled:
						can_execute = true
						break
						
				# 不能再执行时，把按钮名称改为“关闭”，这样下次用户点击该按钮时，对话框就可以关闭了
				if not can_execute:
					dialog_ref[0].ok_button_text = "close"
					
				# true：让该页面不关闭
				return [true, false] # 不涉及defered函数，所以第二个参数传的没什么意义
				
			# 对话框关闭时要执行的方法
			var defered = func(_confirmed, _dummy):
				update_btn_disable_status.call("", 0, 0) # 刷新按钮状态。参数随便传。
				table_2.queue_free()
				check_all_btn.queue_free()
				
			var dialog = mgr.create_custom_dialog(arr, confirmed, Callable(), defered, 0.5)
			dialog_ref.push_back(dialog)
			dialog.ok_button_text = "execute"
			var btn_close_refresh = dialog.add_button("close and refresh", true, "close_and_refresh")
			btn_close_refresh.tooltip_text = "Refresh the table. Actions that not have been executed will be discarded."
			btn_close_refresh.disabled = get_from_nodes(graph_node, "Select").filter(func(v):
				return v.enabled
			).is_empty() # 如果这个表格没有关联select节点，就无法刷新
			if btn_close_refresh.disabled:
				btn_close_refresh.tooltip_text += "\n[Tip]This button is disabled because this Result-node is "\
					+ "not connected to a Select-node or the Select-node is not enabled."
			dialog.custom_action.connect(func(action):
				if action == "close_and_refresh":
					update_btn_disable_status.call("", 0, 0)
					var onclose = func ():
						table.remove_meta("deleted_datas")
						for node in get_from_nodes(graph_node, "Select"):
							on_select_node_query(node, true)
						mgr._clear_custom_dialog(dialog)
						
					if btn_apply.disabled:
						onclose.call()
					else:
						mgr.create_confirmation_dialog("You have some modifications that have not been executed.\n"\
							+ "If you refresh, these modifications will be discarded. \nAre you sure to refresh the table?"
							, onclose)
			)
		)
		
		var btn_revert = Button.new()
		btn_ref[1] = btn_revert
		btn_revert.text = "revert"
		btn_revert.disabled = true
		btn_revert.pressed.connect(func():
			var old_datas: Array = []
			# 恢复被修改的数据
			for i: DictionaryObject in table.datas:
				if not i.has_meta("new"):
					i.revert()
					old_datas.push_back(i)
			# 恢复被删除的数据
			var deleted_datas = table.get_meta("deleted_datas", {})
			table.remove_meta("deleted_datas")
			for i in deleted_datas:
				#old_datas.insert(i, deleted_datas[i]) # 注意：前提是新建的数据都是放在最后面的，不影响数据回到原来的位置。
				(deleted_datas[i] as DictionaryObject).revert()
				table.insert_data(i, deleted_datas[i]) # 注意：前提是新建的数据都是放在最后面的，不影响数据回到原来的位置。
			#table.datas = old_datas
			# 删除新建的数据
			for i in range(table.datas.size()-1, -1, -1):
				if table.datas[i].has_meta("new"):
					table.remove_data_at(i, true)
			btn_apply.disabled = true
			btn_revert.disabled = true
		)
		
		table.row_deleted.connect(func(datas):
			var deleted_datas = table.get_meta("deleted_datas", {}) as Dictionary
			
			# 找到最小行号
			var min_index = 9999999999
			for i in datas:
				min_index = min(datas[i].get_meta("index"), min_index)
				
			# 最小行号前面有几个被删除了
			var offset = 0
			for i in deleted_datas:
				if deleted_datas[i].get_meta("index") < min_index:
					offset += 1
					
			for i in datas:
				var data = datas[i]
				if data.has_meta("new"):
					return
				deleted_datas[i + offset] = data
				
			# 提取字典的键到数组中
			var keys = deleted_datas.keys()
			keys.sort()
			var sorted_dict = {}
			for key in keys:
				sorted_dict[key] = deleted_datas[key]
				
			# 排序后存入
			table.set_meta("deleted_datas", sorted_dict)
			btn_apply.disabled = false
			btn_revert.disabled = false
		)
		
		var btn_new = Button.new()
		btn_new.text = "new"
		btn_new.tooltip_text = "Press 'Ctrl' to add 10 new row."
		btn_new.pressed.connect(func():
			var num = 1
			if Input.is_key_pressed(KEY_CTRL):
				num = 10
			for i in num:
				# 构造一个默认新数据
				var new_data = {}
				for j in new_column_prop_name:
					if j["type"] is String and j["type"] == "group":
						new_data[j["prop"]] = "" # for group
					else:
						var col_def = columns.filter(func(v):
							return v["Column Name"] == j["col_name"]
						).front()
						if (col_def["Default(Expression)"] as String).strip_edges().is_empty():
							new_data[j["prop"]] = DataTypeDef.DEFUALT_VALUES[col_def["Data Type"]]
						else:
							new_data[j["prop"]] = GDSQLUtils.evaluate_command(null, col_def["Default(Expression)"])
							
							
				var dict_obj = DictionaryObject.new(new_data, hint, false)
				dict_obj.set_meta("new", true)
				if table.datas.is_empty():
					dict_obj.set_meta("index", 0)
				else:
					dict_obj.set_meta("index", table.datas.back().get_meta("index") + 1)
				dict_obj._get_property_list() # NOTICE trigger ENUM text possibly
				dict_obj.value_changed.connect(update_btn_disable_status)
				table.append_data(dict_obj)
				table.row_grab_focus(table.datas.size() - 1)
		)
		
		var flow_container = graph_datas[1][2]
		flow_container.add_child(btn_new)
		flow_container.add_child(btn_apply)
		flow_container.add_child(btn_revert)
		flow_container.get_child(0).move_to_front() # move export button to last
		
		# 每行数据转成一个DictionaryObject
		var new_table_datas = []
		for i in table_datas:
			var data = {}
			var new_hint = hint
			for j in new_column_prop_name:
				if j["type"] is String and j["type"] == "group":
					data[j["prop"]] = "" # for group
				else:
					data[j["prop"]] = i[j["type"]]
					# 联表时，主键和关联键禁止修改，除键值为null。而且就算修改，也不能使用已存在的键值（null说明原本就跟已存在的键值没关联）
					if i[j["type"]] != null and uneditable_index.has(j["type"]):
						if new_hint == hint:
							new_hint = hint.duplicate(true)
						new_hint[j["prop"]]["usage"] = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY
						# TODO 不能使用已存在的键值
						
			var dict_obj = DictionaryObject.new(data, new_hint, false)
			dict_obj.value_changed.connect(update_btn_disable_status)
			dict_obj.set_meta("index", new_table_datas.size()) # 为了revert删除的数据时判断前后位置
			dict_obj._get_property_list() # NOTICE trigger ENUM text possibly
			new_table_datas.push_back(dict_obj)
		table.datas = new_table_datas
		table.support_delete_row = true
	else:
		table.datas = table_datas
		table.support_delete_row = false
		
	graph_node.datas = graph_datas
	
	if v_scroll_h > 0:
		table.set_deferred("v_scroll_height", v_scroll_h)
		
	return graph_node
	
## 检查是否存在某主键的Callable
func exist_callable(db_path, table_name, field_name, field_value) -> bool:
	var ret = BaseDao.new().use_db(db_path).select(field_name, false).from(table_name)\
		.where("%s == %s" % [field_name, var_to_str(field_value)]).query()
	if ret == null or not ret.ok():
		push_warning("Something weired. Check this.")
		return true # 报错了，不知道具体啥情况，视为true
	# 数据库有该条数据
	if not ret.get_data().is_empty():
		return true
	return false
	
func add_insert_node(schema = "", password = "", table = "", fields = {}, 
asize = null, pos_offset = null, aname = ""):
	graph_edit.grab_focus() # 激活绘图板的快捷键，比如delte， ctrl+C/V
	unselect_all_node()
	
	var graph_node = gen_insert_node()
	if aname != "":
		graph_node.name = aname
	graph_edit.add_child(graph_node)
	
	# 等待页面就绪
	if not graph_edit.get_rect().has_area():
		await graph_edit.resized
		
	if pos_offset == null:
		graph_node.position_offset = \
			(graph_edit.get_rect().get_center() - graph_node.get_rect().size/2 + graph_edit.scroll_offset) / graph_edit.zoom
	else:
		graph_node.position_offset = pos_offset
		
	if asize != null:
		graph_node.set_deferred("size", asize)
	
	var schema_dict_obj: DictionaryObject = graph_node.datas[0][2]
	var table_dict_obj: DictionaryObject = graph_node.datas[1][2]
	
	if not fields.is_empty():
		var arr = []
		var redraw_call = func(row, col):
			if row == 2 and col == 2 and table_dict_obj._get("Table") == table:
				var fields_dict_obj: DictionaryObject = graph_node.datas[2][2]
				for key in fields:
					fields_dict_obj._set(key, fields[key])
				graph_node.redraw_slot.disconnect(arr[0])
				
		arr.push_back(redraw_call)
		graph_node.redraw_slot.connect(redraw_call)
		
	if schema != schema_dict_obj._get("Schema"):
		schema_dict_obj._set("Schema", schema)
	if password != schema_dict_obj._get("_password"):
		schema_dict_obj._set("_password", password)
	if table != table_dict_obj._get("Table"):
		table_dict_obj._set("Table", table)
		
	return graph_node
	
	
func gen_insert_node() -> GraphNode:
	var databases = mgr.databases.keys()
	
	var schema_dict_obj = DictionaryObject.new(
		{"Schema": "", "_password": ""}, 
		{"Schema": {"hint": PROPERTY_HINT_ENUM, "hint_string": ",".join(databases)}, 
		"_password": {"hint": PROPERTY_HINT_PASSWORD, "hint_string": "password"}})
	var table_dict_obj = DictionaryObject.new(
		{"Table": ""}, {"Table": {"hint": PROPERTY_HINT_ENUM, "hint_string": ""}})
	var fields_dict_obj = DictionaryObject.new(
		{"ColumnName": false}, {"ColumnName": {"usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY}})
	fields_dict_obj.set_meta("align", "vertical") # 垂直显示各属性
	
	# 关联该节点的BaseDao
	var base_dao = BaseDao.new()
	base_dao.insert_into("")
	var graph_node = SQLGraphNode.instantiate()
	graph_node.set_meta("base_dao", base_dao)
	graph_node.node_enable_status.connect(mark_modified)
	
	# 根据选择的数据库来更新表名备选项
	schema_dict_obj.value_changed.connect(func(prop, new_val, _old_val):
		graph_node.push_redraw_slot_control(0, 2) # 如果不是通过点击的控件修改的dict obj，就需要重绘一下。这里偷个懒，直接重绘。
		match prop:
			"Schema":
				base_dao.use_db(mgr.databases[new_val]["data_path"])
				var tables = mgr.databases[new_val]["tables"].keys()
				table_dict_obj.reset_hint(
					{"Table": {"hint": PROPERTY_HINT_ENUM, "hint_string": ",".join(tables)}})
				table_dict_obj._set("Table", "", true)
			"_password":
				base_dao.set_password(new_val)
	)
	table_dict_obj.value_changed.connect(func(prop, new_val, _old_val):
		graph_node.push_redraw_slot_control(1, 2)
		match prop:
			"Table":
				base_dao.set_table(new_val + DATA_EXTENSION)
				if new_val != "" and mgr.databases[schema_dict_obj._get("Schema")]["tables"].has(new_val):
					var data = {}
					var hints = {}
					for col in mgr.databases[schema_dict_obj._get("Schema")]["tables"][new_val]["columns"]:
						data[col["Column Name"]] = DataTypeDef.DEFUALT_VALUES[col["Data Type"]]
						hints[col["Column Name"]] = {"hint": col["Hint"], "hint_string": col["Hint String"], "type": col["Data Type"]}
					fields_dict_obj.reset_data(data, hints)
				else:
					fields_dict_obj.reset_data({"ColumnName": false}, {"ColumnName": {"usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY}})
				graph_node.push_redraw_slot_control(2, 2)
	)
	
	var btn_query = Button.new()
	btn_query.text = "apply"
	btn_query.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_query.pressed.connect(on_insert_node_query.bind(graph_node))
	btn_query.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	
	var separator = Control.new()
	separator.custom_minimum_size.y = 10
	var separator2 = Control.new()
	separator2.custom_minimum_size.y = 10
	
	var datas: Array[Array] = [
		[null, null, schema_dict_obj],
		[null, null, table_dict_obj],
		[null, null, fields_dict_obj],
		[null, null, separator],
		[null, null, btn_query],
		[null, null, separator2]
	]
	graph_node.datas = datas
	graph_node.title = "Insert"
	graph_node.add_theme_stylebox_override("panel", SB_PANEL)
	graph_node.add_theme_stylebox_override("panel_selected", SB_PANEL_SELECTED)
	graph_node.add_theme_stylebox_override("titlebar", SB_INSERT_TITLEBAR)
	graph_node.add_theme_stylebox_override("titlebar_selected", SB_INSERT_TITLEBAR_SELECTED)
	graph_node.ready.connect(func():
		graph_node.size.x = 650
		graph_node.selected = true
	)
	graph_node.set_meta("type", "Insert")
	graph_node.set_meta("node", true)
	graph_node.delete_request.connect(func():
		node_close(graph_node)
	)
	graph_node.node_enable_status.connect(func(enabled):
		btn_query.disabled = !enabled
	)
	
	return graph_node
	
func add_update_node(schema = "", password = "", table = "", fields = {}, where = "", 
asize = null, pos_offset = null, aname = ""):
	graph_edit.grab_focus() # 激活绘图板的快捷键，比如delte， ctrl+C/V
	unselect_all_node()
	
	var graph_node = gen_update_node()
	if aname != "":
		graph_node.name = aname
	graph_edit.add_child(graph_node)
	
	# 等待页面就绪
	if not graph_edit.get_rect().has_area():
		await graph_edit.resized
		
	if pos_offset == null:
		graph_node.position_offset = \
			(graph_edit.get_rect().get_center() - graph_node.get_rect().size/2 + graph_edit.scroll_offset) / graph_edit.zoom
	else:
		graph_node.position_offset = pos_offset
		
	if asize != null:
		graph_node.set_deferred("size", asize)
	
	var schema_dict_obj: DictionaryObject = graph_node.datas[0][2]
	var table_dict_obj: DictionaryObject = graph_node.datas[1][2]
	var where_dict_obj: DictionaryObject = graph_node.datas[3][2]
	
	if not fields.is_empty():
		var arr = []
		var redraw_call = func(row, col):
			if row == 2 and col == 2 and table_dict_obj._get("Table") == table:
				var fields_dict_obj: DictionaryObject = graph_node.datas[2][2]
				for key in fields:
					fields_dict_obj._set(key, fields[key])
				graph_node.redraw_slot.disconnect(arr[0])
				
		arr.push_back(redraw_call)
		graph_node.redraw_slot.connect(redraw_call)
		
	if schema != schema_dict_obj._get("Schema"):
		schema_dict_obj._set("Schema", schema)
	if password != schema_dict_obj._get("_password"):
		schema_dict_obj._set("_password", password)
	if table != table_dict_obj._get("Table"):
		table_dict_obj._set("Table", table)
	if where != where_dict_obj._get("Where"):
		where_dict_obj._set("Where", where)
		
	return graph_node
	
func gen_update_node() -> GraphNode:
	var databases = mgr.databases.keys()
	
	var schema_dict_obj = DictionaryObject.new(
		{"Schema": "", "_password": ""}, 
		{"Schema": {"hint": PROPERTY_HINT_ENUM, "hint_string": ",".join(databases)}, 
		"_password": {"hint": PROPERTY_HINT_PASSWORD, "hint_string": "password"}})
	var table_dict_obj = DictionaryObject.new(
		{"Table": ""}, {"Table": {"hint": PROPERTY_HINT_ENUM, "hint_string": ""}})
	var fields_dict_obj = DictionaryObject.new(
		{"ColumnName": false}, {"ColumnName": {"usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY}})
	var where_dict_obj = DictionaryObject.new({"Where": ""}, {"Where": {"hint": PROPERTY_HINT_MULTILINE_TEXT}})
	
	# 关联该节点的BaseDao
	var base_dao = BaseDao.new()
	base_dao.update("")
	base_dao.set_evalueate_mode(true)
	
	var graph_node = SQLGraphNode.instantiate()
	graph_node.set_meta("base_dao", base_dao)
	graph_node.node_enable_status.connect(mark_modified)
	
	# 根据选择的数据库来更新表名备选项
	schema_dict_obj.value_changed.connect(func(prop, new_val, _old_val):
		graph_node.push_redraw_slot_control(0, 2) # 如果不是通过点击的控件修改的dict obj，就需要重绘一下。这里偷个懒，直接重绘。
		match prop:
			"Schema":
				base_dao.use_db(mgr.databases[new_val]["data_path"])
				var tables = mgr.databases[new_val]["tables"].keys()
				table_dict_obj.reset_hint(
					{"Table": {"hint": PROPERTY_HINT_ENUM, "hint_string": ",".join(tables)}})
				table_dict_obj._set("Table", "", true)
			"_password":
				base_dao.set_password(new_val)
	)
	table_dict_obj.value_changed.connect(func(prop, new_val, _old_val):
		graph_node.push_redraw_slot_control(1, 2)
		match prop:
			"Table":
				base_dao.set_table(new_val + DATA_EXTENSION)
				if new_val != "" and mgr.databases[schema_dict_obj._get("Schema")]["tables"].has(new_val):
					var data = {}
					var hints = {}
					for col in mgr.databases[schema_dict_obj._get("Schema")]["tables"][new_val]["columns"]:
						data[col["Column Name"]] = DataTypeDef.DEFUALT_VALUES[col["Data Type"]]
						hints[col["Column Name"]] = {"hint": col["Hint"], "hint_string": col["Hint String"], "type": col["Data Type"]}
					fields_dict_obj.reset_data(data, hints)
					fields_dict_obj.set_meta("align", "vertical") # 垂直显示各属性
				else:
					fields_dict_obj.reset_data({"ColumnName": false}, {"ColumnName": {"usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY}})
				graph_node.push_redraw_slot_control(2, 2)
	)
	where_dict_obj.value_changed.connect(func(prop, new_val, _old_val):
		graph_node.push_redraw_slot_control(3, 2)
		match prop:
			"Where":
				base_dao.set_where(new_val)
	)
	
	var btn_query = Button.new()
	btn_query.text = "apply"
	btn_query.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_query.pressed.connect(on_update_node_query.bind(graph_node))
	btn_query.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	
	var separator = Control.new()
	separator.custom_minimum_size.y = 10
	var separator2 = Control.new()
	separator2.custom_minimum_size.y = 10
	
	var datas: Array[Array] = [
		[null, null, schema_dict_obj],
		[null, null, table_dict_obj],
		[null, null, fields_dict_obj],
		[null, null, where_dict_obj],
		[null, null, separator],
		[null, null, btn_query],
		[null, null, separator2]
	]
	graph_node.datas = datas
	graph_node.title = "Update"
	graph_node.add_theme_stylebox_override("panel", SB_PANEL)
	graph_node.add_theme_stylebox_override("panel_selected", SB_PANEL_SELECTED)
	graph_node.add_theme_stylebox_override("titlebar", SB_UPDATE_TITLEBAR)
	graph_node.add_theme_stylebox_override("titlebar_selected", SB_UPDATE_TITLEBAR_SELECTED)
	graph_node.ready.connect(func():
		graph_node.size.x = 650
		graph_node.selected = true
	)
	graph_node.set_meta("type", "Update")
	graph_node.set_meta("node", true)
	graph_node.delete_request.connect(func():
		node_close(graph_node)
	)
	graph_node.node_enable_status.connect(func(enabled):
		btn_query.disabled = !enabled
	)
	
	return graph_node
	
func add_delete_node(schema = "", password = "", table = "", where = "", 
asize = null, pos_offset = null, aname = ""):
	graph_edit.grab_focus() # 激活绘图板的快捷键，比如delte， ctrl+C/V
	unselect_all_node()
	
	var graph_node = gen_update_node()
	if aname != "":
		graph_node.name = aname
	graph_edit.add_child(graph_node)
	
	# 等待页面就绪
	if not graph_edit.get_rect().has_area():
		await graph_edit.resized
		
	if pos_offset == null:
		graph_node.position_offset = \
			(graph_edit.get_rect().get_center() - graph_node.get_rect().size/2 + graph_edit.scroll_offset) / graph_edit.zoom
	else:
		graph_node.position_offset = pos_offset
		
	if asize != null:
		graph_node.set_deferred("size", asize)
	
	var schema_dict_obj: DictionaryObject = graph_node.datas[0][2]
	var table_dict_obj: DictionaryObject = graph_node.datas[1][2]
	var where_dict_obj: DictionaryObject = graph_node.datas[2][2]
	
	if schema != schema_dict_obj._get("Schema"):
		schema_dict_obj._set("Schema", schema)
	if password != schema_dict_obj._get("_password"):
		schema_dict_obj._set("_password", password)
	if table != table_dict_obj._get("Table"):
		table_dict_obj._set("Table", table)
	if where != where_dict_obj._get("Where"):
		where_dict_obj._set("Where", where)
		
	return graph_node
	
func gen_delete_node() -> GraphNode:
	var databases = mgr.databases.keys()
	
	var schema_dict_obj = DictionaryObject.new(
		{"Schema": "", "_password": ""}, 
		{"Schema": {"hint": PROPERTY_HINT_ENUM, "hint_string": ",".join(databases)}, 
		"_password": {"hint": PROPERTY_HINT_PASSWORD, "hint_string": "password"}})
	var table_dict_obj = DictionaryObject.new(
		{"Table": ""}, {"Table": {"hint": PROPERTY_HINT_ENUM, "hint_string": ""}})
	var where_dict_obj = DictionaryObject.new({"Where": ""}, {"Where": {"hint": PROPERTY_HINT_MULTILINE_TEXT}})
	
	# 关联该节点的BaseDao
	var base_dao = BaseDao.new()
	base_dao.delete_from("")
	var graph_node = SQLGraphNode.instantiate()
	graph_node.set_meta("base_dao", base_dao)
	graph_node.node_enable_status.connect(mark_modified)
	
	# 根据选择的数据库来更新表名备选项
	schema_dict_obj.value_changed.connect(func(prop, new_val, _old_val):
		graph_node.push_redraw_slot_control(0, 2) # 如果不是通过点击的控件修改的dict obj，就需要重绘一下。这里偷个懒，直接重绘。
		match prop:
			"Schema":
				base_dao.use_db(mgr.databases[new_val]["data_path"])
				var tables = mgr.databases[new_val]["tables"].keys()
				table_dict_obj.reset_hint(
					{"Table": {"hint": PROPERTY_HINT_ENUM, "hint_string": ",".join(tables)}})
				table_dict_obj._set("Table", "", true)
			"_password":
				base_dao.set_password(new_val)
	)
	table_dict_obj.value_changed.connect(func(prop, new_val, _old_val):
		graph_node.push_redraw_slot_control(1, 2)
		match prop:
			"Table":
				base_dao.set_table(new_val + DATA_EXTENSION)
	)
	where_dict_obj.value_changed.connect(func(prop, new_val, _old_val):
		graph_node.push_redraw_slot_control(2, 2)
		match prop:
			"Where":
				base_dao.set_where(new_val)
	)
	
	var btn_query = Button.new()
	btn_query.text = "apply"
	btn_query.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_query.pressed.connect(on_delete_node_query.bind(graph_node))
	btn_query.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	
	var separator = Control.new()
	separator.custom_minimum_size.y = 10
	var separator2 = Control.new()
	separator2.custom_minimum_size.y = 10
	
	var datas: Array[Array] = [
		[null, null, schema_dict_obj],
		[null, null, table_dict_obj],
		[null, null, where_dict_obj],
		[null, null, separator],
		[null, null, btn_query],
		[null, null, separator2]
	]
	graph_node.datas = datas
	graph_node.title = "Delete"
	graph_node.add_theme_stylebox_override("panel", SB_PANEL)
	graph_node.add_theme_stylebox_override("panel_selected", SB_PANEL_SELECTED)
	graph_node.add_theme_stylebox_override("titlebar", SB_DELETE_TITLEBAR)
	graph_node.add_theme_stylebox_override("titlebar_selected", SB_DELETE_TITLEBAR_SELECTED)
	graph_node.ready.connect(func():
		graph_node.size.x = 650
		graph_node.selected = true
	)
	graph_node.set_meta("type", "Delete")
	graph_node.set_meta("node", true)
	graph_node.delete_request.connect(func():
		node_close(graph_node)
	)
	graph_node.node_enable_status.connect(func(enabled):
		btn_query.disabled = !enabled
	)
	
	return graph_node
	
func add_sql_node(sql = "", asize = null, pos_offset = null, aname = "", query = true):
	graph_edit.grab_focus() # 激活绘图板的快捷键，比如delte， ctrl+C/V
	unselect_all_node()
	
	var graph_node = gen_sql_node()
	if aname != "":
		graph_node.name = aname
	graph_edit.add_child(graph_node)
	
	if asize != null:
		graph_node.size = asize
		
	if sql != "":
		var code_editor = graph_node.datas[1][2] as CodeEdit
		code_editor.text = sql
		
	# 等待页面就绪
	if not graph_edit.get_rect().has_area():
		await graph_edit.resized
		
	if pos_offset == null:
		graph_node.position_offset = \
			(graph_edit.get_rect().get_center() - graph_node.get_rect().size/2 + graph_edit.scroll_offset) / graph_edit.zoom
	else:
		graph_node.position_offset = pos_offset
		
	if asize != null:
		graph_node.set_deferred("size", asize)
		
	var btn_query: Button = graph_node.datas[3][2]
	if query:
		btn_query.emit_signal("pressed")
		
	return graph_node
	
func gen_sql_node() -> GraphNode:
	var code_editor = CodeEdit.new()
	code_editor.caret_blink = true
	code_editor.highlight_all_occurrences = true
	code_editor.highlight_current_line = true
	code_editor.scroll_fit_content_height = true
	code_editor.gutters_draw_line_numbers = true
	code_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_editor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	code_editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	
	var graph_node = SQLGraphNode.instantiate()
	graph_node.node_enable_status.connect(mark_modified)
	
	var separator = Control.new()
	separator.custom_minimum_size.y = 10
	var separator2 = Control.new()
	separator2.custom_minimum_size.y = 10
	
	var btn_query = Button.new()
	btn_query.text = "apply"
	btn_query.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_query.pressed.connect(on_sql_node_query.bind(graph_node, true))
	btn_query.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn_query.disabled = true
	code_editor.text_changed.connect(func():
		btn_query.disabled = code_editor.text == ""
	)
	
	var datas: Array[Array] = [
		[null, "Result"],
		[null, null, code_editor],
		[null, null, separator],
		[null, null, btn_query],
		[null, null, separator2]
	]
	graph_node.datas = datas
	graph_node.title = "SQL"
	graph_node.add_theme_stylebox_override("panel", SB_PANEL)
	graph_node.add_theme_stylebox_override("panel_selected", SB_PANEL_SELECTED)
	graph_node.add_theme_stylebox_override("titlebar", SB_SQL_TITLEBAR)
	graph_node.add_theme_stylebox_override("titlebar_selected", SB_SQL_TITLEBAR_SELECTED)
	graph_node.ready.connect(func():
		graph_node.set_slot_type_right(0, 0) # Result's type is 0
		graph_node.size.x = 900
		graph_node.selected = true
	)
	graph_node.set_meta("type", "SQL")
	graph_node.set_meta("node", true)
	graph_node.delete_request.connect(func():
		node_close(graph_node)
	)
	graph_node.node_enable_status.connect(func(enabled):
		btn_query.disabled = !enabled
	)
	
	return graph_node
	
func add_link_node(link_db = "", link_password = "", link_table = "", right_columns = 3,
link_left_col = "", link_right_col = "", left_db = "", left_password = "", left_table = "",
left_link_col = "", left_cols_shown = {}, left_where = "", left_order_by = "", left_offset = 0, left_limit = 1000,
left_show_column_name = false, left_show_column_value = true, left_font_size = 14, left_processor = "",
right_db = "", right_password = "", right_table = "", 
right_link_col = "", right_cols_shown = {}, right_where = "", right_order_by = "", right_offset = 0, right_limit = 1000,
right_show_column_name = false, right_show_column_value = true, right_font_size = 14, right_processor = "",
asize = null, pos_offset = null, aname = "", query = true):
	graph_edit.grab_focus() # 激活绘图板的快捷键，比如delte， ctrl+C/V
	unselect_all_node()
	
	var graph_node = gen_link_node()
	if aname != "":
		graph_node.name = aname
	graph_edit.add_child(graph_node)
	
	if asize != null:
		graph_node.size = asize
		
	#0 [null, "Result"],
	#1 [null, null, schema_dict_obj],
	#2 [null, null, table_dict_obj],
	#3 [null, null, link_prop_dict_obj],
	#4 [null, null, hseparator],
	#5 [null, null, left_schema_dict_obj, right_schema_dict_obj],
	#6 [null, null, left_table_dict_obj, right_table_dict_obj],
	#7 [null, null, left_link_prop_dict_obj, right_link_prop_dict_obj],
	#8 [null, null, left_column_dict_obj, right_column_dict_obj],
	#9 [null, null, left_where_dict_obj, right_where_dict_obj],
	#10 [null, null, left_order_dict_obj, right_order_dict_obj],
	#11 [null, null, left_limit_dict_obj, right_limit_dict_obj],
	#12 [null, null, left_other_options, right_other_options],
	#13 [null, null, separator],
	#14 [null, null, btn_query],
	#15 [null, null, separator2]
	var schema_dict_obj: DictionaryObject = graph_node.datas[1][2]
	var table_dict_obj: DictionaryObject = graph_node.datas[2][2]
	var link_prop_dict_obj: DictionaryObject = graph_node.datas[3][2]
	var left_schema_dict_obj: DictionaryObject = graph_node.datas[5][2]
	var right_schema_dict_obj: DictionaryObject = graph_node.datas[5][3]
	var left_table_dict_obj: DictionaryObject = graph_node.datas[6][2]
	var right_table_dict_obj: DictionaryObject = graph_node.datas[6][3]
	var left_link_prop_dict_obj: DictionaryObject = graph_node.datas[7][2]
	var right_link_prop_dict_obj: DictionaryObject = graph_node.datas[7][3]
	var left_column_dict_obj: DictionaryObject = graph_node.datas[8][2]
	var right_column_dict_obj: DictionaryObject = graph_node.datas[8][3]
	var left_where_dict_obj: DictionaryObject = graph_node.datas[9][2]
	var right_where_dict_obj: DictionaryObject = graph_node.datas[9][3]
	var left_order_dict_obj: DictionaryObject = graph_node.datas[10][2]
	var right_order_dict_obj: DictionaryObject = graph_node.datas[10][3]
	var left_limit_dict_obj: DictionaryObject = graph_node.datas[11][2]
	var right_limit_dict_obj: DictionaryObject = graph_node.datas[11][3]
	var left_other_options: DictionaryObject = graph_node.datas[12][2]
	var right_other_options: DictionaryObject = graph_node.datas[12][3]
	
	if link_db != schema_dict_obj._get("Schema"):
		schema_dict_obj._set("Schema", link_db)
	if link_password != schema_dict_obj._get("_password"):
		schema_dict_obj._set("_password", link_password)
	if link_table != table_dict_obj._get("Table"):
		table_dict_obj._set("Table", link_table)
	if right_columns != table_dict_obj._get("Right Columns"):
		table_dict_obj._set("Right Columns", right_columns)
	if link_left_col != link_prop_dict_obj._get("Left"):
		link_prop_dict_obj._set("Left", link_left_col)
	if link_right_col != link_prop_dict_obj._get("Right"):
		link_prop_dict_obj._set("Right", link_right_col)
		
	if left_db != left_schema_dict_obj._get("Schema1"):
		left_schema_dict_obj._set("Schema1", left_db)
	if left_password != left_schema_dict_obj._get("_password1"):
		left_schema_dict_obj._set("_password1", left_password)
	if left_table != left_table_dict_obj._get("Table1"):
		left_table_dict_obj._set("Table1", left_table)
	if left_link_col != left_link_prop_dict_obj._get("LinkColumnName"):
		left_link_prop_dict_obj._set("LinkColumnName", left_link_col)
	for info in left_column_dict_obj._get_property_list():
		var shown = left_cols_shown.get(info.name, false)
		if shown != left_column_dict_obj._get(info.name):
			left_column_dict_obj._set(info.name, shown)
	if left_where != left_where_dict_obj._get("Where"):
		left_where_dict_obj._set("Where", left_where)
	if left_order_by != left_order_dict_obj._get("Order By"):
		left_order_dict_obj._set("Order By", left_order_by)
	if left_offset != left_limit_dict_obj._get("Offset"):
		left_limit_dict_obj._set("Offset", left_offset)
	if left_limit != left_limit_dict_obj._get("Limit"):
		left_limit_dict_obj._set("Limit", left_limit)
	if left_show_column_name != left_other_options._get("show_column_name"):
		left_other_options._set("show_column_name", left_show_column_name)
	if left_show_column_value != left_other_options._get("show_column_value"):
		left_other_options._set("show_column_value", left_show_column_value)
	if left_font_size != left_other_options._get("font_size"):
		left_other_options._set("font_size", left_font_size)
	if left_processor != left_other_options._get("processor"):
		left_other_options._set("processor", left_processor)
		
	if right_db != right_schema_dict_obj._get("Schema2"):
		right_schema_dict_obj._set("Schema2", right_db)
	if right_password != right_schema_dict_obj._get("_password2"):
		right_schema_dict_obj._set("_password2", right_password)
	if right_table != right_table_dict_obj._get("Table2"):
		right_table_dict_obj._set("Table2", right_table)
	if right_link_col != right_link_prop_dict_obj._get("LinkColumnName"):
		right_link_prop_dict_obj._set("LinkColumnName", right_link_col)
	for info in right_column_dict_obj._get_property_list():
		var shown = right_cols_shown.get(info.name, false)
		if shown != right_column_dict_obj._get(info.name):
			right_column_dict_obj._set(info.name, shown)
	if right_where != right_where_dict_obj._get("Where"):
		right_where_dict_obj._set("Where", right_where)
	if right_order_by != right_order_dict_obj._get("Order By"):
		right_order_dict_obj._set("Order By", right_order_by)
	if right_offset != right_limit_dict_obj._get("Offset"):
		right_limit_dict_obj._set("Offset", right_offset)
	if right_limit != right_limit_dict_obj._get("Limit"):
		right_limit_dict_obj._set("Limit", right_limit)
	if right_show_column_name != right_other_options._get("show_column_name"):
		right_other_options._set("show_column_name", right_show_column_name)
	if right_show_column_value != right_other_options._get("show_column_value"):
		right_other_options._set("show_column_value", right_show_column_value)
	if right_font_size != right_other_options._get("font_size"):
		right_other_options._set("font_size", right_font_size)
	if right_processor != right_other_options._get("processor"):
		right_other_options._set("processor", right_processor)
		
	# 等待页面就绪
	if not graph_edit.get_rect().has_area():
		await graph_edit.resized
		
	if pos_offset == null:
		graph_node.position_offset = \
			(graph_edit.get_rect().get_center() - graph_node.get_rect().size/2 + graph_edit.scroll_offset) / graph_edit.zoom
	else:
		graph_node.position_offset = pos_offset
		
	if asize != null:
		graph_node.set_deferred("size", asize)
		
	var btn_query: Button = graph_node.datas[14][2]
	if query:
		btn_query.emit_signal("pressed")
		
	return graph_node
	
func gen_link_node() -> GraphNode:
	var databases = mgr.databases.keys()
	
	var schema_dict_obj = DictionaryObject.new(
		{"Schema": "", "_password": ""}, 
		{"Schema": {"hint": PROPERTY_HINT_ENUM, "hint_string": ",".join(databases)}, 
		"_password": {"hint": PROPERTY_HINT_PASSWORD, "hint_string": "password"}})
	var table_dict_obj = DictionaryObject.new(
		{"Table": "", "Right Columns": 3}, 
		{"Table": {"hint": PROPERTY_HINT_ENUM, "hint_string": ""}})
	var link_prop_dict_obj = DictionaryObject.new(
		{"Left": "", "Right": ""},
		{"Left": {"hint": PROPERTY_HINT_ENUM, "hint_string": ""},
		"Right": {"hint": PROPERTY_HINT_ENUM, "hint_string": ""}})
		
	# 关联该节点的BaseDao
	var data = DictionaryObject.new({"a": 1})
	
	var graph_node = SQLGraphNode.instantiate()
	graph_node.set_meta("data", data)
	#graph_node.set_meta("base_dao", base_dao)
	graph_node.node_enable_status.connect(mark_modified)
	
	# 根据选择的数据库来更新表名备选项
	schema_dict_obj.value_changed.connect(func(prop, new_val, _old_val):
		graph_node.push_redraw_slot_control(1, 2) # 如果不是通过点击的控件修改的dict obj，就需要重绘一下。这里偷个懒，直接重绘。
		match prop:
			"Schema":
				data.set_meta("link_db", mgr.databases[new_val]["data_path"])
				var tables = mgr.databases[new_val]["tables"].keys()
				table_dict_obj.reset_hint(
					{"Table": {"hint": PROPERTY_HINT_ENUM, "hint_string": ",".join(tables)},})
				table_dict_obj._set("Table", "", true) # 强制设置（可以避免值没变化导致没有发出信号）
			"_password":
				data.set_meta("link_password", new_val)
	)
	table_dict_obj.value_changed.connect(func(prop, new_val, _old_val):
		graph_node.push_redraw_slot_control(2, 2)
		match prop:
			"Table":
				data.set_meta("link_table", new_val)
				var hints = []
				if new_val != "" and mgr.databases[schema_dict_obj._get("Schema")]["tables"].has(new_val):
					for col in mgr.databases[schema_dict_obj._get("Schema")]["tables"][new_val]["columns"]:
						hints.push_back(col["Column Name"])
				hints = ",".join(hints)
				link_prop_dict_obj.reset_hint({
					"Left": {"hint": PROPERTY_HINT_ENUM, "hint_string": hints},
					"Right": {"hint": PROPERTY_HINT_ENUM, "hint_string": hints}
				})
				link_prop_dict_obj._set("Left", "", true)
				link_prop_dict_obj._set("Right", "", true)
				graph_node.push_redraw_slot_control(3, 2)
	)
	var left_schema_dict_obj = DictionaryObject.new(
		{"Schema1": "", "_password1": ""}, 
		{
			"Schema1": {"hint": PROPERTY_HINT_ENUM, "hint_string": ",".join(databases)}, 
			"_password1": {"hint": PROPERTY_HINT_PASSWORD, "hint_string": "password"},
		}
	)
	var right_schema_dict_obj = DictionaryObject.new(
		{"Schema2": "", "_password2": ""}, 
		{
			"Schema2": {"hint": PROPERTY_HINT_ENUM, "hint_string": ",".join(databases)}, 
			"_password2": {"hint": PROPERTY_HINT_PASSWORD, "hint_string": "password"},
		}
	)
	var left_table_dict_obj = DictionaryObject.new(
		{"Table1": ""}, 
		{"Table1": {"hint": PROPERTY_HINT_ENUM, "hint_string": ""},}
	)
	var right_table_dict_obj = DictionaryObject.new(
		{"Table2": ""}, 
		{"Table2": {"hint": PROPERTY_HINT_ENUM, "hint_string": ""},}
	)
	var left_link_prop_dict_obj = DictionaryObject.new(
		{"LinkColumnName": ""},
		{"LinkColumnName": {"hint": PROPERTY_HINT_ENUM, "hint_string": ""}},
	)
	var right_link_prop_dict_obj = DictionaryObject.new(
		{"LinkColumnName": ""},
		{"LinkColumnName": {"hint": PROPERTY_HINT_ENUM, "hint_string": ""}},
	)
	var left_column_dict_obj = DictionaryObject.new(
		{"ColumnName": false}, {"ColumnName": {"usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY}}
	) # dummy obj
	left_column_dict_obj.set_meta("align", "vertical") # 垂直显示各属性
	var right_column_dict_obj = DictionaryObject.new(
		{"ColumnName": false}, {"ColumnName": {"usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY}}
	) # dummy obj
	right_column_dict_obj.set_meta("align", "vertical") # 垂直显示各属性
	left_schema_dict_obj.value_changed.connect(func(prop, new_val, _old_val):
		graph_node.push_redraw_slot_control(5, 2) # 如果不是通过点击的控件修改的dict obj，就需要重绘一下。这里偷个懒，直接重绘。
		match prop:
			"Schema1":
				data.set_meta("left_db", mgr.databases[new_val]["data_path"])
				var tables = mgr.databases[new_val]["tables"].keys()
				var hint = left_table_dict_obj._hint
				hint["Table1"] = {"hint": PROPERTY_HINT_ENUM, "hint_string": ",".join(tables)}
				left_table_dict_obj.reset_hint(hint)
				left_table_dict_obj._set("Table1", "", true) # 强制设置（可以避免值没变化导致没有发出信号）
			"_password1":
				data.set_meta("left_password", new_val)
	)
	right_schema_dict_obj.value_changed.connect(func(prop, new_val, _old_val):
		graph_node.push_redraw_slot_control(5, 3) # 如果不是通过点击的控件修改的dict obj，就需要重绘一下。这里偷个懒，直接重绘。
		match prop:
			"Schema2":
				data.set_meta("right_db", mgr.databases[new_val]["data_path"])
				var tables = mgr.databases[new_val]["tables"].keys()
				var hint = right_table_dict_obj._hint
				hint["Table2"] = {"hint": PROPERTY_HINT_ENUM, "hint_string": ",".join(tables)}
				right_table_dict_obj.reset_hint(hint)
				right_table_dict_obj._set("Table2", "", true) # 强制设置（可以避免值没变化导致没有发出信号）
			"_password2":
				data.set_meta("right_password", new_val)
	)
	left_table_dict_obj.value_changed.connect(func(prop, new_val, _old_val):
		graph_node.push_redraw_slot_control(6, 2)
		match prop:
			"Table1":
				data.set_meta("left_table", new_val)
				if new_val != "" and mgr.databases[left_schema_dict_obj._get("Schema1")]["tables"].has(new_val):
					var adata = {}
					var hints = {}
					var pk = ""
					for col in mgr.databases[left_schema_dict_obj._get("Schema1")]["tables"][new_val]["columns"]:
						if col["PK"]:
							pk = col["Column Name"]
						adata[col["Column Name"]] = true
						hints[col["Column Name"]] = {"hint": PROPERTY_HINT_NONE, "hint_string": "", "type": TYPE_BOOL}
					left_link_prop_dict_obj.reset_hint({"LinkColumnName": {"hint": PROPERTY_HINT_ENUM, 
						"hint_string": ",".join(adata.keys())}})
					left_link_prop_dict_obj._set("LinkColumnName", pk)
					left_column_dict_obj.reset_data(adata, hints)
				else:
					left_link_prop_dict_obj.reset_hint({"LinkColumnName": {"hint": PROPERTY_HINT_ENUM, 
						"hint_string": ""}})
					left_column_dict_obj.reset_data(
						{"ColumnName": false}, {"ColumnName": {"usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY}})
				graph_node.push_redraw_slot_control(7, 2)
				graph_node.push_redraw_slot_control(8, 2)
	)
	right_table_dict_obj.value_changed.connect(func(prop, new_val, _old_val):
		graph_node.push_redraw_slot_control(6, 3)
		match prop:
			"Table2":
				data.set_meta("right_table", new_val)
				if new_val != "" and mgr.databases[right_schema_dict_obj._get("Schema2")]["tables"].has(new_val):
					var adata = {}
					var hints = {}
					var pk = ""
					for col in mgr.databases[right_schema_dict_obj._get("Schema2")]["tables"][new_val]["columns"]:
						if col["PK"]:
							pk = col["Column Name"]
						adata[col["Column Name"]] = true
						hints[col["Column Name"]] = {"hint": PROPERTY_HINT_NONE, "hint_string": "", "type": TYPE_BOOL}
					right_link_prop_dict_obj.reset_hint({"LinkColumnName": {"hint": PROPERTY_HINT_ENUM, 
						"hint_string": ",".join(adata.keys())}})
					right_link_prop_dict_obj._set("LinkColumnName", pk)
					right_column_dict_obj.reset_data(adata, hints)
				else:
					right_link_prop_dict_obj.reset_hint({"LinkColumnName": {"hint": PROPERTY_HINT_ENUM, 
						"hint_string": ""}})
					right_column_dict_obj.reset_data(
						{"ColumnName": false}, {"ColumnName": {"usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY}})
				graph_node.push_redraw_slot_control(7, 3)
				graph_node.push_redraw_slot_control(8, 3)
	)
	var left_where_dict_obj = DictionaryObject.new({"Where": ""}, {"Where": {"hint": PROPERTY_HINT_NONE}})
	var left_order_dict_obj = DictionaryObject.new({"Order By": ""}, {"Order By": {"hint": PROPERTY_HINT_NONE}})
	var left_limit_dict_obj = DictionaryObject.new({"Offset": 0, "Limit": 1000})
	var right_where_dict_obj = DictionaryObject.new({"Where": ""}, {"Where": {"hint": PROPERTY_HINT_NONE}})
	var right_order_dict_obj = DictionaryObject.new({"Order By": ""}, {"Order By": {"hint": PROPERTY_HINT_NONE}})
	var right_limit_dict_obj = DictionaryObject.new({"Offset": 0, "Limit": 1000})
	var left_other_options = DictionaryObject.new({
		"Other Options": "", "show_column_name": false, "show_column_value": true, "font_size": 14, "processor": ""},
		{"Other Options": {"hint": PROPERTY_HINT_NONE, "usage": PROPERTY_USAGE_GROUP},
		"processor": {"hint": PROPERTY_HINT_MULTILINE_TEXT}},
	)
	var left_code_edit = CodeEdit.new()
	left_code_edit.text = "func process(column_name: String, value):\n\treturn value"
	left_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_code_edit.custom_minimum_size.y = 300
	left_code_edit.line_folding = true
	left_code_edit.gutters_draw_line_numbers = true
	left_code_edit.gutters_draw_fold_gutter = true
	left_code_edit.indent_automatic = true
	left_code_edit.auto_brace_completion_enabled = true
	left_code_edit.auto_brace_completion_highlight_matching = true
	left_code_edit.caret_blink = true
	left_code_edit.draw_tabs = true
	left_code_edit.syntax_highlighter = GDScriptSyntaxHighlighter.new()
	left_code_edit.text_changed.connect(func():
		left_other_options._set("processor", left_code_edit.text)
	)
	left_other_options.set_custom_display_control("processor", left_code_edit, func(new_val):
		if left_code_edit.text != new_val:
			left_code_edit.text = new_val
	, false)
	left_other_options.set_meta("align", "vertical")
	var right_other_options = DictionaryObject.new({
		"Other Options": "", "show_column_name": false, "show_column_value": true, "font_size": 14, "processor": ""},
		{"Other Options": {"hint": PROPERTY_HINT_NONE, "usage": PROPERTY_USAGE_GROUP},
		"processor": {"hint": PROPERTY_HINT_MULTILINE_TEXT}},
	)
	var right_code_edit = CodeEdit.new()
	right_code_edit.text = "func process(column_name: String, value):\n\treturn value"
	right_code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_code_edit.custom_minimum_size.y = 300
	right_code_edit.line_folding = true
	right_code_edit.gutters_draw_line_numbers = true
	right_code_edit.gutters_draw_fold_gutter = true
	right_code_edit.indent_automatic = true
	right_code_edit.auto_brace_completion_enabled = true
	right_code_edit.auto_brace_completion_highlight_matching = true
	right_code_edit.caret_blink = true
	right_code_edit.draw_tabs = true
	right_code_edit.syntax_highlighter = GDScriptSyntaxHighlighter.new()
	right_code_edit.text_changed.connect(func():
		right_other_options._set("processor", right_code_edit.text)
	)
	right_other_options.set_custom_display_control("processor", right_code_edit, func(new_val):
		if right_code_edit.text != new_val:
			right_code_edit.text = new_val
	, false)
	right_other_options.set_meta("align", "vertical")
	
	var btn_query = Button.new()
	btn_query.text = "query"
	btn_query.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_query.pressed.connect(on_link_node_query.bind(graph_node))
	btn_query.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	
	var hseparator = HSeparator.new()
	hseparator.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var separator = Control.new()
	separator.custom_minimum_size.y = 10
	var separator2 = Control.new()
	separator2.custom_minimum_size.y = 10
	
	var datas: Array[Array] = [
		[null, "Result"],
		[null, null, schema_dict_obj],
		[null, null, table_dict_obj],
		[null, null, link_prop_dict_obj],
		[null, null, hseparator],
		[null, null, left_schema_dict_obj, right_schema_dict_obj],
		[null, null, left_table_dict_obj, right_table_dict_obj],
		[null, null, left_link_prop_dict_obj, right_link_prop_dict_obj],
		[null, null, left_column_dict_obj, right_column_dict_obj],
		[null, null, left_where_dict_obj, right_where_dict_obj],
		[null, null, left_order_dict_obj, right_order_dict_obj],
		[null, null, left_limit_dict_obj, right_limit_dict_obj],
		[null, null, left_other_options, right_other_options],
		[null, null, separator],
		[null, null, btn_query],
		[null, null, separator2]
	]
	graph_node.datas = datas
	graph_node.title = "Link"
	graph_node.add_theme_stylebox_override("panel", SB_PANEL)
	graph_node.add_theme_stylebox_override("panel_selected", SB_PANEL_SELECTED)
	graph_node.add_theme_stylebox_override("titlebar", SB_SELECT_TITLEBAR)
	graph_node.add_theme_stylebox_override("titlebar_selected", SB_SELECT_TITLEBAR_SELECTED)
	graph_node.ready.connect(func():
		graph_node.set_slot_type_right(0, 0) # Result's type is 0
		graph_node.size.x = 1100
		graph_node.selected = true
	)
	graph_node.set_meta("type", "Link")
	graph_node.set_meta("node", true)
	graph_node.delete_request.connect(func():
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
	
## TODO FIXME NODE类型的怎么保存？
func extract_table_data_call(v, columns):
	if v is DictionaryObject:
		var arr = []
		for i in columns.size():
			arr.push_back(v._get_by_index(i))
		return arr
	return v
	
#func _shortcut_input(event: InputEvent) -> void:
	#if not visible:
		#return
	#if SHORTCUT_COPY.matches_event(event):
		#var selected_nodes_params = get_nodes_params(true)
		#if selected_nodes_params.is_empty():
			#return
		#copied_nodes = {
			#"data": selected_nodes_params,
			#"connections": get_connections_only_selected(),
		#}
		#get_viewport().set_input_as_handled()
	#elif SHORTCUT_PASTE.matches_event(event):
		#if copied_nodes.is_empty():
			#return
		#_load_nodes(copied_nodes.data, copied_nodes.connections, Vector2(40, 40), true, true)
		#for i in copied_nodes.data:
			#copied_nodes.data[i].position_offset += Vector2(40, 40)
		#get_viewport().set_input_as_handled()
		
func get_connections_only_selected():
	var ret = []
	var conns = graph_edit.get_connection_list()
	for c in conns:
		if graph_edit.get_node(str(c.from_node)).selected and\
		graph_edit.get_node(str(c.to_node)).selected:
			c.from_node = (c.from_node as String).validate_node_name()
			c.to_node = (c.to_node as String).validate_node_name()
			ret.push_back(c)
	return ret
	
func get_nodes_params(only_selected = false):
	var all_data = {}
	for graph_node in graph_edit.get_children():
		if not graph_node is GraphNode:
			continue
		if only_selected and not graph_node.selected:
			continue
		var type = graph_node.get_meta("type", "")
		var data = {}
		match type:
			"Select", "Left Join", "Delete":
				for arr in graph_node.datas:
					for i in arr:
						if i is DictionaryObject:
							data.merge((i as DictionaryObject).get_data())
			"Result":
				var table = graph_node.datas[0][0].get_child(0)
				data["is_union_all"] = graph_node.get_meta("is_union_all")
				data["join_conds"] = graph_node.get_meta("join_conds")
				data["columns"] = table.get_meta("columns")
				data["table_datas"] = table.datas.map(extract_table_data_call.bind(data["columns"]))
				data["v_scroll_height"] = table.v_scroll_height
			"Insert":
				var schema_dict_obj: DictionaryObject = graph_node.datas[0][2]
				var table_dict_obj: DictionaryObject = graph_node.datas[1][2]
				var fields_dict_obj = graph_node.datas[2][2]
				data["Schema"] = schema_dict_obj._get("Schema")
				data["_password"] = schema_dict_obj._get("_password")
				data["Table"] = table_dict_obj._get("Table")
				data["_alias"] = table_dict_obj._get("_alias")
				data["Fields"] = {} if fields_dict_obj == null else fields_dict_obj.get_data()
			"Update":
				var schema_dict_obj: DictionaryObject = graph_node.datas[0][2]
				var table_dict_obj: DictionaryObject = graph_node.datas[1][2]
				var fields_dict_obj = graph_node.datas[2][2]
				var where_dict_obj: DictionaryObject = graph_node.datas[3][2]
				data["Schema"] = schema_dict_obj._get("Schema")
				data["_password"] = schema_dict_obj._get("_password")
				data["Table"] = table_dict_obj._get("Table")
				data["_alias"] = table_dict_obj._get("_alias")
				data["Fields"] = {} if fields_dict_obj == null else fields_dict_obj.get_data()
				data["Where"] = where_dict_obj._get("Where")
			"SQL":
				var code_editor = graph_node.datas[1][2] as CodeEdit
				data["sql"] = code_editor.text
			"Link":
				var schema_dict_obj: DictionaryObject = graph_node.datas[1][2]
				var table_dict_obj: DictionaryObject = graph_node.datas[2][2]
				var link_prop_dict_obj: DictionaryObject = graph_node.datas[3][2]
				var left_schema_dict_obj: DictionaryObject = graph_node.datas[5][2]
				var right_schema_dict_obj: DictionaryObject = graph_node.datas[5][3]
				var left_table_dict_obj: DictionaryObject = graph_node.datas[6][2]
				var right_table_dict_obj: DictionaryObject = graph_node.datas[6][3]
				var left_link_prop_dict_obj: DictionaryObject = graph_node.datas[7][2]
				var right_link_prop_dict_obj: DictionaryObject = graph_node.datas[7][3]
				var left_column_dict_obj: DictionaryObject = graph_node.datas[8][2]
				var right_column_dict_obj: DictionaryObject = graph_node.datas[8][3]
				var left_where_dict_obj: DictionaryObject = graph_node.datas[9][2]
				var right_where_dict_obj: DictionaryObject = graph_node.datas[9][3]
				var left_order_dict_obj: DictionaryObject = graph_node.datas[10][2]
				var right_order_dict_obj: DictionaryObject = graph_node.datas[10][3]
				var left_limit_dict_obj: DictionaryObject = graph_node.datas[11][2]
				var right_limit_dict_obj: DictionaryObject = graph_node.datas[11][3]
				var left_other_options: DictionaryObject = graph_node.datas[12][2]
				var right_other_options: DictionaryObject = graph_node.datas[12][3]
				
				data["link_db"] = schema_dict_obj._get("Schema")
				data["link_password"] = schema_dict_obj._get("_password")
				data["link_table"] = table_dict_obj._get("Table")
				data["right_columns"] = table_dict_obj._get("Right Columns")
				data["link_left_col"] = link_prop_dict_obj._get("Left")
				data["link_right_col"] = link_prop_dict_obj._get("Right")
				
				data["left_db"] = left_schema_dict_obj._get("Schema1")
				data["left_password"] = left_schema_dict_obj._get("_password1")
				data["left_table"] = left_table_dict_obj._get("Table1")
				data["left_link_col"] = left_link_prop_dict_obj._get("LinkColumnName")
				data["left_cols_shown"] = left_column_dict_obj.get_data().duplicate()
				data["left_where"] = left_where_dict_obj._get("Where")
				data["left_order_by"] = left_order_dict_obj._get("Order By")
				data["left_offset"] = left_limit_dict_obj._get("Offset")
				data["left_limit"] = left_limit_dict_obj._get("Limit")
				data["left_show_column_name"] = left_other_options._get("show_column_name")
				data["left_show_column_value"] = left_other_options._get("show_column_value")
				data["left_font_size"] = left_other_options._get("font_size")
				data["left_processor"] = left_other_options._get("processor")
				
				data["right_db"] = right_schema_dict_obj._get("Schema2")
				data["right_password"] = right_schema_dict_obj._get("_password2")
				data["right_table"] = right_table_dict_obj._get("Table2")
				data["right_link_col"] = right_link_prop_dict_obj._get("LinkColumnName")
				data["right_cols_shown"] = right_column_dict_obj.get_data().duplicate()
				data["right_where"] = right_where_dict_obj._get("Where")
				data["right_order_by"] = right_order_dict_obj._get("Order By")
				data["right_offset"] = right_limit_dict_obj._get("Offset")
				data["right_limit"] = right_limit_dict_obj._get("Limit")
				data["right_show_column_name"] = right_other_options._get("show_column_name")
				data["right_show_column_value"] = right_other_options._get("show_column_value")
				data["right_font_size"] = right_other_options._get("font_size")
				data["right_processor"] = right_other_options._get("processor")
			_:
				continue
				
		all_data[graph_node.name.validate_node_name()] = { # validate一下，不然会存在@符号，再次设置name的时候会被替换为下划线
			"type": type,
			"params": data,
			"size": graph_node.size if graph_node.window_size == Vector2.ZERO else graph_node.size.min(graph_node.window_size),
			"position_offset": graph_node.position_offset,
			"enabled": graph_node.enabled,
		}
		
	return all_data
	
func load_graph_file(path):
	var config = ImprovedConfigFile.new()
	config.load(path)
	var nodes = config.get_value("data", "nodes", {})
	var connections = config.get_value("data", "connections", [])
	
	# genarate nodes
	_load_nodes(nodes, connections, Vector2.ZERO, false)
	
	set_meta("type", "sql_graph")
	set_meta("is_file", true)
	set_meta("file_path", path)
	set_meta("file_name", path.get_file())
	
## genarate nodes
func _load_nodes(nodes: Dictionary, connections: Array, pos_offset: Vector2, auto_name: bool, select_all = false):
	var node_name_map = {} # 旧name => 新name
	for node_name in nodes:
		var type = nodes[node_name]["type"]
		var params = nodes[node_name]["params"]
		var asize = nodes[node_name]["size"]
		var position_offset = nodes[node_name]["position_offset"] + pos_offset
		var a_name = "" if auto_name else node_name
		var node = null
		match type:
			"Select":
				node = await add_select_node(params["Schema"], params["Table"], params["Fields"], 
					params["Where"], params["Group By"], params["Order By"], params["Offset"], 
					params["Limit"], params["_alias"], params["_password"],
					asize, position_offset, a_name, false)
			"Left Join":
				node = await add_left_join_node(params["Schema"], params["_password"], params["Table"],
					params["_alias"], params["On"], asize, position_offset, a_name)
			"Result":
				node = await add_table_node(params["columns"], params["table_datas"], params["is_union_all"],
					params["join_conds"], params.get("v_scroll_height", 0), asize, position_offset, a_name)
			"Insert":
				node = await add_insert_node(params["Schema"], params["_password"], params["Table"],
					params["Fields"], asize, position_offset, a_name)
			"Update":
				node = await add_update_node(params["Schema"], params["_password"], params["Table"],
					params["Fields"], params["Where"], asize, position_offset, a_name)
			"Delete":
				node = await add_delete_node(params["Schema"], params["_password"], params["Table"],
					params["Where"], asize, position_offset, a_name)
			"SQL":
				node = await add_sql_node(params["sql"], asize, position_offset, a_name, false)
			"Link":
				node = await add_link_node(params["link_db"], params["link_password"], params["link_table"],
					params["right_columns"], params["link_left_col"], params["link_right_col"],
					params["left_db"], params["left_password"], params["left_table"], params["left_link_col"],
					params["left_cols_shown"], params["left_where"], params["left_order_by"], params["left_offset"],
					params["left_limit"], params["left_show_column_name"], params["left_show_column_value"],
					params["left_font_size"], params["left_processor"],
					params["right_db"], params["right_password"], params["right_table"], params["right_link_col"],
					params["right_cols_shown"], params["right_where"], params["right_order_by"], params["right_offset"],
					params["right_limit"], params["right_show_column_name"], params["right_show_column_value"],
					params["right_font_size"], params["right_processor"],
					asize, position_offset, a_name, false)
					
		node_name_map[node_name] = node.name
		
	# make connections
	for info in connections:
		var from = node_name_map[info["from_node"]]
		var to = node_name_map[info["to_node"]]
		_on_graph_edit_connection_request(
			from, info["from_port"], to, info["to_port"])
			
	# enable会影响connection对象间的数据关联，最好最后设置
	for node_name in nodes:
		var a_node_name = node_name_map[node_name]
		var node = graph_edit.get_node(str(a_node_name)) as GraphNode
		node.enabled = nodes[node_name]["enabled"]
		
	if select_all:
		for i in node_name_map:
			graph_edit.get_node(str(node_name_map[i])).selected = true
			
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
		
func set_input(to_port: int, release_position: Vector2, to_node: GraphNode):
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
			
	if input_node:
		#input_node.set_slot_type_right(from_port, to_node.get_slot_type_left(to_port))
		handle_input_node(input_node, to_node.name, from_port, to_port, release_position, xenophobic)
	
## 获取接收输入数据的节点
func get_to_nodes(node: GraphNode, type: String = "") -> Array[GraphNode]:
	var ret: Array[GraphNode] = []
	for info in graph_edit.get_connection_list():
		if info["from_node"] == node.name:
			var to_node = graph_edit.get_node(str(info["to_node"])) as GraphNode
			if type == "" or type == to_node.get_meta("type"):
				ret.push_back(to_node)
	return ret
	
## 获取数据来源的节点
func get_from_nodes(node: GraphNode, type: String = "") -> Array[GraphNode]:
	var ret: Array[GraphNode] = []
	for info in graph_edit.get_connection_list():
		if info["to_node"] == node.name:
			var from_node = graph_edit.get_node(str(info["from_node"])) as GraphNode
			if type == "" or type == from_node.get_meta("type"):
				ret.push_back(from_node)
	return ret
	
# Select 执行
# node: 被点击的select节点
func on_select_node_query(node: GraphNode, log_history: bool):
	#unselect_all_node()
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
		var dao = source_node.get_meta("base_dao") as BaseDao
		mgr.request_user_enter_password.emit(dao.get_db(), dao.get_table(), dao.get_password(), func():
			var begin_time = Time.get_unix_time_from_system()
			var action = dao.get_query_cmd()
			var ret = dao.query()
			if ret == null:
				mgr.add_log_history.emit("Err", begin_time, action, "something wrong")
				return
				
			if log_history:
				mgr.add_log_history.emit("OK", begin_time, action, 
					"%d row(s) returned" % (ret.get_data().size()), ret.get_cost_time()) # 去掉表头
					
			var update_result = false
			if from_to_map.has(source_node.name):
				for to in from_to_map[source_node.name]:
					var to_node = graph_edit.get_node(str(to))
					if to_node.get_meta("type") == "Result":
						if to_node.enabled:
							gen_table_node(ret.get_head(), ret.get_data(), dao.is_union_all(), dao.get_left_join_conds(), 0, to_node)
							update_result = true
						else:
							_on_graph_edit_disconnection_request(source_node.name, 0, to_node.name, 0)
						
			if not update_result:
				var table_node = gen_table_node(ret.get_head(), ret.get_data(), dao.is_union_all(), dao.get_left_join_conds())
				graph_edit.add_child(table_node)
				table_node.position_offset = source_node.position_offset + Vector2(source_node.size.x + 20, 0)
				_on_graph_edit_connection_request(source_node.name, 0, table_node.name, 0)
		)
		
	mark_modified()
	
# Insert 执行
# node: 被点击的insert节点
func on_insert_node_query(node: GraphNode):
	var modified_datas = node.datas[2][2]
	if modified_datas == null:
		mgr.create_accept_dialog("Nothing changed")
		return
		
	modified_datas = (modified_datas as DictionaryObject).get_modified_new_value()
	if modified_datas.is_empty():
		mgr.create_accept_dialog("Nothing changed")
		return
		
	var dao = node.get_meta("base_dao") as BaseDao
	dao.values(modified_datas)
	var action = dao.get_query_cmd()
	mgr.create_confirmation_dialog("Please confirm:\n" + action, func():
		mgr.request_user_enter_password.emit(dao.get_db(), dao.get_table(), dao.get_password(), func():
			var begin_time = Time.get_unix_time_from_system()
			var ret = dao.query()
			if ret == null:
				mgr.add_log_history.emit("Err", begin_time, action, "something wrong")
				return
				
			if not ret.ok():
				mgr.add_log_history.emit("Err", begin_time, action, ret.get_err(), ret.get_cost_time())
				return
				
			mgr.add_log_history.emit("OK", begin_time, action, 
				"%d row(s) affected" % (ret.get_affected_rows()), ret.get_cost_time())
		)
	)
	
# Update 执行
# node: 被点击的update节点
func on_update_node_query(node: GraphNode):
	var modified_datas = node.datas[2][2]
	if modified_datas == null:
		mgr.create_accept_dialog("Nothing changed")
		return
		
	modified_datas = (modified_datas as DictionaryObject).get_modified_new_value()
	if modified_datas.is_empty():
		mgr.create_accept_dialog("Nothing changed")
		return
		
	var dao = node.get_meta("base_dao") as BaseDao
	dao.sets(modified_datas)
	var action = dao.get_query_cmd()
	mgr.create_confirmation_dialog("Please confirm:\n" + action, func():
		mgr.request_user_enter_password.emit(dao.get_db(), dao.get_table(), dao.get_password(), func():
			var begin_time = Time.get_unix_time_from_system()
			var ret = dao.query()
			if ret == null:
				mgr.add_log_history.emit("Err", begin_time, action, "something wrong")
				return
				
			if not ret.ok():
				mgr.add_log_history.emit("Err", begin_time, action, ret.get_err(), ret.get_cost_time())
				return
				
			mgr.add_log_history.emit("OK", begin_time, action, 
				"%d row(s) affected" % (ret.get_affected_rows()), ret.get_cost_time())
		)
	)
	
# Delete 执行
# node: 被点击的delete节点
func on_delete_node_query(node: GraphNode):
	var dao = node.get_meta("base_dao") as BaseDao
	var action = dao.get_query_cmd()
	mgr.create_confirmation_dialog("Please confirm:\n" + action, func():
		mgr.request_user_enter_password.emit(dao.get_db(), dao.get_table(), dao.get_password(), func():
			var begin_time = Time.get_unix_time_from_system()
			var ret = dao.query()
			if ret == null:
				mgr.add_log_history.emit("Err", begin_time, action, "something wrong")
				return
				
			if not ret.ok():
				mgr.add_log_history.emit("Err", begin_time, action, ret.get_err(), ret.get_cost_time())
				return
				
			mgr.add_log_history.emit("OK", begin_time, action, 
				"%d row(s) affected" % (ret.get_affected_rows()), ret.get_cost_time())
		)
	)
	
# 自定义SQL执行
# node: 被点击的sql节点
func on_sql_node_query(node: GraphNode, log_history: bool):
	#unselect_all_node()
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
	_get_final_source(node.name, from_to_map, arr_source_node, "SQL")
	
	# 每个源头都要query
	for node_name in arr_source_node:
		var source_node = graph_edit.get_node(str(node_name)) as GraphNode # 一个sql node
		var sql = (node.datas[1][2] as CodeEdit).text
		var dao = SQLParser.parse_to_dao(sql)
		mgr.request_user_enter_password.emit(dao.get_db(), dao.get_table(), dao.get_password(), func():
			var action = dao.get_query_cmd()
			var begin_time = Time.get_unix_time_from_system()
			var query_ret = dao.query()
			if query_ret == null:
				mgr.add_log_history.emit("Err", begin_time, action, "something wrong")
				return
				
			var ret: QueryResult = null
			if dao.get_cmd().begins_with("select"):
				ret = query_ret
			else:
				var gen_dict = func(s):
					return {"select_name": s, "Column Name": s, "field_as": s, 
						"is_field": false, "table_alias": "", "db_path": "", 
						"table_name": "", "hint": PROPERTY_HINT_NONE, 
						"Hint String": "", "Data Type": TYPE_NIL,
						"Default(Expression)": ""}
				ret = QueryResult.new()
				ret._has_head = true
				ret._data = [
					["err", "affected_rows", "warnings", "last_insert_id", 
					"generated_keys", "cost_time"].map(gen_dict),
					[
						query_ret.get_err(),
						query_ret.get_affected_rows(),
						query_ret.get_warnings(),
						query_ret.get_last_insert_id(),
						query_ret.get_generated_keys(),
						query_ret.get_cost_time(),
					]
				]
				
			var update_result = false
			if from_to_map.has(source_node.name):
				for to in from_to_map[source_node.name]:
					var to_node = graph_edit.get_node(str(to))
					if to_node.get_meta("type") == "Result":
						if to_node.enabled:
							gen_table_node(ret.get_head(), ret.get_data(), dao.is_union_all(), dao.get_left_join_conds(), 0, to_node)
							update_result = true
						else:
							_on_graph_edit_disconnection_request(source_node.name, 0, to_node.name, 0)
							
			if not update_result:
				var table_node = gen_table_node(ret.get_head(), ret.get_data(), dao.is_union_all(), dao.get_left_join_conds())
				graph_edit.add_child(table_node)
				table_node.position_offset = source_node.position_offset + Vector2(source_node.size.x + 20, 0)
				_on_graph_edit_connection_request(source_node.name, 0, table_node.name, 0)
				
			if log_history:
				if dao.get_cmd().begins_with("select"):
					mgr.add_log_history.emit("OK", begin_time, action, 
						"%d row(s) returned" % (query_ret.get_data().size()), 
						ret.get_cost_time()) # 去掉表头
				else:
					mgr.add_log_history.emit("OK", begin_time, action, 
						"%d row(s) affected" % (query_ret.get_affected_rows()), 
						query_ret.get_cost_time())
						
		)
		
	mark_modified()
	
func on_link_node_query(node: GraphNode):
	# 拉取已经存在的关联数据
	var data = node.get_meta("data")
	#var schema_dict_obj: DictionaryObject = node.datas[1][2]
	var table_dict_obj: DictionaryObject = node.datas[2][2]
	var link_prop_dict_obj: DictionaryObject = node.datas[3][2]
	#var left_schema_dict_obj: DictionaryObject = node.datas[5][2]
	#var right_schema_dict_obj: DictionaryObject = node.datas[5][3]
	#var left_table_dict_obj: DictionaryObject = node.datas[6][2]
	#var right_table_dict_obj: DictionaryObject = node.datas[6][3]
	var left_link_prop_dict_obj: DictionaryObject = node.datas[7][2]
	var right_link_prop_dict_obj: DictionaryObject = node.datas[7][3]
	var left_column_dict_obj: DictionaryObject = node.datas[8][2]
	var right_column_dict_obj: DictionaryObject = node.datas[8][3]
	var left_where_dict_obj: DictionaryObject = node.datas[9][2]
	var right_where_dict_obj: DictionaryObject = node.datas[9][3]
	var left_order_dict_obj: DictionaryObject = node.datas[10][2]
	var right_order_dict_obj: DictionaryObject = node.datas[10][3]
	var left_limit_dict_obj: DictionaryObject = node.datas[11][2]
	var right_limit_dict_obj: DictionaryObject = node.datas[11][3]
	var left_other_options: DictionaryObject = node.datas[12][2]
	var right_other_options: DictionaryObject = node.datas[12][3]
	
	mgr.request_user_enter_password.emit(
	data.get_meta("link_db", ""),
	data.get_meta("link_table", ""),
	data.get_meta("link_password", ""), 
	func():
		var begin_time = Time.get_unix_time_from_system()
		var link_datas_dao = BaseDao.new()
		var link_query_ret = (
			link_datas_dao
			.use_db(data.get_meta("link_db", ""))
			.set_password(data.get_meta("link_password", ""))
			.select("%s, list(%s)" % [
				link_prop_dict_obj._get("Left"), link_prop_dict_obj._get("Right")], true)
			.from(data.get_meta("link_table", ""))
			.group_by(link_prop_dict_obj._get("Left"))
			.query()
		)
		var action = link_datas_dao.get_query_cmd()
		if link_query_ret == null:
			mgr.add_log_history.emit("Err", begin_time, action, "something wrong")
			return
		else:
			mgr.add_log_history.emit("OK", begin_time, action, 
				"%d row(s) returned" % (link_query_ret.get_data().size()), 
				link_query_ret.get_cost_time()) # 去掉表头
			
		var link_datas = link_query_ret.get_data()
		var link_map = {}
		for adata in link_datas:
			link_map[adata[0]] = adata[1]
			
		# 拉取左表的数据
		mgr.request_user_enter_password.emit(
		data.get_meta("left_db", ""),
		data.get_meta("left_table", ""),
		data.get_meta("left_password", ""), 
		func():
			var begin_time_2 = Time.get_unix_time_from_system()
			var left_datas_dao = BaseDao.new()
			var left_select = left_column_dict_obj.get_data().keys().map(func(v):
				return v if left_column_dict_obj.get_data()[v] else ""
			).filter(func(v): return not v.is_empty())
			var left_query_ret = (
				left_datas_dao
				.use_db(data.get_meta("left_db", ""))
				.set_password(data.get_meta("left_password", ""))
				.select("*", true)
				.from(data.get_meta("left_table", ""))
				.set_where(left_where_dict_obj._get("Where"))
				.order_by_str(left_order_dict_obj._get("Order By"))
				.limit(left_limit_dict_obj._get("Offset"), left_limit_dict_obj._get("Limit"))
				.query()
			)
			var action2 = left_datas_dao.get_query_cmd()
			if left_query_ret == null:
				mgr.add_log_history.emit("Err", begin_time_2, action2, "something wrong")
				return
			else:
				mgr.add_log_history.emit("OK", begin_time_2, action2, 
					"%d row(s) returned" % (left_query_ret.get_data().size()), 
					left_query_ret.get_cost_time()) # 去掉表头
				
			# 拉取右表的数据
			mgr.request_user_enter_password.emit(
			data.get_meta("right_db", ""),
			data.get_meta("right_table", ""),
			data.get_meta("right_password", ""), 
			func():
				var begin_time_3 = Time.get_unix_time_from_system()
				var right_datas_dao = BaseDao.new()
				var right_select = right_column_dict_obj.get_data().keys().map(func(v):
					return v if right_column_dict_obj.get_data()[v] else ""
				).filter(func(v): return not v.is_empty())
				var right_query_ret = (
					right_datas_dao
					.use_db(data.get_meta("right_db", ""))
					.set_password(data.get_meta("right_password", ""))
					.select("*", true)
					.from(data.get_meta("right_table", ""))
					.set_where(right_where_dict_obj._get("Where"))
					.order_by_str(right_order_dict_obj._get("Order By"))
					.limit(right_limit_dict_obj._get("Offset"), right_limit_dict_obj._get("Limit"))
					.query()
				)
				var action3 = right_datas_dao.get_query_cmd()
				if right_query_ret == null:
					mgr.add_log_history.emit("Err", begin_time_3, action3, "something wrong")
					return
				else:
					mgr.add_log_history.emit("OK", begin_time_3, action3, 
						"%d row(s) returned" % (right_query_ret.get_data().size()), 
						right_query_ret.get_cost_time()) # 去掉表头
						
				# 构造表格数据
				var find_col_index = func(columns: Array, col_name: String):
					for i in columns.size():
						if columns[i]["Column Name"] == col_name:
							return i
					return -1
				var tdatas = []
				var left_columns = left_query_ret.get_head()
				var left_datas = left_query_ret.get_data()
				var left_key_index = find_col_index.call(left_columns, left_link_prop_dict_obj._get("LinkColumnName"))
				assert(left_key_index != -1, "Error of left_key_index.")
				var right_columns = right_query_ret.get_head()
				var right_datas = right_query_ret.get_data()
				var right_key_index = find_col_index.call(right_columns, right_link_prop_dict_obj._get("LinkColumnName"))
				assert(right_key_index != -1, "Error of right_key_index.")
				var detail_panel_scene = preload("res://addons/gdsql/detail_panel.tscn")
				for row: Array in left_datas:
					# 包含左数据、右数据和按钮
					var a_row = []
					
					# 左数据
					var left_data = {}
					var left_id = null
					for i in row.size():
						if left_columns[i]["Column Name"] == left_link_prop_dict_obj._get("LinkColumnName"):
							left_id = row[i]
						if left_columns[i]["Column Name"] in left_select:
							left_data[left_columns[i]["Column Name"]] = row[i]
					var left_panel = detail_panel_scene.instantiate()
					left_panel.show_check_box = false
					left_panel.ready.connect(func():
						left_panel.show_column_name = left_other_options._get("show_column_name")
						left_panel.show_column_value = left_other_options._get("show_column_value")
						left_panel.font_size = left_other_options._get("font_size")
						left_panel.processor = left_other_options._get("processor")
						left_panel.set_datas(left_data)
					)
					a_row.push_back(left_panel)
					
					# 右数据
					var grid = GridContainer.new()
					grid.columns = table_dict_obj._get("Right Columns")
					a_row.push_back(grid)
					
					for right_row: Array in right_datas:
						var right_data = {}
						var right_id = null
						for i in right_row.size():
							if right_columns[i]["Column Name"] == right_link_prop_dict_obj._get("LinkColumnName"):
								right_id = right_row[i]
							if right_columns[i]["Column Name"] in right_select:
								right_data[right_columns[i]["Column Name"]] = right_row[i]
						var right_panel = detail_panel_scene.instantiate()
						assert(left_id != null and right_id != null, "Cannot find left_id or right_id.")
						right_panel.set_meta("left_id", left_id)
						right_panel.set_meta("right_id", right_id)
						right_panel.show_check_box = true
						right_panel.status = "normal_checked" if link_map.has(row[left_key_index]) and \
							right_row[right_key_index] in link_map[row[left_key_index]] else "normal_unchecked"
						right_panel.ready.connect(func():
							right_panel.show_column_name = right_other_options._get("show_column_name")
							right_panel.show_column_value = right_other_options._get("show_column_value")
							right_panel.font_size = right_other_options._get("font_size")
							right_panel.processor = right_other_options._get("processor")
							right_panel.set_datas(right_data)
						)
						grid.add_child(right_panel)
						
					# 按钮
					var vbox = VBoxContainer.new()
					a_row.push_back(vbox)
					
					var btn_check_all = Button.new()
					vbox.add_child(btn_check_all)
					btn_check_all.text = tr("Select All")
					btn_check_all.pressed.connect(func():
						for detail_panel in grid.get_children():
							detail_panel.check_box.button_pressed = true
					)
					
					var btn_cancel_all = Button.new()
					vbox.add_child(btn_cancel_all)
					btn_cancel_all.text = tr("Deselect All")
					btn_cancel_all.pressed.connect(func():
						for detail_panel in grid.get_children():
							detail_panel.check_box.button_pressed = false
					)
					
					var btn_revert = Button.new()
					vbox.add_child(btn_revert)
					btn_revert.text = tr("Revert")
					btn_revert.pressed.connect(func():
						for detail_panel in grid.get_children():
							detail_panel.revert()
					)
					
					var btn_apply = Button.new()
					vbox.add_child(btn_apply)
					btn_apply.text = tr("Apply")
					btn_apply.pressed.connect(func():
						var daos: Array[BaseDao] = []
						for detail_panel in grid.get_children():
							var change_status = detail_panel.get_change_status()
							if change_status == "add":
								var dao = BaseDao.new()
								dao.auto_commit(false)
								(
									dao.use_db(data.get_meta("link_db", ""))
									.set_password(data.get_meta("link_password", ""))
									.insert_into(data.get_meta("link_table", ""))
									.values({
										link_prop_dict_obj._get("Left"): detail_panel.get_meta("left_id"),
										link_prop_dict_obj._get("Right"): detail_panel.get_meta("right_id"),
									})
								)
								daos.push_back(dao)
							elif change_status == "delete":
								var wrap_value = func(v):
									if v is String:
										return "'" + v.c_escape() + "'"
									return v
								var dao = BaseDao.new()
								dao.auto_commit(false)
								(
									dao.use_db(data.get_meta("link_db", ""))
									.set_password(data.get_meta("link_password", ""))
									.delete_from(data.get_meta("link_table", ""))
									.where("%s == %s and %s == %s" % [
										link_prop_dict_obj._get("Left"), wrap_value.call(detail_panel.get_meta("left_id")),
										link_prop_dict_obj._get("Right"), wrap_value.call(detail_panel.get_meta("right_id")),
									])
								)
								daos.push_back(dao)
						# 弹对话框
						var arr: Array[Array] = [["Please confirm:"]]
						var table_2 = preload("res://addons/gdsql/table.tscn").instantiate()
						table_2.ratios = [15.0, 0.2, 2.0, 10.0, 8.0] as Array[float]
						table_2.columns = ["#", "action", "status"]
						var datas = []
						var k = 0
						for i: BaseDao in daos:
							var data_row = [k+1, i.get_query_cmd()]
							var pb = ProgressBar.new()
							data_row.push_back(pb)
							datas.push_back(data_row)
							k += 1
						table_2.datas = datas
						table_2.show_menu = false
						table_2.support_delete_row = false
						table_2.ready.connect(func():
							table_2.get_parent_control().size_flags_vertical = Control.SIZE_EXPAND_FILL
						, CONNECT_ONE_SHOT)
						arr.push_back([table_2])
						
						# 执行成功的项目标绿进度100%；执行失败的项目标红。
						var dialog_ref: Array[ConfirmationDialog] = []
						var confirmed = func():
							if dialog_ref[0].ok_button_text == "close":
								return [false, false] # 不涉及defered函数，所以第二个参数传的没什么意义
								
							# 该按钮名称是回滚，则抛弃修改
							if dialog_ref[0].ok_button_text == "Revert":
								daos[0].discard()
								on_link_node_query(node)
								mgr._clear_custom_dialog(dialog_ref[0])
								return [false, false] # 不涉及defered函数，所以第二个参数传的没什么意义
								
							# sql query
							var failed = false
							var index = -1
							for i: BaseDao in daos:
								index += 1
								if (table_2.datas[index][2] as ProgressBar).value == 100:
									continue
								var begin_time_4 = Time.get_unix_time_from_system()
								var ret = i.query()
								if ret != null:
									if ret.ok():
										# log and UI
										mgr.add_log_history.emit("OK", begin_time_4, i.get_query_cmd(), 
											"%d row(s) affected" % ret.get_affected_rows(), ret.get_cost_time())
										(table_2.datas[index][2] as ProgressBar).value = 100
										(table_2.datas[index][2] as ProgressBar).modulate = Color.GREEN
									else:
										mgr.add_log_history.emit("Err", begin_time_4, i.get_query_cmd(), 
											ret.get_err(), ret.get_cost_time())
										(table_2.datas[index][2] as ProgressBar).modulate = Color.RED
										failed = true
										break
								else:
									mgr.add_log_history.emit("Err", begin_time_4, i.get_query_cmd(), "something wrong")
									(table_2.datas[index][2] as ProgressBar).modulate = Color.RED
									
							# 失败
							if failed:
								dialog_ref[0].ok_button_text = "Revert"
							else:
								daos[0].commit()
								dialog_ref[0].ok_button_text = "close"
								for detail_panel in grid.get_children():
									detail_panel.commit()
									
							# true：让该页面不关闭
							return [true, false] # 不涉及defered函数，所以第二个参数传的没什么意义
							
						# 对话框关闭时要执行的方法
						var defered = func(_confirmed, _dummy):
							table_2.queue_free()
							
						var dialog = mgr.create_custom_dialog(arr, confirmed, Callable(), defered, 0.5)
						dialog_ref.push_back(dialog)
						dialog.ok_button_text = "execute"
						var btn_close_refresh = dialog.add_button("close and refresh", true, "close_and_refresh")
						btn_close_refresh.tooltip_text = "Refresh the table. Modifications that not have been applied will be discarded."
						btn_close_refresh.disabled = get_from_nodes(node, "Link").filter(func(v):
							return v.enabled
						).is_empty() # 如果这个表格没有关联Link节点，就无法刷新
						if btn_close_refresh.disabled:
							btn_close_refresh.tooltip_text += "\n[Tip]This button is disabled because this Result-node is "\
								+ "not connected to a Link-node or the Link-node is not enabled."
						dialog.custom_action.connect(func(custom_action):
							if custom_action == "close_and_refresh":
								var onclose = func ():
									on_link_node_query(node)
									mgr._clear_custom_dialog(dialog)
									
								if btn_apply.disabled:
									onclose.call()
								else:
									mgr.create_confirmation_dialog("You have some modifications that have not been executed.\n"\
										+ "If you refresh, these modifications will be discarded. \nAre you sure to refresh the table?"
										, onclose)
						)
					)
					
					tdatas.push_back(a_row)
					
				# 生成table node然后连接
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
				_get_final_source(node.name, from_to_map, arr_source_node, "Link")
				
				# 每个源头都要query
				var gen_dict = func(s):
					return {"select_name": s, "Column Name": s, "is_field": false, "table_alias": "",
						"db_path": "", "table_name": "", "hint": PROPERTY_HINT_NONE, "Hint String": "",
						"field_as": s, "name_4_computing": s}
				var head = [gen_dict.call("Left"), gen_dict.call("Right"), gen_dict.call("Action")]
				for node_name in arr_source_node:
					var source_node = graph_edit.get_node(str(node_name)) as GraphNode # 一个link node
					var update_result = false
					if from_to_map.has(source_node.name):
						for to in from_to_map[source_node.name]:
							var to_node = graph_edit.get_node(str(to))
							if to_node.get_meta("type") == "Result":
								if to_node.enabled:
									gen_table_node(head, tdatas, true, [], 0, to_node)
									update_result = true
								else:
									_on_graph_edit_disconnection_request(source_node.name, 0, to_node.name, 0)
								
					if not update_result:
						var table_node = gen_table_node(head, tdatas, true, [])
						graph_edit.add_child(table_node)
						table_node.position_offset = source_node.position_offset + Vector2(source_node.size.x + 20, 0)
						_on_graph_edit_connection_request(source_node.name, 0, table_node.name, 0)
						
				mark_modified()
			)
		)
	)
	
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
	
func select_all_node():
	for i in graph_edit.get_children():
		if i is GraphNode:
			i.selected = true
			
func unselect_all_node():
	for i in graph_edit.get_children():
		if i is GraphNode:
			i.selected = false
			
func get_selected_nodes():
	return graph_edit.get_children().filter(func(v):
		return v is GraphNode and v.selected
	)
	
func handle_input_node(input_node: GraphNode, connected_node_name, from_port, to_port, release_position, xenophobic):
	graph_edit.add_child(input_node)
	input_node.set_meta("type", input_node.title)
	input_node.set_meta("node", true)
	input_node.position_offset = release_position # (release_position + graph_edit.scroll_offset) / graph_edit.zoom
	if xenophobic:
		if not input_node.node_enabled.is_connected(node_enabled):
			input_node.node_enabled.connect(node_enabled.bind(input_node)) # 互斥激活事件
	graph_edit.connect_node(input_node.name, from_port, connected_node_name, to_port)
	input_node.enabled = true # 触发同一端口的其余输入端口失效
	mark_modified()
	
func _on_graph_edit_connection_from_empty(to_node: StringName, to_port: int, release_position: Vector2) -> void:
	# 该信号给出的release_position和实际的position_offset不是一个概念，需要做转化
	# WARNING 暂不清楚引擎开发团队是否会修改这个东西，需要注意
	release_position = (release_position + graph_edit.scroll_offset) / graph_edit.zoom
	var node = graph_edit.get_node(str(to_node))
	assert(node.has_meta("type"), "node dose not have meta: type")
	match node.get_meta("type"):
		"Select":
			set_input(to_port, release_position, node)
		"Left Join":
			set_input(to_port, release_position, node)
			
func _on_graph_edit_connection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	graph_edit.connect_node(from_node, from_port, to_node, to_port)
	mark_modified()
	var f_node = graph_edit.get_node(str(from_node))
	var t_node = graph_edit.get_node(str(to_node))
	## select 连 select（即union all）需要做成排他性的
	match f_node.get_meta("type"):
		"Select":
			match t_node.get_meta("type"):
				"Select":
					if not f_node.node_enabled.is_connected(node_enabled):
						f_node.node_enabled.connect(node_enabled.bind(f_node)) # 互斥激活事件
		"Left Join":
			match t_node.get_meta("type"):
				"Select", "Left Join":
					if not f_node.node_enabled.is_connected(node_enabled):
						f_node.node_enabled.connect(node_enabled.bind(f_node)) # 互斥激活事件
	f_node.enabled = true # 可以激活互斥并且促使数据关联
	
func _on_graph_edit_connection_drag_started(_from_node: StringName, _from_port: int, _is_output: bool) -> void:
	unselect_all_node()
	
func _on_graph_edit_disconnection_request(from_node: StringName, from_port: int, to_node: StringName, to_port: int) -> void:
	graph_edit.disconnect_node(from_node, from_port, to_node, to_port)
	mark_modified()
	# 删除BaseDao和LeftJoin数据关联
	var f_node = graph_edit.get_node(str(from_node))
	var t_node = graph_edit.get_node(str(to_node))
	## select 连 select（即union all）
	match f_node.get_meta("type"):
		"Select":
			match t_node.get_meta("type"):
				"Select":
					(t_node.get_meta("base_dao") as BaseDao).remove_union_all(f_node.get_meta("base_dao") as BaseDao)
				"Result":
					# 如果有修改数据的按钮，需要屏蔽
					var graph_datas = t_node.datas
					if graph_datas.size() > 1:
						#┖╴@HBoxContainer                  get_child(-2)
							#┖╴@HFlowContainer             get_child(0)
								#┠╴@Button
								#┠╴@Button
								#┖╴@Button
						var flow_container = t_node.get_child(-2).get_child(0)
						for i in flow_container.get_children():
							i.disabled = true
						var table = graph_datas[0][0].get_child(0)
						for i in table.datas:
							(i as DictionaryObject).reset_read_only(true)
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
			
	mgr = null
	
func _on_graph_edit_delete_nodes_request(nodes):
	var titles = nodes.map(func(v): return graph_edit.get_node(str(v)).title)
	mgr.create_confirmation_dialog(
		split_for_long_content(
			"Are you sure to delete selected nodes `%s`?" % ", ".join(titles)),
		func():
			for i in nodes:
				var node = graph_edit.get_node(str(i))
				node_close(node)
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
	
func mark_modified(_whatever = null):
	if get_meta("is_file", false):
		change_tab_title.emit(self, get_meta("file_name") + "*")
		
func _on_graph_edit_copy_nodes_request(p_copied_data = null) -> void:
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
		
func _on_graph_edit_paste_nodes_request(p_copied_data = null) -> void:
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
			
func _on_graph_edit_duplicate_nodes_request() -> void:
	var tmp_data = {}
	_on_graph_edit_copy_nodes_request(tmp_data)
	_on_graph_edit_paste_nodes_request(tmp_data)
	
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
		
	var focus_owner = get_viewport().gui_get_focus_owner()
	if focus_owner is TextEdit or focus_owner is LineEdit:
		return
		
	var distance = graph_edit.snapping_distance if graph_edit.snapping_enabled else 1
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
