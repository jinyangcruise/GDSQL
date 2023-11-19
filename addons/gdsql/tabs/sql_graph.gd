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
	editor_file_dialog.add_filter("*.gdsqlgraph", "GDSQL GRAPH File")
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
	
func add_select_node(schema = "", table = "", fields = "*", where = "", order_by = "", offset = 0, 
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
	var order_dict_obj: DictionaryObject = graph_node.datas[6][2]
	var limit_dict_obj: DictionaryObject = graph_node.datas[7][2]
	#var separetor: Control = graph_node.datas[8][2]
	var btn_query: Button = graph_node.datas[9][2]
	
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
	if order_by != order_dict_obj._get("Order By"):
		order_dict_obj._set("Order By", order_by)
	if limit != limit_dict_obj._get("Offset"):
		limit_dict_obj._set("Offset", offset)
	if offset != limit_dict_obj._get("Limit"):
		limit_dict_obj._set("Limit", limit)
		
	if query:
		btn_query.emit_signal("pressed")
	
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
	var order_dict_obj = DictionaryObject.new({"Order By": ""}, {"Order By": {"hint": PROPERTY_HINT_MULTILINE_TEXT}})
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
				table_dict_obj._set("Table", "")
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
	order_dict_obj.value_changed.connect(func(prop, new_val, _old_val):
		graph_node.push_redraw_slot_control(6, 2)
		match prop:
			"Order By":
				base_dao.order_by_str(new_val)
	)
	limit_dict_obj.value_changed.connect(func(prop, new_val, _old_val):
		graph_node.push_redraw_slot_control(7, 2)
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
		[null, null, order_dict_obj],
		[null, null, limit_dict_obj],
		[null, null, separator],
		[null, null, btn_query],
		[null, null, separator2]
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
				table_dict_obj._set("Table", "")
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
	
func add_table_node(columns: Array, table_datas: Array, is_union_all: bool, join_conds: Array, asize = null, pos_offset = null, aname = ""):
	graph_edit.grab_focus() # 激活绘图板的快捷键，比如delte， ctrl+C/V
	unselect_all_node()
	
	var graph_node = gen_table_node(columns, table_datas, is_union_all, join_conds)
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
		
	
## 生成一个【表格】节点
func gen_table_node(columns: Array, table_datas: Array, is_union_all: bool, join_conds: Array, old_graph_node: GraphNode = null) -> GraphNode:
#region 每列的属性名称要重新定义
	var hint = {} # 每列的hint
	var map_table_path_index = {} # 临时变量：记录每个表分组的序号
	var last_table_path = "" # 临时变量：记录上一列的表路径
	var last_prefix = "" # 临时变量：记录上一列使用的名称前缀
	var dealed_columns = {} # 临时变量：记录已经处理过的真实列名
	var real_col_name_name = {} # 临时变量：记录列名对应的真实列名
	var new_column_prop_name = [] # 保存包含用于分组的属性和数据列的所有属性
	var table_primary_index = {} # 保存每个表的主键在new_column_prop_name中的序号
	var table_col_index = {} # 保存每个表的键在new_column_prop_name中的序号
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
		separator.custom_minimum_size.y = 60
		
		graph_datas = [
			[margin_container, null],
			[null, null, flow_container], # buttons
			[null, null, separator], # separetor
		]
		
		graph_node.title = "Result"
		graph_node.ready.connect(func():
			graph_node.set_slot_type_left(0, 1) # Result's type is 1
			graph_node.size = Vector2(400, 400)
			graph_node.selected = true
		)
		graph_node.set_meta("type", "Result")
		graph_node.set_meta("node", true)
		graph_node.delete_request.connect(node_close.bind(graph_node)) # 关闭事件
	else:
		graph_node.selected = true
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
			
	# 非unionall就可以编辑。
	graph_node.set_meta("is_union_all", is_union_all)
	graph_node.set_meta("join_conds", join_conds)
	table.editable = not is_union_all
	# 只有单表查询才支持右键删除。联表查询无法知道用户想删除哪个表的数据，即便能勾选要执行的命令，也容易误操作
	var single_table_query = table_primary_index.size() == 1
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
			
		# 加俩按钮:1.新建一条数据；2.应用
		var btn_apply = Button.new()
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
					base_dao.use_db(table_path.get_base_dir() + "/").delete_from(table_path.get_file())
					if grouped_modified_data[table_path]["PK_key"] == null:
						base_dao.set_meta("lackWhere", true)
					else:
						base_dao.where("%s == %s" % [grouped_modified_data[table_path]["PK_key"], 
							var_to_str(grouped_modified_data[table_path]["PK_value_old"])])
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
						daos.push_back(base_dao)
						
					if i.has_meta("new"):
							
						# 单表查询时，由用户自己负责
						if single_table_query:
							insert_call.call()
						# 联表查询时，修改数据若包含主键，那可以先检查一下（主键）是不是在数据库已经存在，如果存在就不需要新增了。
						# 实际上，联表查询时，用户输入了主键如果在数据库里存在，会自动帮用户填充数据。如果不存在，就算新增数据。TODO
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
						var primary_value = modified_data["PK_value_new"]
						var update_call = func():
							var data = {}
							for key in modified_data["modified"]:
								data[key] = modified_data["modified"][key]["new"]
							var base_dao = BaseDao.new().use_db(db_path).update(table_name).sets(data)
							if primary_key == null:
								base_dao.set_meta("lackWhere", true)
							else:
								base_dao.where("%s == %s" % [primary_key, var_to_str(primary_value)])
							daos.push_back(base_dao)
							
						# 单表查询时的所有情况
						if single_table_query:# or primary_key == null or not modified_data["modified"].has(primary_key):
							update_call.call()
						# 联表查询涉及主键修改的情况。只有一种被允许的情况，那就是该主键的旧值为null（实际上该主键所属表的其他字段都是null）。
						# 这样的话，用户修改该主键的值，只能是新建一条数据。
						# 其他情况涉及逻辑冲突，所以禁止用户在联表查询中进行修改主键和关联键的行为（通过hint的usage禁止）。TODO
						# TODO 如果用户需要删除关联，考虑右键菜单加入删除关联。
						else:
							Utils.print_variant(modified_data)
							if primary_key == null or primary_value == null or modified_data["modified"].has(primary_key):
								insert_call.call()
							# 更新非主键字段、非关联键字段
							else:
								update_call.call()
						
			mgr.create_confirmation_dialog("Please confirm:\n" + "\n".join(daos.map(func(v: BaseDao): return v.get_query_cmd())),
				func():
					for i in daos:
						var begin_time = Time.get_unix_time_from_system()
						var ret = i.query()
						if ret != null:
							if ret.ok():
								mgr.add_log_history.emit("OK", begin_time, i.get_query_cmd(), 
									"%d row(s) affected" % ret.get_affected_rows())
							else:
								mgr.add_log_history.emit("Err", begin_time, i.get_query_cmd(), ret.get_err())
						else:
							mgr.add_log_history.emit("Err", begin_time, i.get_query_cmd(), "something wrong")
					table.remove_meta("deleted_datas")
					for node in get_from_nodes(graph_node, "Select"):
						on_select_node_query(node, false)
			)
		)
		
		var btn_revert = Button.new()
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
				old_datas.insert(i, deleted_datas[i]) # 注意：前提是新建的数据都是放在最后面的，不影响数据回到原来的位置。
			table.datas = old_datas
			btn_revert.disabled = true
		)
		
		table.row_deleted.connect(func(row_index, data):
			if data.has_meta("new"):
				return
			var deleted_datas = table.get_meta("deleted_datas", {}) as Dictionary
			deleted_datas[row_index] = data
			table.set_meta("deleted_datas", deleted_datas)
			btn_apply.disabled = false
			btn_revert.disabled = false
		)
		
		var btn_new = Button.new()
		btn_new.text = "new"
		btn_new.pressed.connect(func():
			# 构造一个默认新数据
			var new_data = {}
			for j in new_column_prop_name:
				if j["type"] is String and j["type"] == "group":
					new_data[j["prop"]] = "" # for group
				else:
					var col_def = columns.filter(func(v):
						return v["is_field"] and v["Column Name"] == j["col_name"]
					).front()
					if (col_def["Default(Expression)"] as String).strip_edges().is_empty():
						new_data[j["prop"]] = DataTypeDef.DEFUALT_VALUES[col_def["Data Type"]]
					else:
						new_data[j["prop"]] = mgr.evaluate_command(null, col_def["Default(Expression)"])
						
			var dict_obj = DictionaryObject.new(new_data, hint, false)
			dict_obj.set_meta("new", true)
			dict_obj.value_changed.connect(func(_prop, _new_val, _old_val):
				if not table.get_meta("deleted_datas", {}).is_empty():
					return
					
				for j in table.datas:
					var modified_data = (j as DictionaryObject).get_modified_value()
					if not modified_data.is_empty():
						btn_apply.disabled = false
						btn_revert.disabled = false
						return
				btn_apply.disabled = true
				btn_revert.disabled = true
			)
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
			for j in new_column_prop_name:
				if j["type"] is String and j["type"] == "group":
					data[j["prop"]] = "" # for group
				else:
					data[j["prop"]] = i[j["type"]]
					
			var dict_obj = DictionaryObject.new(data, hint, false)
			dict_obj.value_changed.connect(func(_prop, _new_val, _old_val):
				for j in table.datas:
					var modified_data = (j as DictionaryObject).get_modified_value()
					if not modified_data.is_empty():
						btn_apply.disabled = false
						return
				btn_apply.disabled = true
			)
			new_table_datas.push_back(dict_obj)
		table.datas = new_table_datas
		table.show_menu = true
		table.support_delete_row = true
	else:
		table.datas = table_datas
		table.show_menu = false
		table.support_delete_row = false
		
	graph_node.datas = graph_datas
	
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
		var redraw_call_ref: Callable
		var redraw_call = func(row, col):
			if row == 2 and col == 2 and table_dict_obj._get("Table") == table:
				var fields_dict_obj: DictionaryObject = graph_node.datas[2][2]
				for key in fields:
					fields_dict_obj._set(key, fields[key])
				graph_node.redraw_slot.disconnect(redraw_call_ref)
				
		redraw_call_ref = redraw_call
		graph_node.redraw_slot.connect(redraw_call_ref)
		
	if schema != schema_dict_obj._get("Schema"):
		schema_dict_obj._set("Schema", schema)
	if password != schema_dict_obj._get("_password"):
		schema_dict_obj._set("_password", password)
	if table != table_dict_obj._get("Table"):
		table_dict_obj._set("Table", table)
		
	
func gen_insert_node() -> GraphNode:
	var databases = mgr.databases.keys()
	
	var schema_dict_obj = DictionaryObject.new(
		{"Schema": "", "_password": ""}, 
		{"Schema": {"hint": PROPERTY_HINT_ENUM, "hint_string": ",".join(databases)}, 
		"_password": {"hint": PROPERTY_HINT_PASSWORD, "hint_string": "password"}})
	var table_dict_obj = DictionaryObject.new(
		{"Table": ""}, {"Table": {"hint": PROPERTY_HINT_ENUM, "hint_string": ""}})
	var fields_dict_obj = null
	
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
				table_dict_obj._set("Table", "")
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
					fields_dict_obj = DictionaryObject.new(data, hints)
					fields_dict_obj.set_meta("align", "vertical") # 垂直显示各属性
				else:
					fields_dict_obj = null
				graph_node.datas[2][2] = fields_dict_obj
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
		var redraw_call_ref: Callable
		var redraw_call = func(row, col):
			if row == 2 and col == 2 and table_dict_obj._get("Table") == table:
				var fields_dict_obj: DictionaryObject = graph_node.datas[2][2]
				for key in fields:
					fields_dict_obj._set(key, fields[key])
				graph_node.redraw_slot.disconnect(redraw_call_ref)
				
		redraw_call_ref = redraw_call
		graph_node.redraw_slot.connect(redraw_call_ref)
		
	if schema != schema_dict_obj._get("Schema"):
		schema_dict_obj._set("Schema", schema)
	if password != schema_dict_obj._get("_password"):
		schema_dict_obj._set("_password", password)
	if table != table_dict_obj._get("Table"):
		table_dict_obj._set("Table", table)
	if where != where_dict_obj._get("Where"):
		where_dict_obj._set("Where", where)
		
	
func gen_update_node() -> GraphNode:
	var databases = mgr.databases.keys()
	
	var schema_dict_obj = DictionaryObject.new(
		{"Schema": "", "_password": ""}, 
		{"Schema": {"hint": PROPERTY_HINT_ENUM, "hint_string": ",".join(databases)}, 
		"_password": {"hint": PROPERTY_HINT_PASSWORD, "hint_string": "password"}})
	var table_dict_obj = DictionaryObject.new(
		{"Table": ""}, {"Table": {"hint": PROPERTY_HINT_ENUM, "hint_string": ""}})
	var fields_dict_obj = null
	var where_dict_obj = DictionaryObject.new({"Where": ""}, {"Where": {"hint": PROPERTY_HINT_MULTILINE_TEXT}})
	
	# 关联该节点的BaseDao
	var base_dao = BaseDao.new()
	base_dao.update("")
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
				table_dict_obj._set("Table", "")
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
					fields_dict_obj = DictionaryObject.new(data, hints)
					fields_dict_obj.set_meta("align", "vertical") # 垂直显示各属性
				else:
					fields_dict_obj = null
				graph_node.datas[2][2] = fields_dict_obj
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
				table_dict_obj._set("Table", "")
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
	
func extract_table_data_call(v, columns):
	if v is DictionaryObject:
		var arr = []
		for i in columns.size():
			arr.push_back(v._get_by_index(i))
		return arr
	return v
	
func get_nodes_params():
	var all_data = {}
	for graph_node in graph_edit.get_children():
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
			_:
				continue
				
		all_data[graph_node.name.validate_node_name()] = { # validate一下，不然会存在@符号，再次设置name的时候会被替换为下划线
			"type": type,
			"params": data,
			"size": graph_node.size,
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
	for node_name in nodes:
		var type = nodes[node_name]["type"]
		var params = nodes[node_name]["params"]
		var asize = nodes[node_name]["size"]
		var position_offset = nodes[node_name]["position_offset"]
		match type:
			"Select":
				await add_select_node(params["Schema"], params["Table"], params["Fields"], 
					params["Where"], params["Order By"], params["Offset"], 
					params["Limit"], params["_alias"], params["_password"],
					asize, position_offset, node_name, false)
			"Left Join":
				await add_left_join_node(params["Schema"], params["_password"], params["Table"],
					params["_alias"], params["On"], asize, position_offset, node_name)
			"Result":
				await add_table_node(params["columns"], params["table_datas"], params["is_union_all"],
					params["join_conds"], asize, position_offset, node_name)
			"Insert":
				await add_insert_node(params["Schema"], params["_password"], params["Table"],
					params["Fields"], asize, position_offset, node_name)
			"Update":
				await add_update_node(params["Schema"], params["_password"], params["Table"],
					params["Fields"], params["Where"], asize, position_offset, node_name)
			"Delete":
				await add_delete_node(params["Schema"], params["_password"], params["Table"],
					params["Where"], asize, position_offset, node_name)
					
	# make connections
	for info in connections:
		_on_graph_edit_connection_request(info["from_node"], info["from_port"], 
			info["to_node"], info["to_port"])
			
	# enable会影响connection对象间的数据关联，最好最后设置
	for node_name in nodes:
		var node = graph_edit.get_node(node_name) as GraphNode
		node.enabled = nodes[node_name]["enabled"]
		
	set_meta("type", "sql_graph")
	set_meta("is_file", true)
	set_meta("file_path", path)
	set_meta("file_name", path.get_file())
	
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
		var dao = source_node.get_meta("base_dao") as BaseDao
		mgr.request_user_enter_password.emit(dao.get_db(), dao.get_table(), dao.get_password(), func():
			var begin_time = Time.get_unix_time_from_system()
			var action = dao.get_query_cmd()
			var ret = dao.query()
			if ret == null:
				mgr.add_log_history.emit("Err", begin_time, action, "something wrong")
				return
				
			if log_history:
				mgr.add_log_history.emit("OK", begin_time, action, "%d row(s) returned" % (ret.get_data().size())) # 去掉表头
			
			var update_result = false
			if from_to_map.has(source_node.name):
				for to in from_to_map[source_node.name]:
					var to_node = graph_edit.get_node(str(to))
					if to_node.get_meta("type") == "Result":
						if to_node.enabled:
							gen_table_node(ret.get_head(), ret.get_data(), dao.is_union_all(), dao.get_left_join_conds(), to_node)
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
				mgr.add_log_history.emit("Err", begin_time, action, ret.get_err())
				return
				
			mgr.add_log_history.emit("OK", begin_time, action, "%d row(s) affected" % (ret.get_affected_rows()))
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
				mgr.add_log_history.emit("Err", begin_time, action, ret.get_err())
				return
				
			mgr.add_log_history.emit("OK", begin_time, action, "%d row(s) affected" % (ret.get_affected_rows()))
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
				mgr.add_log_history.emit("Err", begin_time, action, ret.get_err())
				return
				
			mgr.add_log_history.emit("OK", begin_time, action, "%d row(s) affected" % (ret.get_affected_rows()))
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
	
func unselect_all_node():
	for i in graph_edit.get_children():
		if i.has_meta("node"):
			i.selected = false

		
func handle_input_node(input_node: GraphNode, connected_node_name, from_port, to_port, release_position, xenophobic):
	graph_edit.add_child(input_node)
	input_node.set_meta("type", input_node.title)
	input_node.set_meta("node", true)
	input_node.position_offset = release_position # (release_position + graph_edit.scroll_offset) / graph_edit.zoom
	if xenophobic:
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
	mgr.create_confirmation_dialog("Are you sure to delete selected nodes `%s`?" % ", ".join(titles),
		func():
			for i in nodes:
				var node = graph_edit.get_node(str(i))
				node_close(node)
				node.queue_free()
			mark_modified()
	)
	
func mark_modified(_whatever = null):
	if get_meta("is_file", false):
		change_tab_title.emit(self, get_meta("file_name") + "*")


