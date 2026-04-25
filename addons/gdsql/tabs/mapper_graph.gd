@tool
extends VSplitContainer

@onready var button_open: Button = $VBoxContainer/HFlowContainer/ButtonOpen
@onready var button_save: Button = $VBoxContainer/HFlowContainer/ButtonSave
@onready var button_save_as: Button = $VBoxContainer/HFlowContainer/ButtonSaveAs
@onready var button_add_node: Button = $VBoxContainer/HFlowContainer/ButtonAddNode
@onready var line_edit_save_path: LineEdit = $VBoxContainer/HFlowContainer/LineEditSavePath
@onready var option_button_choose_path: OptionButton = $VBoxContainer/HFlowContainer/OptionButtonChoosePath
@onready var option_button_result_map_mode: OptionButton = $VBoxContainer/HFlowContainer/OptionButtonResultMapMode
@onready var option_button_link: OptionButton = $VBoxContainer/HFlowContainer/OptionButtonLink
@onready var button_run_selected: Button = $VBoxContainer/HFlowContainer/ButtonRunSelected
@onready var button_run: Button = $VBoxContainer/HFlowContainer/ButtonRun
@onready var button_node_list: Button = %ButtonNodeList
@onready var popup_panel_node_list: PopupPanel = %PopupPanelNodeList
@onready var v_box_container_node_list: VBoxContainer = %VBoxContainerNodeList
@onready var line_edit_filter_node_list: LineEdit = %LineEditFilterNodeList
@onready var menu_button_sort_node_list: MenuButton = %MenuButtonSortNodeList
@onready var button_refresh_node_list: Button = %ButtonRefreshNodeList
@onready var scroll_container_node_list: ScrollContainer = $VBoxContainer/HFlowContainer/ButtonNodeList/PopupPanelNodeList/VBoxContainerNodeList/ScrollContainerNodeList
@onready var tree_node_list: Tree = %TreeNodeList
@onready var graph_edit: GraphEdit = %GraphEdit

signal request_open_file(path: String)
signal change_tab_title(page: Control, title: String)

const EXTENSION = "*.gdmappergraph"

enum RESULT_MAP_MODE {
	SIMPLEST,
	FULL,
}

enum LINK_WAY {
	NESTING_SELECT,
	NESTING_RESULT_MAP, # use left join
}

enum NODE_LIST_TREE_ITEM_BUTTON {
	TABLE_NOT_EXIST, ## 表不存在
	TABLE_COMMENT_CHANGE, ## 表描述有变化
	COLUMNS_CHANGE, ## 表字段发生了变化
}

enum TABLE_CHANGE_TYPE {
	META_TABLE_NOT_EXIST, ## 表不存在
	META_TABLE_COMMENT_CHANGE, ## 表描述有变化
	META_COLUMN_NAME_CHANGE, ## 列名发生了变化
	META_COLUMN_DEFINE_CHANGE, ## 列定义有变化
}

const COLOR_DIFF_BASIC_ADDED = Color(Color.LIGHT_GREEN, 0.2)
const COLOR_DIFF_BASIC_REMOVED = Color(Color.INDIAN_RED, 0.2)
const COLOR_DIFF_MERGE_INSERTED = Color(Color.BLUE, 0.2)

var tree_node_list_root: TreeItem

func _ready() -> void:
	line_edit_filter_node_list.text_changed.connect(_filter_node_list_changed)
	
	tree_node_list.set_column_expand(0, true)
	tree_node_list.set_column_clip_content(0, false)
	tree_node_list_root = tree_node_list.create_item()
	tree_node_list.hide_root = true
	
	menu_button_sort_node_list.get_popup().id_pressed.connect(_on_sort_node_list_pressed)
	menu_button_sort_node_list.icon = get_theme_icon(&"Sort", &"EditorIcons")
	
	graph_edit.tree_node_list_item_added.connect(_filter_node_list_changed.bind(""))
	
	GDSQL.WorkbenchManager.sys_confirm_alter_table.connect(_on_sys_confirm_alter_table)
	GDSQL.WorkbenchManager.sys_confirm_drop_table.connect(_on_sys_confirm_drop_table)
	
func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		if menu_button_sort_node_list:
			menu_button_sort_node_list.icon = get_theme_icon(&"Sort", &"EditorIcons")
			
func load_mapper_file(path):
	var config = GDSQL.ImprovedConfigFile.new()
	config.load(path)
	var save_path = config.get_value("data", "path", "") as String
	var result_map_mode = config.get_value("data", "result_map_mode", RESULT_MAP_MODE.SIMPLEST)
	var link_type = config.get_value("data", "link_type", LINK_WAY.NESTING_SELECT)
	
	line_edit_save_path.text = save_path
	option_button_result_map_mode.selected = result_map_mode
	option_button_link.selected = link_type
	if save_path != "":
		if save_path.begins_with("res://"):
			option_button_choose_path.selected = 0
		elif save_path.begins_with("user://"):
			option_button_choose_path.selected = 1
		else:
			option_button_choose_path.selected = 2
			
	graph_edit.include_file(path, false)
	
	set_meta("type", "mapper_graph")
	set_meta("is_file", true)
	set_meta("file_path", path)
	set_meta("file_name", path.get_file())
	
func load_data(info: Dictionary):
	graph_edit.add_item(info, {})
	
func _on_button_open_pressed() -> void:
	var editor_file_dialog = EditorFileDialog.new()
	editor_file_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	editor_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	editor_file_dialog.add_filter(EXTENSION, "GDSQL Mapper Project File")
	editor_file_dialog.file_selected.connect(func(path: String):
		request_open_file.emit(path)
	)
	add_child(editor_file_dialog)
	editor_file_dialog.popup_centered_ratio(0.7)
	editor_file_dialog.canceled.connect(editor_file_dialog.queue_free)
	
func _on_button_save_pressed() -> void:
	# 本身就是一个已经保存的文件，就直接保存
	if get_meta("is_file"):
		var config = GDSQL.ImprovedConfigFile.new()
		config.set_value("data", "nodes", graph_edit.get_nodes_params())
		config.set_value("data", "connections", graph_edit.get_connection_params())
		config.set_value("data", "include_files", graph_edit.get_inlcude_params())
		config.set_value("data", "path", line_edit_save_path.text.strip_edges())
		config.set_value("data", "result_map_mode", option_button_result_map_mode.selected)
		config.set_value("data", "link_type", option_button_link.selected)
		
		# 防止报错导致丢失文件中的旧数据
		if config.get_value("data", "nodes", null) == null or \
			config.get_value("data", "connections", null) == null:
			return
			
		config.save(get_meta("file_path"))
		change_tab_title.emit(self, get_meta("file_name"))
		return
		
	_on_button_save_as_pressed()
	
func _on_button_save_as_pressed() -> void:
	var editor_file_dialog = EditorFileDialog.new()
	editor_file_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	editor_file_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	editor_file_dialog.add_filter(EXTENSION, "GDSQL MAPPER File")
	editor_file_dialog.file_selected.connect(func(path: String):
		var config = GDSQL.ImprovedConfigFile.new()
		config.set_value("data", "nodes", graph_edit.get_nodes_params())
		config.set_value("data", "connections", graph_edit.get_connection_params())
		config.set_value("data", "include_files", graph_edit.get_inlcude_params())
		config.set_value("data", "path", line_edit_save_path.text.strip_edges())
		config.set_value("data", "result_map_mode", option_button_result_map_mode.selected)
		config.set_value("data", "link_type", option_button_link.selected)
		
		# 防止报错导致丢失文件中的旧数据
		if config.get_value("data", "nodes", null) == null or \
			config.get_value("data", "connections", null) == null:
			return
			
		config.save(path)
		var file_name = path.get_file()
		change_tab_title.emit(self, file_name)
		set_meta("type", "mapper_graph")
		set_meta("is_file", true)
		set_meta("file_path", path)
		set_meta("file_name", file_name)
	)
	add_child(editor_file_dialog)
	editor_file_dialog.popup_centered_ratio(0.7)
	editor_file_dialog.canceled.connect(editor_file_dialog.queue_free)
	
func _on_button_add_node_pressed() -> void:
	GDSQL.WorkbenchManager.create_accept_dialog(tr(button_add_node.tooltip_text))
	
func _on_option_button_choose_path_item_selected(access: int, extra_line_edit = null, parent_dialog = null) -> void:
	var editor_file_dialog = EditorFileDialog.new()
	editor_file_dialog.access = access
	editor_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
	editor_file_dialog.dir_selected.connect(func(path: String):
		line_edit_save_path.text = path
		if extra_line_edit:
			extra_line_edit.text = path
		change_tab_title.emit(self, get_meta("file_name") + "*")
	, CONNECT_DEFERRED)
	if parent_dialog:
		editor_file_dialog.transient = true
		editor_file_dialog.exclusive = true
		parent_dialog.add_child(editor_file_dialog)
	else:
		add_child(editor_file_dialog)
	editor_file_dialog.popup_centered_ratio(0.5)
	editor_file_dialog.canceled.connect(func():
		editor_file_dialog.queue_free()
	, CONNECT_DEFERRED)
	
func _on_button_run_selected_pressed() -> void:
	var arr_node = []
	for i in graph_edit.get_children():
		if i is GraphNode and i.selected:
			arr_node.push_back(i)
	_generate(arr_node)
	
func _on_button_run_pressed() -> void:
	var arr_node = []
	for i in graph_edit.get_children():
		if i is GraphNode:
			arr_node.push_back(i)
	_generate(arr_node)
	
func has_a_helper_pre_node(node: GraphNode, to_from_map: Dictionary) -> bool:
	if to_from_map.has(node):
		for fnode in to_from_map[node]:
			if graph_edit.is_helper_node(fnode):
				return true
	return false
	
## 获取node前面连接的helper的源头实体节点
## 由于来源可能是多个字段，所以返回数组.
## return [[node, from_col, to_col]]
## node 是实体节点，from_col是实体节点的某个字段，to_col是helper节点的接入字段。
func get_pre_helpers_source(node: GraphNode, to_from_map: Dictionary):
	var ret = []
	if to_from_map.has(node):
		for fnode in to_from_map[node]:
			# 如果fnode是helper节点
			if graph_edit.is_helper_node(fnode):
				# 如果fnode前面还连着helper节点，继续向前溯源
				if has_a_helper_pre_node(fnode, to_from_map):
					var r = get_pre_helpers_source(fnode, to_from_map)
					ret.append_array(r)
				# 把fnode前面连着的非helper节点信息加入
				else:
					for f_fnode in to_from_map[fnode]:
						# i is [from_col, to_col]
						for i in to_from_map[fnode][f_fnode]:
							ret.push_back([f_fnode] + i)
			else:
				# 错误的情况，因为一个非HELPER节点就意味着一个实体，两个实体节点拥有同一个
				# 实体作为它们的属性，是不正确的，或者说，是我们不支持的。
				assert(false, "Invalid connection!")
	return ret
	
## 获取node前面连接的helper的源头实体节点的输出列名
func get_pre_helper_source_cols(node: GraphNode, to_from_map: Dictionary):
	var ret = []
	for i in get_pre_helpers_source(node, to_from_map):
		if not ret.has(i[1]):
			ret.push_back(i[1])
	return ret
	
## 返回helper的最终实体节点。NOTICE 外部确保传入的node是一个helper节点。
func get_helper_final_entity_nodes(node: GraphNode, nodes_map: Dictionary, node_pair: Dictionary):
	var ret = []
	var process = [node.name]
	while not process.is_empty():
		var n = process.pop_front()
		if node_pair.has(n):
			for tnode in node_pair[n]:
				if graph_edit.is_helper_node(nodes_map[tnode]):
					process.push_back(tnode)
				else:
					if not ret.has(nodes_map[tnode]):
						ret.push_back(nodes_map[tnode])
	return ret
	
## return:
## select t0.id, t0.xx from db.table t0
## left join db.table1 t1 on t1.xx == t0.xx
## left join db.table2 t2 on t2.yy == t1.yy
## where t1.xx == #{id1} and t2.yy == #{id2}
func get_helpers_left_join_cmds(node: GraphNode, to_from_map: Dictionary, 
alias_map: Dictionary = {}, arr_index: Array = [-1]):
	var ret = {"select": [], "left_join": [], "where": []}
	# 优先给前面的表取小序号的alias
	var process = [node]
	var nodes = []
	while not process.is_empty():
		var anode = process.pop_front()
		if not nodes.has(anode):
			nodes.push_back(anode)
		for fnode in to_from_map[anode]:
			if graph_edit.is_helper_node(fnode):
				process.push_back(fnode)
				
	nodes.reverse()
	var first_node = arr_index.max() == -1
	var get_alias_func = func(p_node):
		if alias_map.has(p_node):
			return alias_map[p_node]
		var index = arr_index.max() + 1
		arr_index.push_back(index)
		var alias = "t%s" % index
		alias_map[p_node] = alias
		return alias
	for n in nodes:
		get_alias_func.call(n)
		
	var data = node.get_meta("data")
	var db_name = data.db_name
	var table_name = data.table_name
	var table_alias = get_alias_func.call(node)
	var columns = data.columns
	var cols = columns.map(func(v):
		return "%s.%s" % [table_alias, v["Column Name"]])
		
	if first_node:
		if option_button_result_map_mode.selected == RESULT_MAP_MODE.SIMPLEST:
			ret.select.push_back("select %s.*" % table_alias)
		else:
			ret.select.push_back("select %s " % 
				split_for_long_content(", ".join(cols), "\n\t\t"))
				
	var arr_on = []
	for fnode in to_from_map[node]:
		var from_alias = get_alias_func.call(fnode)
		# i is [from_col, to_col]
		for i in to_from_map[node][fnode]:
			arr_on.push_back("%s.%s == %s.%s" % [
				table_alias, i[1], from_alias, i[0]])
	ret.left_join.push_front("left join %s.%s %s on %s" % [
		db_name, table_name, table_alias, " and ".join(arr_on)])
		
	if to_from_map.has(node):
		for fnode in to_from_map[node]:
			var from_data = fnode.get_meta("data")
			var from_db = from_data.db_name
			var from_table = from_data.table_name
			var from_alias = get_alias_func.call(fnode)
			var ffnode_is_helper_node = false
			for ffnode in to_from_map[fnode]:
				if graph_edit.is_helper_node(ffnode):
					ffnode_is_helper_node = true
					break
			if ffnode_is_helper_node and graph_edit.is_helper_node(fnode):
				var r = get_helpers_left_join_cmds(
					fnode, to_from_map, alias_map, arr_index)
				ret.select.append_array(r.select)
				ret.left_join = r.left_join + ret.left_join
				ret.where = r.where + ret.where
			else:
				ret.select.push_back("from %s.%s %s" % [from_db, from_table, from_alias])
				# i is [from_col, to_col]
				for ffnode in to_from_map[fnode]:
					for i in to_from_map[fnode][ffnode]:
						# 不考虑#{%s}存在两张表相同字段导致变量名混淆的问题，
						# 因为不能连接多个实体表。
						ret.where.push_front("%s.%s == #{%s}" % [
							get_alias_func.call(fnode), i[1], i[0]])
	return ret
	
func _generate(nodes: Array):
	var nodes_map = {}
	var node_pair = {}
	var node_link_prop = {}
	var node_to_from_map = {}
	
	for i in nodes:
		if i.enabled:
			nodes_map[i.name] = i
			
	for i in graph_edit.get_connection_list():
		# 节点可能未被选中或开启
		if not nodes_map.has(i.from_node) or not nodes_map.has(i.to_node):
			continue
		var from_node = nodes_map[i.from_node]
		var from_columns = from_node.get_meta("data").columns
		var from_col = from_columns[i.from_port]["Column Name"]
		var to_node = nodes_map[i.to_node]
		var to_columns = to_node.get_meta("data").columns
		assert(to_node.get_meta("extra_enabled", false), 
			"This node is supposed to has meta extra_enabled's true.")
		var to_col = to_columns[i.to_port]["Column Name"]
		var to_data = to_node.get_meta("data")
		
		if not node_to_from_map.has(to_node):
			node_to_from_map[to_node] = {}
		if not node_to_from_map[to_node].has(from_node):
			node_to_from_map[to_node][from_node] = []
		node_to_from_map[to_node][from_node].push_back([from_col, to_col])
		
		if nodes_map.has(i.from_node) and nodes_map.has(i.to_node):
			if not node_pair.has(i.from_node):
				node_pair[i.from_node] = {}
			if not node_pair[i.from_node].has(i.to_node):
				var to_node_extra = graph_edit.get_node_extra(to_node)
				node_link_prop[i.to_node] = to_node_extra.link_prop_type
				var is_helper = to_node_extra.link_type == graph_edit.LINK_TYPE.LINK_HELPER
				node_pair[i.from_node][i.to_node] = {
					"node": nodes_map[i.to_node],
					"db_name": to_data.db_name,
					"table_name": to_data.table_name,
					"comment": to_data.comment,
					"link_type": to_node_extra.link_type,
					"link_prop_type": to_node_extra.link_prop_type,
					"link_prop": to_node_extra.link_prop,
					"link_col": [],
					"to_columns": to_columns,
					"is_helper": is_helper,
					"helper_finals": null,
				}
				
			node_pair[i.from_node][i.to_node].link_col.push_back([from_col, to_col])
			
	for f in node_pair:
		for t in node_pair[f]:
			if node_pair[f][t]["is_helper"]:
				var to_node = nodes_map[t]
				node_pair[f][t]["helper_finals"] = get_helper_final_entity_nodes(to_node, nodes_map, node_pair)
				
	var leading_nodes = nodes_map.keys()
	for from_node_name in node_pair:
		for to_node_name in node_pair[from_node_name]:
			leading_nodes.erase(to_node_name)
			
	const prefixes = "tabcdefghijklmnopqrsuvwxyz" # t is most common
	
	# gdscript of entity
	var entity_map = {} # db.entity_name => [content]
	var entity_map_2 = {} # db.entity_name => {property => {"comment": "", "define": "", "getset": []}}
	# xml of mapper
	var xml_map = {} # db.mapper_name => [content]
	# gdscrip of mapper
	var mapper_map = {} # db.mapper_name => [content]
	
	# 每一个起始节点，有一套生成的xml、entity、mapper
	for lead_node_name in leading_nodes:
		var xml_arr = ["""<?xml version="1.0" encoding="UTF-8" ?>
<!DOCTYPE mapper
PUBLIC "-//mybatis.org//DTD Mapper 3.0//EN"
"http://mybatis.org/dtd/mybatis-3-mapper.dtd">
<mapper namespace="%s">
	
	<cache eviction="LRU" flushInterval="0" size="50" />
	"""]
		var arr_method = []
		var arr_columns = {}
		var has_asso_collec = node_pair.has(lead_node_name)
		var valid_prefixes = {} # a0_, a1_, ..., z8_, z9_, aa_, ab_, ..., zy_, zz_
		for i in prefixes:
			for j in 10:
				valid_prefixes[i + str(j) + "_"] = 1
		for i in prefixes:
			for j in prefixes:
				valid_prefixes[i + j + "_"] = 1
		var prefix_index = -1
		var table_alias = {}
		var leading_result_map_id = null
		var leading_mapper_n = null
		var leading_entity_n = null
		var leading_db_name = null
		var leading_table_name = null
		var leading_table_name_snake = null
		var table_counts = {}
		var column_counts = {} # 同名列
		
		# 递归找到与起始节点关联的诸多节点
		var linked_nodes = get_linked_nodes_bfs(node_pair, lead_node_name)
		
		for node_name in linked_nodes:
			# HELPER 不占用实体类名，除非使用了left join
			if option_button_link.selected == LINK_WAY.NESTING_SELECT and \
			graph_edit.is_helper_node(nodes_map[node_name]):
				continue
				
			prefix_index += 1
			table_alias[node_name] = valid_prefixes.keys()[prefix_index]
			var data = nodes_map[node_name].get_meta("data") as Dictionary
			var db_name = data.db_name as String
			var table_name = data.table_name as String
			var columns = data.columns as Array
			
			if not table_counts.has(data.db_name):
				table_counts[data.db_name] = {}
			if not table_counts[data.db_name].has(data.table_name):
				table_counts[data.db_name][data.table_name] = 0
			table_counts[data.db_name][data.table_name] += 1
			
			for j in columns:
				if not column_counts.has(j["Column Name"]):
					column_counts[j["Column Name"]] = 0
				column_counts[j["Column Name"]] += 1
				var i3 = j["Column Name"].substr(0, 3)
				if valid_prefixes.has(i3):
					valid_prefixes.erase(i3)
					
		var result_map_added = []
		for node_name in linked_nodes:
			var node = nodes_map[node_name]
			# HELPER 不生成实体、xml mapper、gdscript xml
			if graph_edit.is_helper_node(node):
				continue
				
			var data = node.get_meta("data") as Dictionary
			var aprops = graph_edit.get_node_props(node) as Dictionary
			var db_name = data.db_name as String
			var table_name = data.table_name as String
			var table_comment = data.comment
			var columns = data.columns as Array
			var result_map_id = ""
			if node_link_prop.has(node_name):
				result_map_id = node_link_prop[node_name].to_camel_case()
			else:
				result_map_id = graph_edit.get_node_extra(node).link_prop_type.to_camel_case()
			var entity_name = result_map_id.capitalize().replace(" ", "") + "Entity"
			if leading_result_map_id == null:
				leading_result_map_id = result_map_id
				leading_mapper_n = result_map_id.capitalize().replace(" ", "") + "Mapper"
				leading_entity_n = entity_name
				leading_db_name = db_name
				leading_table_name = table_name
				leading_table_name_snake = table_name.to_snake_case()
				
			var arr_col = []
			var arr_col_name = []
			var arr_prop_type = []
			var a_col_prefix = ""
			# lead table 可能需要column加前缀。其他的不用，因为association和collection
			# 支持在columnPrefix属性设定一个前缀。
			if node_name == lead_node_name:
				if node_pair.has(node_name) and option_button_link.selected != LINK_WAY.NESTING_SELECT:
					a_col_prefix = table_alias[node_name]
			var prop_max_length = get_max_prop_name_length(aprops) + 'property=""'.length()
			var col_max_length = get_max_col_name_length(columns) + 'column=""'.length() + \
				a_col_prefix.length() + 4
			var unique_cols = []
			for col in columns:
				var prefix = '<id    ' if col.PK else ('<uq    ' if col.UQ else '<result')
				if linked_nodes.size() > 1:
					prefix += '     ' # +5 as long as associaiton
				var a_col_name = col["Column Name"]
				if col.PK or col.UQ:
					unique_cols.push_back(a_col_name)
				if option_button_result_map_mode.selected == RESULT_MAP_MODE.FULL:
					arr_col.push_back(('%s %-' + str(prop_max_length) + 's    %-' + \
						str(col_max_length) + 's/>') % [
							prefix, 
							'property="%s"' % aprops[a_col_name], 
							'column="%s"' % (a_col_prefix + a_col_name)]
					)
				arr_col_name.push_back(a_col_name)
				arr_prop_type.push_back([aprops[a_col_name], 
					type_string(col["Data Type"]), -1, col["Comment"], col["Hint String"]])
			arr_columns[node_name] = arr_col_name
			
			if node_pair.has(node_name):
				for to_node_name in node_pair[node_name]:
					var ainfo = node_pair[node_name][to_node_name]
					var arr_info = [] # 要兼容helper一对多的情况
					if ainfo.is_helper:
						for anode in ainfo.helper_finals:
							for fnode in node_to_from_map[anode]:
								# WARNING 注意push的info中的部分信息不属于 node_name 的节点
								arr_info.push_back(node_pair[fnode.name][anode.name])
								break # 只需要一个关于anode的信息就行了，主要是db名称，表名称，属性名称等
					else:
						arr_info.push_back(ainfo)
						
					for info in arr_info:
						var s = null
						var is_association = info.link_type == graph_edit.LINK_TYPE.ASSOCIATION
						var prefix = "<association" if is_association else "<collection "
						var a_result_map_id = info.link_prop_type.to_camel_case() + "Result"
						
						if option_button_link.selected == LINK_WAY.NESTING_SELECT:
							var by
							var parent_by
							var arg_types = []
							var method
							if ainfo.is_helper:
								by = get_pre_helper_source_cols(info.node, node_to_from_map)
								by.sort()
								for i in by:
									for j in node.get_meta("data").columns:
										if j["Column Name"] == i:
											arg_types.push_back(j["Data Type"])
											break
								parent_by = by
								method = "select_%s_by_%s" if is_association \
									else "select_%s_list_by_%s"
								method %= [info.link_prop_type.to_snake_case(), "_".join(by)]
							else:
								by = info.link_col.map(func(v): return v[1])
								by.sort()
								for i in by:
									for j in info.to_columns:
										if j["Column Name"] == i:
											arg_types.push_back(j["Data Type"])
											break
								parent_by = info.link_col.map(func(v): return v[0])
								parent_by.sort()
								method = "select_%s_by_%s" % [
									info.link_prop_type.to_snake_case(), "_".join(by)]
									
							var method_info = {
								"id": method,
								"result_map": a_result_map_id,
								"arg_names": by,
								"arg_types": arg_types,
								"db_name": info.db_name,
								"namespace": info.db_name + "." + info.table_name,
								"node_name": to_node_name,
								"info": info,
								"from_helper": ainfo.is_helper,
							}
							
							# 为了避免因为各种原因导致method相同但实际上不能共用method的情况，
							# 需要给method名称加后缀。
							var new_index = 1
							var need_add_surfix = false
							var has_same = false
							for i in arr_method:
								if i.id.begins_with(method_info.id):
									var a_index = Array(i.id.split("_")).back().to_int()
									new_index = max(a_index, new_index) + 1
								if i.id == method_info.id:
									# TODO FIXME 有漏洞
									has_same = true
									if i.from_helper != method_info.from_helper \
									or i.result_map != method_info.result_map \
									or i.arg_names != method_info.arg_names \
									or i.arg_types != method_info.arg_types \
									or i.namespace != method_info.namespace \
									or i.info.link_col != method_info.info.link_col:
										need_add_surfix = true
										
							if need_add_surfix:
								method_info.id = method_info.id + "_" + str(new_index)
								has_same = false
								
							s = '%s property="%s" column="%s" select="%s"    />' % \
								[prefix, info.link_prop, ",".join(parent_by), method_info.id]
								
							if not has_same:
								arr_method.push_back(method_info)
						else:
							s = '%s property="%s" columnPrefix="%s" resultMap="%s"    />' % \
								[prefix, info.link_prop, table_alias[to_node_name], 
								a_result_map_id]
								
						arr_col.push_back(s)
						arr_prop_type.push_back(
							[info.link_prop, info.link_prop_type, info.link_type, info.comment, ""])
							
			if not result_map_added.has(result_map_id):
				xml_arr.push_back('\n\t<resultMap id="%sResult" type="%s"' % [result_map_id, entity_name])
				if option_button_result_map_mode.selected == RESULT_MAP_MODE.SIMPLEST:
					xml_arr.push_back(' uniqueColumn="%s"' % ",".join(unique_cols))
				if arr_col.is_empty():
					xml_arr.push_back(' autoMapping="%s" />\n\t' % (
						"true" if option_button_result_map_mode.selected == RESULT_MAP_MODE.SIMPLEST else "false"))
				else:
					xml_arr.push_back(' autoMapping="%s">\n\t\t%s\n\t</resultMap>\n\t' % 
						["true" if option_button_result_map_mode.selected == RESULT_MAP_MODE.SIMPLEST else "false", 
						"\n\t\t".join(arr_col)])
				result_map_added.push_back(result_map_id)
				
			# entity
			var en_ns = '%s.%s' % [db_name, entity_name]
			if not entity_map.has(en_ns):
				entity_map[en_ns] = []
				if table_comment != "":
					entity_map[en_ns].push_back('## %s\n' % table_comment)
				entity_map[en_ns].push_back('@warning_ignore("missing_tool")\nextends GDSQL.GBatisEntity\nclass_name %s\n' % entity_name)
				
			var e_map = entity_map_2.get(en_ns, {})
			entity_map_2[en_ns] = e_map
			for i in arr_prop_type:
				var arr_getset = []
				var p_map = {"comment": "", "define": "", "getset": arr_getset}
				var i_0_snake = i[0].to_snake_case()
				if is_shadowing(i[0]):
					p_map.define = '\n@warning_ignore("shadowed_global_identifier")'
				if i[2] == graph_edit.LINK_TYPE.COLLECTION_ARRAY:
					if i[1] == "Nil":
						p_map.comment = '\n## Array[null]. %s' % i[3]
						p_map.define += '\nvar %s: Array\n' % i[0]
						arr_getset.push_back('\nfunc get_%s() -> Array:' % i_0_snake)
						arr_getset.push_back('\n\treturn %s\n\t' % i[0])
						arr_getset.push_back('\nfunc set_%s(p_%s: Array):' % [i_0_snake, i_0_snake])
						arr_getset.push_back('\n\t%s = p_%s' % [i[0], i_0_snake])
						arr_getset.push_back('\n\tvalue_changed.emit("%s", %s)\n\t' % [i_0_snake, i[0]])
					elif GDSQL.DataTypeDef.DATA_TYPE_COMMON_NAMES.has(i[1]):
						p_map.comment = '\n## Array[%s]. %s' % [i[1], i[3]]
						p_map.define += '\nvar %s: Array[%s]\n' % [i[0], i[1]]
						arr_getset.push_back('\nfunc get_%s() -> Array[%s]:' % [i_0_snake, i[1]])
						arr_getset.push_back('\n\treturn %s\n\t' % i[0])
						arr_getset.push_back('\nfunc set_%s(p_%s: Array[%s]):' % [i_0_snake, i_0_snake, i[1]])
						arr_getset.push_back('\n\t%s = p_%s' % [i[0], i_0_snake])
						arr_getset.push_back('\n\tvalue_changed.emit("%s", %s)\n\t' % [i_0_snake, i[0]])
					else:
						p_map.comment = '\n## Array[%sEntity]. %s' % [i[1], i[3]]
						p_map.define += '\nvar %s: Array[%sEntity]\n' % [i[0], i[1]]
						arr_getset.push_back('\nfunc get_%s() -> Array[%sEntity]:' % [i_0_snake, i[1]])
						arr_getset.push_back('\n\treturn %s\n\t' % i[0])
						arr_getset.push_back('\nfunc set_%s(p_%s: Array[%sEntity]):' % [i_0_snake, i_0_snake, i[1]])
						arr_getset.push_back('\n\t%s = p_%s' % [i[0], i_0_snake])
						arr_getset.push_back('\n\tvalue_changed.emit("%s", %s)\n\t' % [i_0_snake, i[0]])
				else:
					if i[1] == "Nil":
						p_map.comment = '\n## null. %s' % i[3]
						p_map.define += '\nvar %s\n' % i[0]
						arr_getset.push_back('\nfunc get_%s():' % i_0_snake)
						arr_getset.push_back('\n\treturn %s\n\t' % i[0])
						arr_getset.push_back('\nfunc set_%s(p_%s):' % [i_0_snake, i_0_snake])
						arr_getset.push_back('\n\t%s = p_%s' % [i[0], i_0_snake])
						arr_getset.push_back('\n\tvalue_changed.emit("%s", %s)\n\t' % [i_0_snake, i[0]])
					elif GDSQL.DataTypeDef.DATA_TYPE_COMMON_NAMES.has(i[1]):
						p_map.comment = '\n## %s. %s' % [i[4] if i[1] == "Object" else i[1], i[3]]
						#arr.push_back('\nvar %s: %s\n' % [i[0], i[1]])
						# 不在属性上指定数据类型了，不然update、insert不知道有没有给属性设定值。
						# 比如：<if test="name != null">
						# 但是保留在get、set函数上进行设置数据类型
						p_map.define += '\nvar %s = NULL\n' % i[0]
						arr_getset.push_back('\nfunc get_%s() -> %s:' % [i_0_snake, 
							i[4] if i[1] == "Object" else i[1]])
						arr_getset.push_back('\n\treturn %s\n\t' % i[0])
						arr_getset.push_back('\nfunc set_%s(p_%s: %s):' % [i_0_snake, i_0_snake, 
							i[4] if i[1] == "Object" else i[1]])
						arr_getset.push_back('\n\t%s = p_%s' % [i[0], i_0_snake])
						arr_getset.push_back('\n\tvalue_changed.emit("%s", %s)\n\t' % [i_0_snake, i[0]])
					else:
						p_map.comment = '\n## %sEntity. %s' % [i[1], i[3]]
						p_map.define += '\nvar %s: %sEntity\n' % [i[0], i[1]]
						arr_getset.push_back('\nfunc get_%s() -> %sEntity:' % [i_0_snake, i[1]])
						arr_getset.push_back('\n\treturn %s\n\t' % i[0])
						arr_getset.push_back('\nfunc set_%s(p_%s: %sEntity):' % [i_0_snake, i_0_snake, i[1]])
						arr_getset.push_back('\n\t%s = p_%s' % [i[0], i_0_snake])
						arr_getset.push_back('\n\tvalue_changed.emit("%s", %s)\n\t' % [i_0_snake, i[0]])
						
				if e_map.has(i[0]):
					var old_p_map = e_map[i[0]]
					if old_p_map.comment != p_map.comment:
						push_error("Detect inconsistent comment of property: `%s.%s`, 1: `%s`, 2: `%s`." %[
							en_ns, i[0], old_p_map.comment, p_map.comment])
					if old_p_map.define != p_map.define:
						push_error("Detect inconsistent defination of property: `%s.%s`, 1: `%s`, 2: `%s`." %[
							en_ns, i[0], old_p_map.define, p_map.define])
					if old_p_map.getset != p_map.getset:
						push_error("Detect inconsistent getset of property: `%s.%s`, 1: `%s`, 2: `%s`." %[
							en_ns, i[0], "".join(old_p_map.define), "".join(p_map.define)])
				else:
					e_map[i[0]] = p_map
					
		# <sql>
		var vo_ids = {} # namespace => vo_id
		var select_use_db = false # <select>标签是否使用databaseId属性
		if not has_asso_collec:
			select_use_db = true
			vo_ids[leading_db_name + "." + leading_table_name] = leading_result_map_id
			var vo = ""
			if option_button_result_map_mode.selected == RESULT_MAP_MODE.SIMPLEST:
				vo = "select * from %s" % leading_table_name
			else:
				vo = "select %s from %s" % [", ".join(arr_columns[lead_node_name]), leading_table_name]
			xml_arr.push_back('\n\t<sql id="%sVo">\n\t\t%s\n\t</sql>\n\t' % \
				[leading_result_map_id, split_for_long_content(vo, "\n\t\t")])
		# nesting select 不使用left join，直接select主表即可，但是有多个sql
		elif option_button_link.selected == LINK_WAY.NESTING_SELECT:
			select_use_db = true
			for node_name in linked_nodes:
				# HELPER 不生成vo、xml mapper
				if graph_edit.is_helper_node(nodes_map[node_name]):
					continue
					
				var data = nodes_map[node_name].get_meta("data") as Dictionary
				var db_name = data.db_name as String
				var table_name = data.table_name as String
				var ns = db_name + "." + table_name
				var id = graph_edit.get_node_extra(nodes_map[node_name]).link_prop_type.to_camel_case()
				if not vo_ids.has(ns):
					var count = 1
					for i in vo_ids:
						if vo_ids[i].begins_with(id):
							count += 1
					if count != 1:
						id += "_" + str(count)
					vo_ids[db_name + "." + table_name] = id
					var vo = ""
					if option_button_result_map_mode.selected == RESULT_MAP_MODE.SIMPLEST:
						vo = "select * from %s" % table_name
					else:
						vo = "select %s from %s" % [
							", ".join(arr_columns[node_name]), table_name]
					xml_arr.push_back('\n\t<sql id="%sVo">\n\t\t%s\n\t</sql>\n\t' % \
						[id, split_for_long_content(vo, "\n\t\t")])
		# nesting resultMap 需要使用left join，把所有表形成一条sql
		else:
			vo_ids[leading_db_name + "." + leading_table_name] = leading_result_map_id
			var vo = ""
			var all_column_name = []
			var all_table_alias_simplest_fields = []
			for node_n in arr_columns:
				# helper不拉取数据
				if graph_edit.is_helper_node(nodes_map[node_n]):
					continue
				all_table_alias_simplest_fields.push_back(table_alias[node_n].substr(0, 2) + ".*")
				for c in arr_columns[node_n]:
					all_column_name.push_back(
						table_alias[node_n].substr(0, 2) + "." + c + \
						" as " + table_alias[node_n] + c
					)
			var leading = true
			for node_name in linked_nodes:
				var t_alias = table_alias[node_name].substr(0, 2)
				# first is leading node
				if leading:
					leading = false
					if option_button_result_map_mode.selected == RESULT_MAP_MODE.SIMPLEST:
						vo = split_for_long_content("select %s from %s.%s %s" % [", ".join(all_table_alias_simplest_fields), 
							leading_db_name, leading_table_name, t_alias], "\n\t\t")
					else:
						vo = "select %s \n\t\tfrom %s.%s %s" % [
							split_for_long_content(", ".join(all_column_name), "\n\t\t"),
							leading_db_name, leading_table_name, t_alias
						]
				else:
					var db_name = null
					var table_name = null
					var acond = []
					for f in node_pair:
						for t in node_pair[f]:
							if t == node_name:
								db_name = node_pair[f][t].db_name
								table_name = node_pair[f][t].table_name
								var alias0 = table_alias[f].substr(0, 2)
								var alias1 = table_alias[t].substr(0, 2)
								for k in node_pair[f][t].link_col:
									acond.push_back('%s.%s == %s.%s' % [
										alias1, k[1], alias0, k[0]])
								break
					vo += "\n\t\tleft join %s.%s %s on %s" % [
						db_name, table_name, t_alias, " and ".join(acond)
					]
			xml_arr.push_back('\n\t<sql id="%sVo">\n\t\t%s\n\t</sql>\n\t' % \
				[leading_result_map_id, vo])
				
		# mapper_arr
		var mp_id = '%s.%s' % [leading_db_name, leading_mapper_n]
		if mapper_map.has(mp_id):
			var count = 1
			for i in mapper_map:
				if i.begins_with(mp_id):
					count += 1
			if count != 1:
				leading_mapper_n += str(count)
				mp_id += str(count)
		var mapper_arr = ['@tool\nextends GBatisMapper\nclass_name %s\n' % leading_mapper_n]
		mapper_map[mp_id] = mapper_arr
		
		# prepare somthing
		var props = graph_edit.get_node_props(nodes_map[lead_node_name])
		var pk_col = []
		var pk_prop = []
		var pk_type = []
		for i in nodes_map[lead_node_name].get_meta("data").columns:
			if i.PK:
				pk_col.push_back(i["Column Name"])
				pk_prop.push_back(props[i["Column Name"]])
				pk_type.push_back(i["Data Type"])
		var pk_prop_snake = pk_prop.map(func(v): return v.to_snake_case())
		
		# <select> leading table: one by primary, one by entity and list by entity
		for method_surfix in ["_by_%s", "", "_list"]:
			var leading_method = 'select_%s%s' % [leading_table_name_snake, method_surfix]
				
			if method_surfix == "_by_%s":
				leading_method = leading_method % ("_".join(pk_prop_snake))
				
			# mapper_arr
			if method_surfix == "_by_%s":
				var args = []
				for i in pk_prop_snake.size():
					args.push_back('%s: %s' % [pk_prop_snake[i], type_string(pk_type[i])])
				mapper_arr.push_back('\nfunc %s(%s) -> %s:' % [
					leading_method, ", ".join(args), leading_entity_n
				])
				mapper_arr.push_back('\n\treturn query("%s", %s)\n\t' % [
					leading_method, ", ".join(pk_prop_snake)
				])
			else:
				mapper_arr.push_back('\nfunc %s(%s: %s) -> ' % [
					leading_method, leading_result_map_id, leading_entity_n
				])
				if method_surfix == "":
					mapper_arr.push_back('%s:' % leading_entity_n)
				else:
					mapper_arr.push_back('Array[%s]:' % leading_entity_n)
				mapper_arr.push_back('\n\treturn query("%s", %s)\n\t' % [
					leading_method, leading_result_map_id
				])
				
			xml_arr.push_back('\n\t<select id="%s" resultMap="%s"%s>' % \
				[leading_method, leading_result_map_id + "Result",
				(' databaseId="%s"' % leading_db_name) if select_use_db else ""])
			xml_arr.push_back('\n\t\t<include refid="%sVo"/>' % leading_result_map_id)
			
			if method_surfix == "_by_%s":
				var args = []
				for i in pk_col.size():
					var content = '%s == #{%s}' % [pk_col[i], pk_prop_snake[i]]
					if has_asso_collec and \
					option_button_link.selected != LINK_WAY.NESTING_SELECT:
						content = table_alias[lead_node_name].substr(0, 2) + "." + content
					args.push_back(content)
				xml_arr.push_back('\n\t\twhere %s' % ', '.join(args))
			else:
				xml_arr.push_back('\n\t\t<where>')
				for i in nodes_map[lead_node_name].get_meta("data").columns:
					var test = null
					var content = null
					#test = '%s != %s' % [
						#props[i["Column Name"]], default_val(i["Data Type"])]
					test = '%s != null' % props[i["Column Name"]]
					content = '%s == #{%s}' % [i["Column Name"], props[i["Column Name"]]]
					if has_asso_collec and \
					option_button_link.selected != LINK_WAY.NESTING_SELECT:
						content = table_alias[lead_node_name].substr(0, 2) + "." + content
					xml_arr.push_back('\n\t\t\t<if test="%s">and %s</if>' % [test, content])
				xml_arr.push_back('\n\t\t</where>')
			xml_arr.push_back('\n\t</select>\n\t')
			
		for m in arr_method:
			# mapper_arr
			var arg_names = []
			var args = []
			for i in m.arg_names.size():
				arg_names.push_back(m.arg_names[i].to_snake_case())
				args.push_back('%s: %s' % [
					arg_names.back(), type_string(m.arg_types[i])])
			var return_type = null
			# WARNING m.info在节点前面连接了helper的情况下，只能使用节点本身相关的信息，
			# 不能使用前面连接helper节点的信息，因为它可能（也许未来某个版本会支持）前面连
			# 了多个helper，但是只提供了一个info在这里。
			if m.info.link_type == graph_edit.LINK_TYPE.ASSOCIATION:
				return_type = m.info.link_prop_type.capitalize().replace(" ", "") + "Entity"
			else:
				return_type = 'Array[%sEntity]' % m.info.link_prop_type
			mapper_arr.push_back('\nfunc %s(%s) -> %s:' % [
				m.id, ", ".join(args), return_type])
			mapper_arr.push_back('\n\treturn query("%s", %s)\n\t' % [
				m.id, ", ".join(arg_names)])
				
			# xml_arr
			if m.from_helper:
				var cmds = get_helpers_left_join_cmds(m.info.node, node_to_from_map)
				xml_arr.push_back('\n\t<select id="%s" resultMap="%s">' % [
					m.id, m.result_map])
				xml_arr.push_back('\n\t\t' + '\n\t\t'.join(cmds.select))
				xml_arr.push_back('\n\t\t' + '\n\t\t'.join(cmds.left_join))
				xml_arr.push_back('\n\t\twhere %s' % (' and '.join(cmds.where)))
			else:
				var acond = []
				for arg in m.arg_names:
					acond.push_back('%s == #{%s}' % [arg, arg.to_snake_case()])
					
				xml_arr.push_back('\n\t<select id="%s" resultMap="%s"%s>' %
					[m.id, m.result_map, 
					(' databaseId="%s"' % m.db_name) if select_use_db else ""])
				xml_arr.push_back('\n\t\t<include refid="%sVo"/>' % vo_ids[m.namespace])
				xml_arr.push_back('\n\t\twhere %s' % (" and ".join(acond)))
			xml_arr.push_back('\n\t</select>\n\t')
			
		# update mapper
		mapper_arr.push_back('\nfunc update_%s(%s: %s) -> int:' % [
			leading_table_name_snake, leading_result_map_id, leading_entity_n
		])
		mapper_arr.push_back('\n\treturn query("update_%s", %s)\n\t' % [
			leading_table_name_snake, leading_result_map_id
		])
		
		# <update> leading table
		xml_arr.push_back('\n\t<update id="update_%s" databaseId="%s">' % \
			[leading_table_name_snake, leading_db_name])
		xml_arr.push_back('\n\t\tupdate %s' % leading_table_name)
		xml_arr.push_back('\n\t\t<set>')
		for i in nodes_map[lead_node_name].get_meta("data").columns:
			#var test = '%s != %s' % [props[i["Column Name"]], 
				#default_val(i["Data Type"])]
			var test = '%s != null' % props[i["Column Name"]]
			var content = '%s = #{%s},' % [i["Column Name"], props[i["Column Name"]]]
			xml_arr.push_back('\n\t\t\t<if test="%s">%s</if>' % [test, content])
		xml_arr.push_back('\n\t\t</set>')
		xml_arr.push_back('\n\t</update>\n\t')
		
		# insert mapper
		mapper_arr.push_back('\nfunc insert_%s(%s: %s) -> int:' % [
			leading_table_name_snake, leading_result_map_id, leading_entity_n
		])
		mapper_arr.push_back('\n\treturn query("insert_%s", %s)\n\t' % [
			leading_table_name_snake, leading_result_map_id
		])
		
		# <insert> leading table
		xml_arr.push_back('\n\t<insert id="insert_%s" databaseId="%s">' % \
			[leading_table_name_snake, leading_db_name])
		xml_arr.push_back('\n\t\tinsert into %s(' % leading_table_name)
		xml_arr.push_back('\n\t\t\t<trim suffixOverrides=",">')
		for i in nodes_map[lead_node_name].get_meta("data").columns:
			#var test = '%s != %s' % [props[i["Column Name"]], 
				#default_val(i["Data Type"])]
			var test = '%s != null' % props[i["Column Name"]]
			xml_arr.push_back(
				'\n\t\t\t\t<if test="%s">%s,</if>' % [test, i["Column Name"]])
		xml_arr.push_back('\n\t\t\t</trim>')
		xml_arr.push_back('\n\t\t)values(')
		xml_arr.push_back('\n\t\t\t<trim suffixOverrides=",">')
		for i in nodes_map[lead_node_name].get_meta("data").columns:
			#var test = '%s != %s' % [props[i["Column Name"]], 
				#default_val(i["Data Type"])]
			var test = '%s != null' % props[i["Column Name"]]
			xml_arr.push_back(
				'\n\t\t\t\t<if test="%s">#{%s},</if>' % [test, props[i["Column Name"]]])
		xml_arr.push_back('\n\t\t\t</trim>')
		xml_arr.push_back('\n\t\t)')
		xml_arr.push_back('\n\t</insert>\n\t')
		
		# delete mapper
		var a_args = []
		for i in pk_prop_snake.size():
			a_args.push_back('%s: %s' % [pk_prop_snake[i], type_string(pk_type[i])])
		mapper_arr.push_back('\nfunc delete_%s_by_%s(%s) -> int:' % [
			leading_table_name_snake, "_".join(pk_prop_snake), ", ".join(a_args)
		])
		mapper_arr.push_back('\n\treturn query("delete_%s", %s)\n\t' % [
			leading_table_name_snake, "_".join(pk_prop_snake)
		])
		
		# <delete> leading table
		xml_arr.push_back('\n\t<delete id="delete_%s_by_%s" databaseId="%s">' % \
			[leading_table_name_snake, "_".join(pk_prop_snake), 
			leading_db_name])
		var cond = []
		for i in pk_col.size():
			cond.push_back('%s == #{%s}' % [pk_col[i], pk_prop[i]])
		xml_arr.push_back('\n\t\tdelete from %s where %s' % [
			leading_table_name, " and ".join(cond)])
		xml_arr.push_back('\n\t</delete>\n\t')
		
		# end
		xml_arr.push_back('\n</mapper>')
		xml_arr[0] = xml_arr[0] % leading_mapper_n # replace namespace
		var xml_ns = '%s.%s' % [leading_db_name, leading_mapper_n]
		if xml_map.has(xml_ns):
			var a_index = 1
			for n: String in xml_map:
				if n.begins_with(xml_ns):
					a_index += 1
			if a_index > 1:
				xml_ns = '%s.%s%s' % [leading_db_name, leading_mapper_n, a_index]
		xml_map[xml_ns] = xml_arr
		
	# 归一化 entity_map
	for en_ns in entity_map:
		for p in entity_map_2[en_ns]:
			entity_map[en_ns].push_back(entity_map_2[en_ns][p].comment)
			entity_map[en_ns].push_back(entity_map_2[en_ns][p].define)
		for p in entity_map_2[en_ns]:
			entity_map[en_ns].append_array(entity_map_2[en_ns][p].getset)
			
	# popup confirm dialog
	popup_generate_dialog(xml_map, mapper_map, entity_map)
	
func is_shadowing(p_identifier: String) -> bool:
	if GDSQL.SQLExpression.has_utility_function(p_identifier):
		return true
		
	if ClassDB.class_exists(p_identifier):
		return true
		
	for i in ProjectSettings.get_global_class_list():
		if i.class == p_identifier:
			return true
			
	if GDSQL.DataTypeDef.DATA_TYPE_COMMON_NAMES.has(p_identifier):
		return true
		
	return false
	
var _generate_dialog
func popup_generate_dialog(xml_map, mapper_map, entity_map):
	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var line_edit_path = LineEdit.new()
	line_edit_path.placeholder_text = "Save path"
	line_edit_path.caret_blink = true
	line_edit_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line_edit_path.text = line_edit_save_path.text
	line_edit_path.text_changed.connect(func(t):
		if line_edit_save_path.text != t:
			line_edit_save_path.text = t
	)
	var ref = []
	ref.push_back(func(t):
		if line_edit_path:
			if line_edit_path.text != t:
				line_edit_path.text = t
		else:
			line_edit_save_path.text_changed.disconnect(ref[0])
	)
	line_edit_save_path.text_changed.connect(ref[0])
	hbox.add_child(line_edit_path)
	
	var option_button_choose = OptionButton.new()
	option_button_choose.add_item("Resource")
	option_button_choose.add_item("UserData")
	option_button_choose.add_item("FileSystem")
	option_button_choose.tooltip_text = "Pick a path from Resource, UserData or FileSystem."
	option_button_choose.allow_reselect = true
	option_button_choose.selected = option_button_choose_path.selected
	hbox.add_child(option_button_choose)
	
	var btn_save_all = Button.new()
	btn_save_all.icon = get_theme_icon("Save", "EditorIcons")
	btn_save_all.text = "Save All"
	hbox.add_child(btn_save_all)
	
	var filter_edit = LineEdit.new()
	filter_edit.placeholder_text = "Filter Files"
	filter_edit.right_icon = get_theme_icon("Search", "EditorIcons")
	filter_edit.clear_button_enabled = true
	filter_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var tree = Tree.new()
	tree.columns = 4
	tree.hide_root = true
	tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.set_column_expand(0, false)
	tree.set_column_expand(3, false) # for diff info
	
	var root = tree.create_item()
	var check_all_item = tree.create_item(root)
	check_all_item.set_text(1, "Select All")
	check_all_item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
	check_all_item.set_editable(0, true)
	
	var edit_history = {}
	tree.set_meta("edit_history", edit_history)
	var refresh_tree = func():
		var filter_text = filter_edit.text.strip_edges()
		# remove all item, except check_all_item
		for i in range(root.get_child_count() - 1, 0, -1):
			root.remove_child(root.get_child(i))
		for map in [xml_map, mapper_map, entity_map]:
			for i: String in map:
				var file_name = i.get_slice(".", 1) + (".xml" if map == xml_map else ".gd")
				if not (filter_text == "" or i.containsn(filter_text) or file_name.containsn(filter_text)):
					continue
				var item = tree.create_item(root)
				item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
				item.set_checked(0, check_all_item.is_checked(0))
				item.set_editable(0, true)
				item.set_text(1, i)
				item.set_meta("file_name", file_name)
				if edit_history.has(file_name):
					item.set_metadata(0, edit_history[file_name])
					item.set_meta("origin", ''.join(map[i]) + '\n')
					item.set_text(2, file_name + "(*)")
					item.add_button(2, get_theme_icon("RotateLeft", "EditorIcons"), 3, false, tr("Revert"))
				else:
					item.set_metadata(0, ''.join(map[i]) + '\n')
					item.set_meta("origin", item.get_metadata(0))
					item.set_text(2, file_name)
					item.add_button(2, CompressedTexture2D.new(), 3, true, tr("Revert"))
				item.add_button(2, get_theme_icon("Edit", "EditorIcons"), 0, false, tr("Edit"))
				item.add_button(2, get_theme_icon("Save", "EditorIcons"), 1, false, tr("Save As..."))
				item.add_button(2, get_theme_icon("ActionCopy", "EditorIcons"), 2, false, tr("Copy"))
				item.add_button(2, get_theme_icon("HSplitContainer", "EditorIcons"), 4, false, tr("Compare"))
				_refresh_item_diff(item)
				
	refresh_tree.call()
	filter_edit.text_changed.connect(refresh_tree.unbind(1))
	line_edit_path.text_changed.connect(func(_text):
		for item in root.get_children():
			if item != check_all_item:
				_refresh_item_diff(item)
	)
	
	btn_save_all.pressed.connect(func():
		if line_edit_path.text == "":
			GDSQL.WorkbenchManager.create_accept_dialog(tr("Save path is empty!"))
			return
		for i: TreeItem in root.get_children():
			if i.get_text(2) != "":
				var content = i.get_metadata(0)
				var path = line_edit_path.text.strip_edges().path_join(i.get_meta("file_name"))
				var file = FileAccess.open(path, FileAccess.WRITE)
				file.store_string(content)
				file.flush()
				file = null
		var old_icon = btn_save_all.icon
		btn_save_all.icon = get_theme_icon("ImportCheck", "EditorIcons")
		btn_save_all.disabled = true
		EditorInterface.get_editor_toaster().push_toast(
			"Please refocus Godot editor window to import file(s).", EditorToaster.SEVERITY_WARNING)
		#EditorInterface.get_resource_filesystem().scan()
		#if _generate_dialog:
			## scan后窗口可能被最小化了，所以用窗口的方法，能重新激活
			#while EditorInterface.get_resource_filesystem().is_scanning():
				#await get_tree().process_frame
			#_generate_dialog.transient = false
			#if _generate_dialog.mode != Window.MODE_WINDOWED:
				#_generate_dialog.mode = Window.MODE_WINDOWED
			#_generate_dialog.grab_focus()
		await get_tree().create_timer(2).timeout
		if btn_save_all:
			btn_save_all.icon = old_icon
			btn_save_all.disabled = false
	)
	
	tree.item_edited.connect(func():
		var selected_item = tree.get_selected()
		if tree.get_selected() == check_all_item:
			for i: TreeItem in root.get_children():
				i.set_checked(0, check_all_item.is_checked(0))
		elif selected_item:
			if selected_item.is_checked(0):
				var all_checked = true
				for i: TreeItem in root.get_children():
					if i == check_all_item:
						continue
					if not i.is_checked(0):
						all_checked = false
						break
				check_all_item.set_checked(0, all_checked)
			else:
				check_all_item.set_checked(0, false)
	)
	tree.button_clicked.connect(
		func(item: TreeItem, _column: int, id: int, _mouse_button_index: int):
			item.select(2)
			match id:
				0: # Edit
					popup_edit_dialog(item)
				1: # Save As...
					popup_saveas_dialog(option_button_choose.selected, item, 
						line_edit_path.text)
				2: # Copy to clipboard
					DisplayServer.clipboard_set(item.get_metadata(0))
				3: # Revert
					item.get_tree().get_meta("edit_history").erase(item.get_meta("file_name"))
					item.set_metadata(0, item.get_meta("origin"))
					item.set_button(2, 0, CompressedTexture2D.new())
					item.set_button_disabled(2, 0, true)
					item.set_button_tooltip_text(2, 0, "")
					if item.get_text(2).ends_with("(*)"):
						item.set_text(2, item.get_meta("file_name"))
					_refresh_item_diff(item)
				4: # Compare
					var path = line_edit_path.text.strip_edges().path_join(item.get_meta("file_name"))
					var arr_content = [{
						"title": "[old] " + item.get_meta("file_name"),
						"file": item.get_meta("file_name"),
						"content": FileAccess.open(path, FileAccess.READ).get_as_text(),
						"item": null,
					}, {
						"title": "[new] " + item.get_meta("file_name"),
						"file": item.get_meta("file_name"),
						"content": item.get_metadata(0),
						"item": item,
					}]
					popup_diff_dialog(arr_content, true)
	)
	tree.ready.connect(func():
		check_all_item.set_checked(0, false)
		tree.get_parent_control().size_flags_vertical = Control.SIZE_EXPAND_FILL
	)
	
	var arr = [[hbox], [filter_edit], [tree]] as Array[Array]
	
	var confirm = func():
		if line_edit_path.text == "":
			GDSQL.WorkbenchManager.create_accept_dialog(tr("Save path is empty!"))
			return [true, null]
		var save_at_least_one = 0
		for i: TreeItem in root.get_children():
			if i.get_text(2) != "" and i.is_checked(0):
				var content = i.get_metadata(0)
				var path = line_edit_path.text.strip_edges().path_join(i.get_meta("file_name"))
				var file = FileAccess.open(path, FileAccess.WRITE)
				file.store_string(content)
				file.flush()
				file = null
				save_at_least_one += 1
		if save_at_least_one > 0:
			# TODO FIXME Editor will crash if scan, see https://github.com/godotengine/godot/issues/108003
			#if not EditorInterface.get_resource_filesystem().is_scanning():
				#EditorInterface.get_resource_filesystem().scan()
			EditorInterface.get_editor_toaster().push_toast("Please refocus Godot editor window to import file(s).")
			_generate_dialog.get_ok_button().disabled = true
			_generate_dialog.get_ok_button().text = "%s file(s) saved!" % save_at_least_one
			await get_tree().create_timer(2).timeout
			if _generate_dialog:
				_generate_dialog.get_ok_button().disabled = false
				_generate_dialog.get_ok_button().text = "Save"
			return [true, null]
		else:
			GDSQL.WorkbenchManager.create_accept_dialog(tr("None selected."))
			return [true, null]
			
	var defer = func(_a, _b):
		_generate_dialog = null
		hbox.queue_free()
		tree.queue_free()
	_generate_dialog = GDSQL.WorkbenchManager.create_custom_dialog(arr, confirm, Callable(), defer, 0.3)
	#_generate_dialog.exclusive = false
	#_generate_dialog.transient = false
	#_generate_dialog.transient_to_focused = true
	#_generate_dialog.always_on_top = true
	_generate_dialog.minimize_disabled = false
	_generate_dialog.maximize_disabled = false
	_generate_dialog.add_button("Inspect", true, "Inspect")
	_generate_dialog.get_ok_button().text = "Save"
	option_button_choose.item_selected.connect(
		_on_option_button_choose_path_item_selected.bind(line_edit_path, _generate_dialog))
	_generate_dialog.custom_action.connect(func(action):
		match action:
			"Inspect":
				var arr_content = []
				for i: TreeItem in root.get_children():
					if i.is_checked(0):
						if i.get_text(2) != "":
							arr_content.push_back({
								"title": i.get_meta("file_name"),
								"file": i.get_meta("file_name"),
								"content": i.get_metadata(0),
								"item": i,
							})
				popup_diff_dialog(arr_content)
	)
	
func _refresh_item_diff(item: TreeItem):
	if item.get_button_by_id(3, 5) > -1:
		item.erase_button(3, item.get_button_by_id(3, 5))
	var path = line_edit_save_path.text.strip_edges().path_join(item.get_meta("file_name"))
	if FileAccess.file_exists(path):
		var file_content = FileAccess.open(path, FileAccess.READ).get_as_text()
		item.set_button_disabled(2, item.get_button_by_id(2, 4), false)
		if item.get_metadata(0) == file_content:
			item.set_button_color(2, item.get_button_by_id(2, 4), Color.WHITE)
		else:
			item.set_button_color(2, item.get_button_by_id(2, 4), Color(2, 0.647059, 0, 1))
			var diffs = GDSQL.DiffHelper.compare(file_content.split("\n"), item.get_metadata(0).split("\n"))
			var texture = GDSQL.DiffLabelTexture.new()
			texture.remove_count = diffs[0].size()
			texture.add_count = diffs[1].size()
			item.add_button(3, texture, 5, true)
	else:
		item.set_button_disabled(2, item.get_button_by_id(2, 4), true)
		
func comfirm_save(path: String = "", item: TreeItem = null, editor_file_dialog = null):
	if path == "":
		path = editor_file_dialog.current_path
	var content = item.get_metadata(0)
	var file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.flush()
	file = null
	var old_btn = item.get_button(2, 2)
	item.set_button(2, 2, get_theme_icon("ImportCheck", "EditorIcons"))
	item.set_button_disabled(2, 2, true)
	
	# refresh diff
	_refresh_item_diff(item)
	
	EditorInterface.get_editor_toaster().push_toast(
		"Please refocus Godot editor window to import file(s).", EditorToaster.SEVERITY_WARNING)
	#EditorInterface.get_resource_filesystem().scan()
	#if _generate_dialog:
		# scan后窗口可能被最小化了，所以用窗口的方法，能重新激活
		#while EditorInterface.get_resource_filesystem().is_scanning():
			#await get_tree().process_frame
		#_generate_dialog.transient = false
		#if _generate_dialog.mode != Window.MODE_WINDOWED:
			#_generate_dialog.mode = Window.MODE_WINDOWED
		#_generate_dialog.grab_focus()
	await get_tree().create_timer(2).timeout
	if item:
		item.set_button(2, 2, old_btn)
		item.set_button_disabled(2, 2, false)
	return [false, false]
	
func popup_saveas_dialog(access: int, item: TreeItem, dir: String):
	var editor_file_dialog = EditorFileDialog.new()
	editor_file_dialog.disable_overwrite_warning = true
	editor_file_dialog.access = access
	if item.get_text(2).ends_with(".xml") or item.get_text(2).ends_with(".xml(*)"):
		editor_file_dialog.add_filter("*.xml", "XML File")
	else:
		editor_file_dialog.add_filter("*.gd", "GDScript File")
	editor_file_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	editor_file_dialog.ready.connect(func():
		if dir != "":
			editor_file_dialog.current_dir = dir
		editor_file_dialog.current_file = item.get_meta("file_name")
	)
	
	editor_file_dialog.file_selected.connect(
		self.comfirm_save.bind(item, editor_file_dialog), CONNECT_DEFERRED)
		
	var defer = func(_confirmed, _dummy):
		editor_file_dialog.queue_free()
	GDSQL.WorkbenchManager.popup_user_dialog(editor_file_dialog, Callable(), Callable(), defer, 0.5)
	
func reset_content(item: TreeItem, editor, arr_editor = null, show_diff: bool = false):
	if item:
		item.set_metadata(0, editor.text_editor.text)
		if item.get_meta("origin") == editor.text_editor.text:
			item.set_button(2, 0, CompressedTexture2D.new())
			item.set_button_disabled(2, 0, true)
			item.set_button_tooltip_text(2, 0, "Edit")
			item.get_tree().get_meta("edit_history").erase(item.get_meta("file_name"))
			if item.get_text(2).ends_with("(*)"):
				item.set_text(2, item.get_meta("file_name"))
		else:
			item.get_tree().get_meta("edit_history")[item.get_meta("file_name")] = item.get_metadata(0)
			if not item.get_text(2).ends_with("(*)"):
				item.set_button(2, 0, get_theme_icon("RotateLeft", "EditorIcons"))
				item.set_button_disabled(2, 0, false)
				item.set_button_tooltip_text(2, 0, "Revert")
				item.set_text(2, item.get_meta("file_name") + "(*)")
				
		_refresh_item_diff(item)
		
	# 有做对比的editor
	if show_diff and arr_editor:
		if arr_editor[1] == editor:
			_refresh_diff_show(arr_editor[0].text_editor, editor.text_editor)
		else:
			_refresh_diff_show(editor.text_editor, arr_editor[1].text_editor)
			
func popup_edit_dialog(item: TreeItem):
	var editor = preload("res://addons/gdsql/gxml/editor/xml_editor.tscn").instantiate()
	editor.ready.connect(func():
		editor.get_parent_control().size_flags_vertical = Control.SIZE_EXPAND_FILL
		editor.toggle_scripts_button.hide()
		var code_edit = editor.text_editor as CodeEdit
		code_edit.syntax_highlighter = GDScriptSyntaxHighlighter.new()
		code_edit.gutters_draw_line_numbers = true
		code_edit.draw_tabs = true
		code_edit.highlight_all_occurrences = true
		code_edit.add_theme_color_override(&"word_highlighted_color", Color(Color.YELLOW, 0.3))
		code_edit.highlight_current_line = true
		code_edit.minimap_draw = true
		code_edit.caret_blink = true
		code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		code_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
		code_edit.text = item.get_metadata(0)
		code_edit.text_changed.connect(reset_content.bind(item, editor))
		code_edit.text_set.connect(reset_content.bind(item, editor))
		code_edit.selecting_enabled = false
		await get_tree().process_frame
		code_edit.selecting_enabled = true
	)
	
	var arr = [[editor]] as Array[Array]
	var defer = func(_confirmed, _dummy):
		if editor.text_editor.text_changed.is_connected(self.reset_content):
			editor.text_editor.text_changed.disconnect(self.reset_content)
		if editor.text_editor.text_set.is_connected(self.reset_content):
			editor.text_editor.text_set.disconnect(self.reset_content)
		editor.queue_free()
		
	var dialog = GDSQL.WorkbenchManager.create_custom_dialog(arr, Callable(), Callable(), defer, 0.6)
	dialog.exclusive = false
	dialog.minimize_disabled = false
	dialog.maximize_disabled = false
	dialog.get_cancel_button().hide()
	
func _get_commit_line_gutter(editor: TextEdit):
	for i in editor.get_gutter_count():
		if editor.get_gutter_name(i) == "commit_line_gutter":
			return i
	return -1
	
func _refresh_diff_show(editor1: TextEdit, editor2: TextEdit):
	var diffs = GDSQL.DiffHelper.compare(editor1.text.split("\n"), editor2.text.split("\n"))
	for i in editor1.get_line_count():
		editor1.set_line_background_color(i, editor1.get_theme_color(&"background_color"))
		
	# 清空gutter和行背景色
	var commit_line_gutter1 = _get_commit_line_gutter(editor1)
	for i in editor1.get_line_count():
		editor1.set_line_gutter_icon(i, commit_line_gutter1, null)
		editor1.set_line_gutter_clickable(i, commit_line_gutter1, false)
		if editor1.get_line_background_color(i) != COLOR_DIFF_MERGE_INSERTED:
			editor1.set_line_background_color(i, editor2.get_theme_color(&"background_color"))
			
	var commit_line_gutter2 = _get_commit_line_gutter(editor2)
	for i in editor2.get_line_count():
		editor2.set_line_gutter_icon(i, commit_line_gutter2, null)
		editor2.set_line_gutter_clickable(i, commit_line_gutter2, false)
		if editor2.get_line_background_color(i) != COLOR_DIFF_MERGE_INSERTED:
			editor2.set_line_background_color(i, editor2.get_theme_color(&"background_color"))
			
	# 左边被删除的行
	for i in diffs[0]:
		editor1.set_meta("gutter_mapping", diffs[2])
		editor1.set_line_gutter_icon(i, commit_line_gutter1, get_theme_icon("ArrowRight", "EditorIcons"))
		editor1.set_line_gutter_clickable(i, commit_line_gutter1, true)
		editor1.set_line_background_color(i, COLOR_DIFF_BASIC_REMOVED)
	# 右边新增的行
	for i in diffs[1]:
		editor2.set_meta("gutter_mapping", diffs[2])
		# UPDATE: 把右边新增的行合并到左边并没有什么意义，所以右边不增加gutter了
		#editor2.set_line_gutter_icon(i, commit_line_gutter2, get_theme_icon("ArrowLeft", "EditorIcons"))
		#editor2.set_line_gutter_clickable(i, commit_line_gutter2, true)
		editor2.set_line_background_color(i, COLOR_DIFF_BASIC_ADDED)
		
func popup_diff_dialog(arr_content: Array, show_diff = false):
	if arr_content.is_empty():
		return
		
	var table = preload("res://addons/gdsql/table.tscn").instantiate()
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	table.row_expend_and_fill = true
	table.ready.connect(func():
		table.get_parent_control().size_flags_horizontal = Control.SIZE_EXPAND_FILL
		table.get_parent_control().size_flags_vertical = Control.SIZE_EXPAND_FILL
	)
	var arr_editor = []
	var arr_v_scroll_bar = []
	var columns = []
	var data = []
	var index = -1
	for i in arr_content:
		index += 1
		columns.push_back(i.title)
		var vbox = VBoxContainer.new()
		data.push_back(vbox)
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		
		var editor = preload("res://addons/gdsql/gxml/editor/xml_editor.tscn").instantiate()
		vbox.add_child(editor)
		arr_editor.push_back(editor)
		editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
		editor.ready.connect(func():
			editor.toggle_scripts_button.hide()
			var code_edit = editor.text_editor as CodeEdit
			if not (i.file as String).to_lower().ends_with(".xml"):
				code_edit.syntax_highlighter = GDScriptSyntaxHighlighter.new()
			arr_v_scroll_bar.push_back(code_edit.get_v_scroll_bar())
			code_edit.get_v_scroll_bar().value_changed.connect(func(v):
				for a_bar: VScrollBar in arr_v_scroll_bar:
					if a_bar != code_edit.get_v_scroll_bar():
						a_bar.value = v
			)
			editor.text_editor.caret_changed.connect(func():
				for a_editor in arr_editor:
					if a_editor != editor:
						(a_editor.text_editor as CodeEdit).get_v_scroll_bar().value = \
							(editor.text_editor as CodeEdit).get_v_scroll_bar().value
			)
			code_edit.gutters_draw_line_numbers = true
			code_edit.draw_tabs = true
			code_edit.highlight_all_occurrences = true
			code_edit.add_theme_color_override(&"word_highlighted_color", Color(Color.YELLOW, 0.3))
			code_edit.highlight_current_line = true
			code_edit.minimap_draw = true
			code_edit.caret_blink = true
			code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			code_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
			code_edit.text = i.content
			code_edit.selecting_enabled = false
			
			code_edit.text_changed.connect(reset_content.bind(i.item, editor, arr_editor, show_diff))
			code_edit.text_set.connect(reset_content.bind(i.item, editor, arr_editor, show_diff))
			
			if not i.item:
				code_edit.editable = false
				
			if show_diff:
				var commit_line_gutter = 1
				code_edit.add_gutter(commit_line_gutter)
				code_edit.set_gutter_name(commit_line_gutter, "commit_line_gutter")
				code_edit.set_gutter_clickable(commit_line_gutter, true)
				code_edit.set_gutter_overwritable(commit_line_gutter, true)
				code_edit.set_gutter_type(commit_line_gutter, TextEdit.GUTTER_TYPE_ICON)
				code_edit.set_gutter_width(commit_line_gutter, code_edit.get_line_height())
				code_edit.gutter_clicked.connect(_on_gutter_clicked.bind(
					index == 0, arr_editor, arr_content[index]))
					
			await get_tree().process_frame
			code_edit.selecting_enabled = true
		)
	for editor in arr_editor:
		editor.zoomed.connect(func(factor):
			for a_editor in arr_editor:
				if a_editor != editor:
					a_editor.set_zoom_factor(factor)
		)
		
	if show_diff and arr_editor.size() == 2:
		var t = create_tween()
		t.tween_callback(func():
			for i in arr_editor:
				while not i.ready:
					await get_tree().process_frame
			_refresh_diff_show(arr_editor[0].text_editor, arr_editor[1].text_editor)
		).set_delay(0.1)
		
	table.columns = columns
	table.datas = [data]
	table.support_select_border = false
	var arr = [[table]] as Array[Array]
	var defer = func(_confirmed, _dummy):
		for editor in arr_editor:
			if editor.text_editor.text_changed.is_connected(self.reset_content):
				editor.text_editor.text_changed.disconnect(self.reset_content)
			if editor.text_editor.text_set.is_connected(self.reset_content):
				editor.text_editor.text_set.disconnect(self.reset_content)
		arr_editor.clear()
		arr_v_scroll_bar.clear()
		table.queue_free()
	var dialog = GDSQL.WorkbenchManager.create_custom_dialog(arr, Callable(), Callable(), defer, 0.9)
	dialog.exclusive = false
	dialog.minimize_disabled = false
	dialog.maximize_disabled = false
	
func _on_gutter_clicked(line: int, gutter: int, is_left: bool, arr_editor: Array, _info):
	var left_edit: TextEdit = arr_editor[0].text_editor
	var right_edit: TextEdit = arr_editor[1].text_editor
	# 点的是左边窗口的gutter
	if is_left:
		if gutter == _get_commit_line_gutter(left_edit):
			var insert_line = GDSQL.DiffHelper.merge_delete_line_by_mapping(
				line, right_edit.get_line_count(), right_edit.get_meta("gutter_mapping"))
			right_edit.insert_line_at(insert_line, left_edit.get_line(line))
			await get_tree().create_timer(0.1).timeout
			right_edit.set_line_background_color(insert_line, COLOR_DIFF_MERGE_INSERTED)
	else:
		if gutter == _get_commit_line_gutter(right_edit):
			var insert_line = GDSQL.DiffHelper.merge_insert_line_by_mapping(
				line, left_edit.get_line_count(), left_edit.get_meta("gutter_mapping"))
			left_edit.insert_line_at(insert_line, right_edit.get_line(line))
			await get_tree().create_timer(0.1).timeout
			left_edit.set_line_background_color(insert_line, COLOR_DIFF_MERGE_INSERTED)
			
#func get_linked_nodes(node_pair: Dictionary, head_name, result: Array):
	#result.push_back(head_name)
	#if node_pair.has(head_name):
		#for to_node_name in node_pair[head_name]:
			#get_linked_nodes(node_pair, to_node_name, result)
			
func get_linked_nodes_bfs(node_pair: Dictionary, head_name):
	var result = []
	var queue = [head_name]
	while not queue.is_empty():  # 当队列不为空时循环
		var current_node = queue.pop_front()  # 从队列的左侧取出一个元素，实现先进先出
		if not result.has(current_node):
			result.push_back(current_node)  # 将当前节点添加到结果中
			if node_pair.has(current_node):  # 如果当前节点在节点对中
				for to_node_name in node_pair[current_node]:  # 遍历当前节点的所有邻接节点
					queue.push_back(to_node_name)  # 将邻接节点添加到队列的右侧
	return result
	
func default_val(type: int) -> String:
	return var_to_str(GDSQL.DataTypeDef.DEFUALT_VALUES[type]).replace('""', "''")
	
func get_max_col_name_length(columns: Array) -> int:
	var ret = 0
	for i in columns:
		ret = max(ret, i["Column Name"].length())
	return ret
	
func get_max_prop_name_length(props: Dictionary) -> int:
	var ret = 0
	for c in props:
		ret = max(ret, props[c].length())
	return ret
	
## ALERT 基于全英文内容，且不包含引号。一个单词不会被切分开。
func split_for_long_content(content: String, delimiter = "\n") -> String:
	const l = 50
	var total_l = content.length()
	if total_l <= l:
		return content
	var arr = []
	var start = 0
	while true:
		if start >= total_l:
			break
		if start + l >= total_l:
			arr.push_back(content.substr(start, l))
		# 不要把单词分开，找到下一个空格
		else:
			if content[start + l] == " ":
				arr.push_back(content.substr(start, l))
			else:
				var ll = content.find(" ", start + l)
				if ll == -1:
					arr.push_back(content.substr(start))
					break
				else:
					arr.push_back(content.substr(start, ll - start + 1))
					start = ll + 1
					continue
		if start + l >= total_l:
			break
		start += l
	return delimiter.join(arr)
	
func _on_option_button_link_item_selected(_index: int) -> void:
	change_tab_title.emit(self, get_meta("file_name") + "*")
	
func _on_button_add_include_pressed() -> void:
	EditorInterface.popup_quick_open(graph_edit.include_file, [&"GDMapperGraph"])
	
func _filter_node_list_changed(_p_filter: String, item: TreeItem = null):
	if item == null:
		item = tree_node_list_root
		
	var filter = line_edit_filter_node_list.text.strip_edges().to_lower()
	if filter == "":
		item.call_recursive(&"set_custom_color", 0, tree_node_list.get_theme_color(&"font_color"))
		item.call_recursive(&"set_visible", true)
		await _refresh_table_change_status()
		update_popup_panel_node_list_size()
		return true
		
	var find_any = item.get_text(0).to_lower().contains(filter)
	if find_any:
		item.set_custom_color(0, get_theme_color(&"accent_color", &"Editor"))
	else:
		item.set_custom_color(0, get_theme_color(&"font_disabled_color", &"Editor"))
		
	for i in item.get_children():
		if await _filter_node_list_changed(filter, i):
			find_any = true
			
	item.visible = find_any
	
	if item == tree_node_list_root:
		await _refresh_table_change_status()
		update_popup_panel_node_list_size()
		
	return find_any
	
func _on_button_node_list_toggled(toggled_on: bool) -> void:
	if toggled_on:
		var button_rect = get_screen_rect(button_node_list)
		var rect = button_rect
		rect.position.y = rect.end.y
		rect.size.y = 0
		popup_panel_node_list.popup(rect)
		update_popup_panel_node_list_size()
	else:
		popup_panel_node_list.hide()
		
func update_popup_panel_node_list_size():
	var button_rect = get_screen_rect(button_node_list)
	var sb_panel: StyleBox = popup_panel_node_list.get_theme_stylebox(&"panel")
	var max_width = get_max_item_width(tree_node_list_root) + \
		sb_panel.get_content_margin(SIDE_LEFT) + sb_panel.get_content_margin(SIDE_RIGHT)
	var last_item_rect = get_last_item_rect(tree_node_list_root)
	var sb_tree: StyleBox = tree_node_list.get_theme_stylebox(&"panel")
	var sb_sc: StyleBox = scroll_container_node_list.get_theme_stylebox(&"panel")
	var max_height = min(last_item_rect.end.y + line_edit_filter_node_list.size.y + 
		v_box_container_node_list.get_theme_constant(&"separation") + 
		sb_panel.get_content_margin(SIDE_TOP) + sb_panel.get_content_margin(SIDE_BOTTOM) +
		sb_tree.get_content_margin(SIDE_TOP) + sb_tree.get_content_margin(SIDE_BOTTOM) +
		sb_sc.get_content_margin(SIDE_TOP) + sb_sc.get_content_margin(SIDE_BOTTOM) +
		tree_node_list.get_theme_constant(&"v_separation"),
		
		DisplayServer.screen_get_size().y - button_rect.end.y - 
		sb_panel.get_content_margin(SIDE_TOP) - sb_panel.get_content_margin(SIDE_BOTTOM) -
		sb_tree.get_content_margin(SIDE_TOP) - sb_tree.get_content_margin(SIDE_BOTTOM) -
		sb_sc.get_content_margin(SIDE_TOP) - sb_sc.get_content_margin(SIDE_BOTTOM) - 
		tree_node_list.get_theme_constant(&"v_separation"))
	popup_panel_node_list.set_min_size(Vector2(max_width, max_height))
	popup_panel_node_list.set_max_size(Vector2(max_width, max_height))
	#await get_tree().process_frame
	#if popup_panel_node_list.position.y < button_rect.end.y:
		#var offset = button_rect.end.y - popup_panel_node_list.position.y
		#popup_panel_node_list.set_min_size(Vector2(max_width, max_height - offset))
		#popup_panel_node_list.set_max_size(Vector2(max_width, max_height - offset))
		#popup_panel_node_list.position.y += offset
		
func get_last_item_rect(tree_item: TreeItem):
	if tree_item.get_child_count() == 0:
		return tree_node_list.get_item_area_rect(tree_item)
	return get_last_item_rect(tree_item.get_children().back())
	
func get_max_item_width(tree_item: TreeItem):
	var max_width = tree_node_list.get_item_area_rect(tree_item).end.x
	for i in tree_item.get_children():
		max_width = max(max_width, get_max_item_width(i))
	return max_width
	
func get_screen_rect(control: Control):
	var xform = control.get_screen_transform()
	return Rect2(xform.get_origin(), xform.get_scale() * control.get_size())
	
func _on_popup_panel_node_list_popup_hide() -> void:
	button_node_list.button_pressed = false
	
func _on_sort_node_list_pressed(id: int):
	match id:
		# Default
		0: sort_tree_items(tree_node_list_root, func(a: TreeItem, b: TreeItem):
			return a.get_meta("_meta_graph_element").get_meta("_meta_add_index") < b.get_meta("_meta_graph_element").get_meta("_meta_add_index")
			)
		# Sort by Name (Ascending)
		1: sort_tree_items(tree_node_list_root, func(a: TreeItem, b: TreeItem):
			return a.get_text(0).to_lower() < b.get_text(0).to_lower()
			)
		# Sort by Name (Descending)
		2: sort_tree_items(tree_node_list_root, func(a: TreeItem, b: TreeItem):
			return a.get_text(0).to_lower() > b.get_text(0).to_lower()
			)
		# Sort by Position (Left to Right)
		3: sort_tree_items(tree_node_list_root, func(a: TreeItem, b: TreeItem):
			return a.get_meta("_meta_graph_element").position_offset.x < b.get_meta("_meta_graph_element").position_offset.x
			)
		# Sort by Position (Right to Left)
		4: sort_tree_items(tree_node_list_root, func(a: TreeItem, b: TreeItem):
			return a.get_meta("_meta_graph_element").position_offset.x > b.get_meta("_meta_graph_element").position_offset.x
			)
		# Sort by Position (Top to Bottom)
		5: sort_tree_items(tree_node_list_root, func(a: TreeItem, b: TreeItem):
			return a.get_meta("_meta_graph_element").position_offset.y < b.get_meta("_meta_graph_element").position_offset.y
			)
		# Sort by Position (Bottom to Top)
		6: sort_tree_items(tree_node_list_root, func(a: TreeItem, b: TreeItem):
			return a.get_meta("_meta_graph_element").position_offset.y > b.get_meta("_meta_graph_element").position_offset.y
			)
		
# 对 Tree 中指定父节点下的直接子项进行文字排序
# parent_item: 要排序的父节点（传 null 表示排序根节点）
func sort_tree_items(parent_item: TreeItem, sort_func: Callable):
	var items = parent_item.get_children()
	if items.size() <= 1:
		return
		
	items.sort_custom(sort_func)
	
	for i in items:
		parent_item.remove_child(i)
		
	for i in items:
		parent_item.add_child(i)
		
	for i in items:
		sort_tree_items(i, sort_func)
		
func _on_tree_node_list_item_selected() -> void:
	var item: TreeItem = tree_node_list.get_selected()
	if not item:
		return
	var node: GraphElement = item.get_meta("_meta_graph_element")
	if not node:
		return
		
	graph_edit.ensure_control_visible(node, 0.3)
	graph_edit.unselect_all_node()
	node.selected = true
	
func _on_button_refresh_node_list_pressed() -> void:
	_refresh_table_change_status()
	
func _on_sys_confirm_alter_table(_id = null) -> void:
	_refresh_table_change_status()
	
func _on_sys_confirm_drop_table(_db, _table) -> void:
	_refresh_table_change_status()
	
func _refresh_table_change_status():
	var change = await _check_table_change(tree_node_list_root)
	if change:
		button_node_list.icon = get_theme_icon(&"StatusWarning", &"EditorIcons")
	else:
		button_node_list.icon = null
		
func _check_table_change(item: TreeItem) -> bool:
	var node: GraphElement = null if not item.has_meta("_meta_graph_element") else item.get_meta("_meta_graph_element")
	var change = false
	if node and node is GraphNode and node.has_meta("data") and node.get_meta("data").get("__table_item", false):
		item.clear_buttons()
		
		var data = node.get_meta("data")
		var db = data.db_name
		var table = data.table_name
		var columns_define = GDSQL.WorkbenchManager.get_table_columns(db, table)
		if columns_define.is_empty():
			item.add_button(0, get_theme_icon(&"StatusWarning", &"EditorIcons"), 
				NODE_LIST_TREE_ITEM_BUTTON.TABLE_NOT_EXIST, false, tr("This table is not exist!"))
			item.set_meta("_meta_change_%d" % TABLE_CHANGE_TYPE.META_TABLE_NOT_EXIST, [db, table])
			change = true
		else:
			#TABLE_COMMENT_CHANGE, ## 表描述有变化
			var old_comment = data.comment
			var new_comment = GDSQL.WorkbenchManager.get_table_comment(db, table)
			if old_comment != new_comment:
				item.add_button(0, get_theme_icon(&"VisualShaderNodeComment", &"EditorIcons"), 
					NODE_LIST_TREE_ITEM_BUTTON.TABLE_COMMENT_CHANGE, false, 
					tr("Table comment changes.") + "\n" + 
					(tr("Old: [%s].") % old_comment) + "\n" + (tr("New: [%s].") % new_comment))
				item.set_meta("_meta_change_%d" % TABLE_CHANGE_TYPE.META_TABLE_COMMENT_CHANGE, new_comment)
				change = true
				
			var old_column_map = {}
			for col in data.columns:
				old_column_map[col["Column Name"]] = col
			var new_column_map = {}
			for col in columns_define:
				new_column_map[col["Column Name"]] = col
				
			# NEW_COLUMN, ## 新增了列
			#var new_cols = []
			#for col_name in new_column_map:
				#if not old_column_map.has(col_name):
					#new_cols.push_back(col_name)
			#if not new_cols.is_empty():
				#item.add_button(0, get_theme_icon(&"InsertAfter", &"EditorIcons"), 
					#NODE_LIST_TREE_ITEM_BUTTON.NEW_COLUMN, false, 
					#tr("New column(s) found:[%s].") % (", ".join(new_cols)))
				#item.set_meta("_meta_change_%d" % NODE_LIST_TREE_ITEM_BUTTON.NEW_COLUMN, 
					#[old_column_map, new_column_map, new_cols])
				#change = true
				
			# Column name diff
			var change_message = []
			var column_diffs = GDSQL.DiffHelper.get_compare_result_in_bbcode(old_column_map.keys(), new_column_map.keys())
			if not column_diffs.is_empty():
				change_message.push_back("[center][color=white]%s[/color][/center]" % tr("Column name changed:"))
				change_message.push_back(column_diffs[0])
				item.set_meta("_meta_change_%d" % TABLE_CHANGE_TYPE.META_COLUMN_NAME_CHANGE, 
					[old_column_map, new_column_map, column_diffs, db, table])
					
			## COLUMN_NOT_EXIST, ## 列不存在
			#var not_exist_cols = []
			#for col_name in old_column_map:
				#if not new_column_map.has(col_name):
					#not_exist_cols.push_back(col_name)
			#if not not_exist_cols.is_empty():
				#item.add_button(0, get_theme_icon(&"MissingNode", &"EditorIcons"), 
					#NODE_LIST_TREE_ITEM_BUTTON.COLUMN_NOT_EXIST, false, 
					#tr("Column(s) not exist:[%s].") % (", ".join(not_exist_cols)))
				#item.set_meta("_meta_change_%d" % NODE_LIST_TREE_ITEM_BUTTON.COLUMN_NOT_EXIST, 
					#[old_column_map, new_column_map, not_exist_cols])
				#change = true
				#
				
			## COLUMN_DEFINE_CHANGE, ## 列定义有变化
			var defination_changed = []
			var defineation_diff = {}
			for col_name in old_column_map:
				if new_column_map.has(col_name) and new_column_map[col_name] != old_column_map[col_name]:
					defination_changed.push_back(col_name)
					var old_content = []
					for p in old_column_map[col_name]:
						old_content.push_back("%s: %s" % [p, old_column_map[col_name][p]])
					var new_content = []
					for p in new_column_map[col_name]:
						new_content.push_back("%s: %s" % [p, new_column_map[col_name][p]])
					var prop_diffs = GDSQL.DiffHelper.get_compare_result_in_bbcode(old_content, new_content, true)
					if not prop_diffs.is_empty():
						defineation_diff[col_name] = prop_diffs
						if not change_message.is_empty():
							change_message.push_back("")
						change_message.push_back("[center][color=white]%s[/color][/center]" % 
							(tr("Column [%s] defination changed:")) % col_name)
						change_message.push_back(prop_diffs[0])
			if not defination_changed.is_empty():
				item.set_meta("_meta_change_%d" % TABLE_CHANGE_TYPE.META_COLUMN_DEFINE_CHANGE, 
					[old_column_map, new_column_map, defination_changed, defineation_diff])
					
			if not change_message.is_empty():
				item.add_button(0, load("res://addons/gdsql/img/file_type_diff_icon.svg"), 
					NODE_LIST_TREE_ITEM_BUTTON.COLUMNS_CHANGE, false, "\n".join(change_message))
				change = true
				
			#if not defination_changed.is_empty():
				#item.add_button(0, get_theme_icon(&"Tools", &"EditorIcons"), 
					#NODE_LIST_TREE_ITEM_BUTTON.COLUMN_DEFINE_CHANGE, false, 
					#tr("Column(s) defination changed:[%s].") % (", ".join(defination_changed)))
				#change = true
				
			## COLUMN_ORDER_CHANGE, ## 列顺序有变化
			#var same_cols = []
			#for i in old_column_map.keys() + new_column_map.keys():
				#if old_column_map.has(i) and new_column_map.has(i) and not same_cols.has(i):
					#same_cols.push_back(i)
			#var old_column_map_dup = old_column_map.duplicate(true)
			#var new_column_map_dup = new_column_map.duplicate(true)
			#for col in old_column_map_dup:
				#if not col in same_cols:
					#old_column_map_dup.erase(col)
			#for col in new_column_map_dup:
				#if not col in same_cols:
					#new_column_map_dup.erase(col)
			#var old_order = old_column_map_dup.keys()
			#var new_order = new_column_map_dup.keys()
			#if old_order != new_order:
				#var tooltip = tr("Columns order changed:") + \
					#"\n[table=3][cell]Old[/cell][cell]New[/cell][cell][/cell][cell]%s[/cell][cell]%s[/cell][cell][/cell]" % \
					#["—".repeat(5), "—".repeat(5)]
				#for i in old_order.size():
					#tooltip += "[cell]%s[/cell][cell]%s[/cell][cell]%s[/cell]" % \
						#[old_order[i], new_order[i], "" if old_order[i] == new_order[i] else "*"]
				#tooltip += "[/table]"
				#
				#item.add_button(0, get_theme_icon(&"YSort", &"EditorIcons"), 
					#NODE_LIST_TREE_ITEM_BUTTON.COLUMN_ORDER_CHANGE, false, tooltip)
				#item.set_meta("_meta_change_%d" % NODE_LIST_TREE_ITEM_BUTTON.COLUMN_NOT_EXIST, 
					#[old_column_map, new_column_map, old_order, new_order])
				#change = true
				
	for i in item.get_children():
		var child_change = await _check_table_change(i)
		change = change or child_change
		
	if change and item == tree_node_list_root:
		await get_tree().process_frame
		update_popup_panel_node_list_size()
		
	return change
	
func _on_tree_node_list_button_clicked(item: TreeItem, _column: int, id: int, _mouse_button_index: int) -> void:
	popup_panel_node_list.hide()
	item.select(0)
	match id:
		NODE_LIST_TREE_ITEM_BUTTON.TABLE_NOT_EXIST:
			GDSQL.WorkbenchManager.create_accept_dialog(tr("You can delete this node or leave it and create this table later."))
		NODE_LIST_TREE_ITEM_BUTTON.TABLE_COMMENT_CHANGE:
			var new_comment = item.get_meta("_meta_change_%d" % TABLE_CHANGE_TYPE.META_TABLE_COMMENT_CHANGE)
			var graph_node: GraphNode = item.get_meta("_meta_graph_element")
			var frame = graph_edit.get_element_frame(graph_node.name)
			var confirm = func():
				if frame:
					request_open_file.emit(frame.title)
				else:
					graph_edit.update_item_comment(graph_node, new_comment)
					_on_sys_confirm_alter_table()
					if get_meta("is_file"):
						change_tab_title.emit(self, get_meta("file_name") + "*")
			var dialog = GDSQL.WorkbenchManager.create_confirmation_dialog("Change the comment to: [%s]." % new_comment, confirm, Callable())
			if frame:
				dialog.ok_button_text = tr("Open file to modify this")
				var ok_btn = dialog.get_ok_button()
				ok_btn.icon = get_theme_icon(&"ExternalLink", &"EditorIcons")
				ok_btn.tooltip_text = frame.title
				
		NODE_LIST_TREE_ITEM_BUTTON.COLUMNS_CHANGE:
			var graph_node = item.get_meta("_meta_graph_element")
			var frame = graph_edit.get_element_frame(graph_node.name)
			var datas_for_dialog: Array[Array] = []
			if frame:
				datas_for_dialog.push_back([tr("Confirm the changes:")])
			else:
				datas_for_dialog.push_back([(tr("Click [%s] ") % tr("OK")) + tr("to confirm the changes:")])
			var new_column_map: Dictionary
			if item.has_meta("_meta_change_%d" % TABLE_CHANGE_TYPE.META_COLUMN_NAME_CHANGE):
				# [old_column_map, new_column_map, column_diffs, db, table]
				var info = item.get_meta("_meta_change_%d" % TABLE_CHANGE_TYPE.META_COLUMN_NAME_CHANGE)
				new_column_map = info[1]
				
				var label = RichTextLabel.new()
				label.bbcode_enabled = true
				label.text = info[2][0]
				label.autowrap_trim_flags = TextServer.BREAK_NONE
				label.fit_content = true
				label.autowrap_mode = TextServer.AUTOWRAP_OFF
				
				datas_for_dialog.push_back([tr("Table: %s.%s") % [info[3], info[4]]])
				datas_for_dialog.push_back([tr("Column name changed:")])
				datas_for_dialog.push_back([label])
				
			if item.has_meta("_meta_change_%d" % TABLE_CHANGE_TYPE.META_COLUMN_DEFINE_CHANGE):
				# [old_column_map, new_column_map, defination_changed, defineation_diff]
				var info = item.get_meta("_meta_change_%d" % TABLE_CHANGE_TYPE.META_COLUMN_DEFINE_CHANGE)
				new_column_map = info[1]
				
				for col_name in info[3]:
					var label = RichTextLabel.new()
					label.bbcode_enabled = true
					label.text = info[3][col_name][0]
					label.autowrap_trim_flags = TextServer.BREAK_NONE
					label.fit_content = true
					label.autowrap_mode = TextServer.AUTOWRAP_OFF
					
					datas_for_dialog.push_back([tr("Column [%s] defination changed:") % col_name])
					datas_for_dialog.push_back([label])
					
			var confirm = func():
				if frame:
					request_open_file.emit(frame.title)
					return [false, null]
				else:
					graph_edit.update_item_columns(graph_node, new_column_map.values())
					await get_tree().process_frame
					_on_sys_confirm_alter_table()
					return [false, null]
			var defer = func(_a, _b):
				for arr in datas_for_dialog:
					for i in arr:
						if i is Control:
							i.queue_free()
			var dialog = GDSQL.WorkbenchManager.create_custom_dialog(datas_for_dialog, confirm, Callable(), defer, Vector2(0, 0.5), true)
			if frame:
				dialog.ok_button_text = tr("Open file to modify this")
				var ok_btn = dialog.get_ok_button()
				ok_btn.icon = get_theme_icon(&"ExternalLink", &"EditorIcons")
				ok_btn.tooltip_text = frame.title
