@tool
extends VSplitContainer

@onready var button_open: Button = $VBoxContainer/HFlowContainer/ButtonOpen
@onready var button_save: Button = $VBoxContainer/HFlowContainer/ButtonSave
@onready var button_save_as: Button = $VBoxContainer/HFlowContainer/ButtonSaveAs
@onready var button_add_node: Button = $VBoxContainer/HFlowContainer/ButtonAddNode
@onready var line_edit_save_path: LineEdit = $VBoxContainer/HFlowContainer/LineEditSavePath
@onready var option_button_choose_path: OptionButton = $VBoxContainer/HFlowContainer/OptionButtonChoosePath
@onready var option_button_link: OptionButton = $VBoxContainer/HFlowContainer/OptionButtonLink
@onready var button_run_selected: Button = $VBoxContainer/HFlowContainer/ButtonRunSelected
@onready var button_run: Button = $VBoxContainer/HFlowContainer/ButtonRun

var mgr: GDSQLWorkbenchManagerClass = Engine.get_singleton("GDSQLWorkbenchManager")


signal request_open_file(path: String)
signal change_tab_title(page: Control, title: String)

@onready var graph_edit: GraphEdit = $VBoxContainer/GraphEdit

const EXTENSION = "*.gdmappergraph"

enum LINK_WAY {
	NESTING_SELECT,
	NESTING_RESULT_MAP,
}

func _ready() -> void:
	pass
	
func load_mapper_file(path):
	var config = ImprovedConfigFile.new()
	config.load(path)
	var nodes = config.get_value("data", "nodes", {})
	var connections = config.get_value("data", "connections", [])
	var save_path = config.get_value("data", "path", "") as String
	var link_type = config.get_value("data", "link_type", 0)
	
	line_edit_save_path.text = save_path
	option_button_link.selected = link_type
	if save_path != "":
		if save_path.begins_with("res://"):
			option_button_choose_path.selected = 0
		elif save_path.begins_with("user://"):
			option_button_choose_path.selected = 1
		else:
			option_button_choose_path.selected = 2
			
	# genarate nodes
	graph_edit._load_nodes(nodes, connections, Vector2.ZERO, false, false)
	
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
	editor_file_dialog.close_requested.connect(func():
		editor_file_dialog.queue_free()
	)
	
func _on_button_save_pressed() -> void:
	# 本身就是一个已经保存的文件，就直接保存
	if get_meta("is_file"):
		var config = ImprovedConfigFile.new()
		config.set_value("data", "nodes", graph_edit.get_nodes_params())
		config.set_value("data", "connections", graph_edit.get_connection_list().map(func(v):
			v["from_node"] = v["from_node"].validate_node_name()
			v["to_node"] = v["to_node"].validate_node_name()
			return v
		))
		config.set_value("data", "path", line_edit_save_path.text.strip_edges())
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
		var config = ImprovedConfigFile.new()
		config.set_value("data", "nodes", graph_edit.get_nodes_params())
		config.set_value("data", "connections", graph_edit.get_connection_list().map(func(v):
			v["from_node"] = v["from_node"].validate_node_name()
			v["to_node"] = v["to_node"].validate_node_name()
			return v
		))
		config.set_value("data", "path", line_edit_save_path.text.strip_edges())
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
	editor_file_dialog.close_requested.connect(func():
		editor_file_dialog.queue_free()
	)
	
func _on_button_add_node_pressed() -> void:
	mgr.create_accept_dialog(button_add_node.tooltip_text)
	
func _on_option_button_choose_path_item_selected(access: int, extra_line_edit = null) -> void:
	var editor_file_dialog = EditorFileDialog.new()
	editor_file_dialog.access = access
	editor_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
	editor_file_dialog.dir_selected.connect(func(path: String):
		line_edit_save_path.text = path
		if extra_line_edit:
			extra_line_edit.text = path
		change_tab_title.emit(self, get_meta("file_name") + "*")
	, CONNECT_DEFERRED)
	add_child(editor_file_dialog)
	editor_file_dialog.popup_centered_ratio(0.5)
	editor_file_dialog.close_requested.connect(func():
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
	
func _generate(nodes: Array):
	var nodes_map = {}
	var node_pair = {}
	var node_link_prop = {}
	
	for i in nodes:
		if i.enabled:
			nodes_map[i.name] = i
			
	for i in graph_edit.get_connection_list():
		if nodes_map.has(i.from_node) and nodes_map.has(i.to_node):
			var from_node = nodes_map[i.from_node]
			var from_columns = from_node.get_meta("data").columns
			#var from_port_offset = -1 if from_node.get_meta("extra_enabled", false) else 0
			#var from_col = from_columns[i.from_port + from_port_offset]["Column Name"]
			var from_col = from_columns[i.from_port]["Column Name"]
			#var from_data = from_node.get_meta("data")
			
			var to_node = nodes_map[i.to_node]
			var to_columns = to_node.get_meta("data").columns
			assert(to_node.get_meta("extra_enabled", false), 
				"This node is supposed to has meta extra_enabled's true.")
			#var to_port_offset = -1
			#var to_col = to_columns[i.to_port + to_port_offset]["Column Name"]
			var to_col = to_columns[i.to_port]["Column Name"]
			var to_data = to_node.get_meta("data")
			
			if not node_pair.has(i.from_node):
				node_pair[i.from_node] = {}
			if not node_pair[i.from_node].has(i.to_node):
				var to_node_extra = graph_edit.get_node_extra(to_node)
				node_link_prop[i.to_node] = to_node_extra.link_prop_type
				node_pair[i.from_node][i.to_node] = {
					"db_name": to_data.db_name,
					"table_name": to_data.table_name,
					"comment": to_data.comment,
					"link_type": to_node_extra.link_type,
					"link_prop_type": to_node_extra.link_prop_type,
					"link_prop": to_node_extra.link_prop,
					"link_col": [],
					"to_columns": to_columns,
				}
				
			node_pair[i.from_node][i.to_node].link_col.push_back([from_col, to_col])
			
	var leading_nodes = nodes_map.keys()
	for from_node_name in node_pair:
		for to_node_name in node_pair[from_node_name]:
			leading_nodes.erase(to_node_name)
			
	const prefixes = "tabcdefghijklmnopqrsuvwxyz" # t is most common
	
	# gdscript of entity
	var entity_map = {} # db.entity_name => [content]
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
<mapper namespace="%sMapper">
	
	<cache eviction="LRU" flushInterval="0" size="50" />
	"""]
		var arr_method = []
		var arr_columns = {}
		var has_asso_collec = false
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
		var leading_class_n = null
		var leading_entity_n = null
		var leading_db_name = null
		var leading_table_name = null
		var leading_table_name_snake = null
		var table_counts = {}
		var column_counts = {} # 同名列
		
		# 递归找到与起始节点关联的诸多节点
		var linked_nodes = get_linked_nodes_bfs(node_pair, lead_node_name)
		
		for node_name in linked_nodes:
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
			var data = node.get_meta("data") as Dictionary
			var aprops = graph_edit.get_node_props(node) as Dictionary
			var db_name = data.db_name as String
			var table_name = data.table_name as String
			var table_name_camel = table_name.to_camel_case()
			var table_comment = data.comment
			var columns = data.columns as Array
			var result_map_id = table_name_camel
			if node_link_prop.has(node.name):
				result_map_id = node_link_prop[node.name].to_camel_case()
			if leading_result_map_id == null:
				leading_result_map_id = result_map_id
				leading_class_n = result_map_id.capitalize().replace(" ", "")
				leading_entity_n = leading_class_n + "Entity"
				leading_db_name = db_name
				leading_table_name = table_name
				leading_table_name_snake = table_name.to_snake_case()
				
			var arr_col = []
			var arr_col_name = []
			var arr_prop_type = []
			var a_col_prefix = ""
			# lead tabel 可能需要column加前缀。其他的不用，因为association和collection
			# 支持在columnPrefix属性设定一个前缀。
			if node_name == lead_node_name:
				if node_pair.has(node_name) and \
				option_button_link.selected != LINK_WAY.NESTING_SELECT:
					a_col_prefix = table_alias[node_name]
			var prop_max_length = get_max_prop_name_length(aprops) + 'property=""'.length()
			var col_max_length = get_max_col_name_length(columns) + 'column=""'.length() + \
				a_col_prefix.length() + 4
			for col in columns:
				var prefix = '<id    ' if col.PK else '<result'
				if linked_nodes.size() > 1:
					prefix += '     ' # +5 as long as associaiton
				var a_col_name = col["Column Name"]
				arr_col.push_back(('%s %-' + str(prop_max_length) + 's    %-' + \
					str(col_max_length) + 's/>') % [
						prefix, 
						'property="%s"' % aprops[a_col_name], 
						'column="%s"' % (a_col_prefix + a_col_name)]
				)
				arr_col_name.push_back(a_col_name)
				arr_prop_type.push_back([aprops[a_col_name], type_string(col["Data Type"]), -1, col["Comment"]])
			arr_columns[node_name] = arr_col_name
			
			if node_pair.has(node_name):
				has_asso_collec = true
				for to_node_name in node_pair[node.name]:
					var info = node_pair[node.name][to_node_name]
					var s = null
					var prefix = "<association" if info.link_type == \
						graph_edit.LINK_TYPE.ASSOCIATION else "<collection "
					var a_result_map_id = info.link_prop_type.to_camel_case() + "Result"
					
					if option_button_link.selected == LINK_WAY.NESTING_SELECT:
						var by = info.link_col.map(func(v): return v[1])
						by.sort()
						var arg_types = []
						for i in by:
							for j in info.to_columns:
								if j["Column Name"] == i:
									arg_types.push_back(j["Data Type"])
									break
						var parent_by = info.link_col.map(func(v): return v[0])
						parent_by.sort()
						var method = 'select_%s_by_%s' % \
							[info.link_prop_type.to_snake_case(), "_".join(by)]
						var method_info = {
							"id": method,
							"result_map": a_result_map_id,
							"arg_names": by,
							"arg_types": arg_types,
							"db_name": info.db_name,
							"namespace": info.db_name + "." + info.table_name,
							"node_name": to_node_name,
							"info": info,
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
								has_same = true
								if i.result_map != method_info.result_map or \
								i.arg_names != method_info.arg_names or \
								i.namespace != method_info.namespace:
									need_add_surfix = true
									
						if need_add_surfix:
							method_info.id = method_info.id + "_" + str(new_index)
							
						s = '%s property="%s" column="%s" select="%s"    />' % \
							[prefix, info.link_prop, ",".join(parent_by), 
							method_info.id]
							
						if not has_same:
							arr_method.push_back(method_info)
					else:
						s = '%s property="%s" columnPrefix="%s" resultMap="%s"    />' % \
							[prefix, info.link_prop, table_alias[to_node_name], 
							a_result_map_id]
							
					arr_col.push_back(s)
					arr_prop_type.push_back(
						[info.link_prop, info.link_prop_type, info.link_type, info.comment])
						
			if not result_map_added.has(result_map_id):
				xml_arr.push_back('\n\t<resultMap id="%sResult" type="%sEntity"' % [
					result_map_id, result_map_id.capitalize().replace(" ", "")
				])
				xml_arr.push_back(' autoMapping="false">\n\t\t%s\n\t</resultMap>\n\t' % \
						"\n\t\t".join(arr_col))
				result_map_added.push_back(result_map_id)
				
			# entity
			var en_ns = '%s.%sEntity' % [db_name, result_map_id.capitalize().replace(" ", "")]
			if not entity_map.has(en_ns):
				var arr = ['extends RefCounted\nclass_name %sEntity\n' % \
					result_map_id.capitalize().replace(" ", "")]
				var arr_getset = []
				if table_comment != "":
					arr.push_front('## %s\n' % table_comment)
				for i in arr_prop_type:
					var i_0_snake = i[0].to_snake_case()
					if i[2] == graph_edit.LINK_TYPE.COLLECTION_ARRAY:
						arr.push_back('\n## Array[%s]' % i[3])
						if i[1] == "Nil":
							arr.push_back('\nvar %s: Array\n' % i[0])
							arr_getset.push_back('\nfunc get_%s() -> Array:' % i_0_snake)
							arr_getset.push_back('\n\treturn %s\n\t' % i[0])
							arr_getset.push_back('\nfunc set_%s(p_%s: Array):' % [i_0_snake, i_0_snake])
							arr_getset.push_back('\n\t%s = p_%s\n\t' % [i[0], i_0_snake])
						elif DataTypeDef.DATA_TYPE_COMMON_NAMES.has(i[1]):
							arr.push_back('\nvar %s: Array[%s]\n' % [i[0], i[1]])
							arr_getset.push_back('\nfunc get_%s() -> Array[%s]:' % [i_0_snake, i[1]])
							arr_getset.push_back('\n\treturn %s\n\t' % i[0])
							arr_getset.push_back('\nfunc set_%s(p_%s: Array[%s]):' % [i_0_snake, i_0_snake, i[1]])
							arr_getset.push_back('\n\t%s = p_%s\n\t' % [i[0], i_0_snake])
						else:
							arr.push_back('\nvar %s: Array[%sEntity]\n' % [i[0], i[1]])
							arr_getset.push_back('\nfunc get_%s() -> Array[%sEntity]:' % [i_0_snake, i[1]])
							arr_getset.push_back('\n\treturn %s\n\t' % i[0])
							arr_getset.push_back('\nfunc set_%s(p_%s: Array[%sEntity]):' % [i_0_snake, i_0_snake, i[1]])
							arr_getset.push_back('\n\t%s = p_%s\n\t' % [i[0], i_0_snake])
					else:
						arr.push_back('\n## %s' % i[3])
						if i[1] == "Nil":
							arr.push_back('\nvar %s\n' % i[0])
							arr_getset.push_back('\nfunc get_%s():' % i_0_snake)
							arr_getset.push_back('\n\treturn %s\n\t' % i[0])
							arr_getset.push_back('\nfunc set_%s(p_%s):' % [i_0_snake, i_0_snake])
							arr_getset.push_back('\n\t%s = p_%s\n\t' % [i[0], i_0_snake])
						elif DataTypeDef.DATA_TYPE_COMMON_NAMES.has(i[1]):
							#arr.push_back('\nvar %s: %s\n' % [i[0], i[1]])
							# 不在属性上指定数据类型了，不然update、insert不知道有没有给属性设定值。
							# 但是保留在get、set函数上进行设置数据类型
							arr.push_back('\nvar %s # %s\n' % [i[0], i[1]])
							arr_getset.push_back('\nfunc get_%s() -> %s:' % [i_0_snake, i[1]])
							arr_getset.push_back('\n\treturn %s\n\t' % i[0])
							arr_getset.push_back('\nfunc set_%s(p_%s: %s):' % [i_0_snake, i_0_snake, i[1]])
							arr_getset.push_back('\n\t%s = p_%s\n\t' % [i[0], i_0_snake])
						else:
							arr.push_back('\nvar %s: %sEntity\n' % [i[0], i[1]])
							arr_getset.push_back('\nfunc get_%s() -> %sEntity:' % [i_0_snake, i[1]])
							arr_getset.push_back('\n\treturn %s\n\t' % i[0])
							arr_getset.push_back('\nfunc set_%s(p_%s: %sEntity):' % [i_0_snake, i_0_snake, i[1]])
							arr_getset.push_back('\n\t%s = p_%s\n\t' % [i[0], i_0_snake])
				entity_map[en_ns] = arr + arr_getset
				
		# <sql>
		var vo_ids = {} # namespace => vo_id
		var select_use_db = false # <select>标签是否使用databaseId属性
		if not has_asso_collec:
			select_use_db = true
			vo_ids[leading_db_name + "." + leading_table_name] = leading_result_map_id
			var vo = "select %s from %s" % [", ".join(arr_columns[lead_node_name]), 
				leading_table_name]
			xml_arr.push_back('\n\t<sql id="%sVo">\n\t\t%s\n\t</sql>\n\t' % \
				[leading_result_map_id, split_for_long_content(vo, "\n\t\t")])
		# nesting select 不使用left join，直接select主表即可，但是有多个sql
		elif option_button_link.selected == LINK_WAY.NESTING_SELECT:
			select_use_db = true
			for node_name in linked_nodes:
				var data = nodes_map[node_name].get_meta("data") as Dictionary
				var db_name = data.db_name as String
				var table_name = data.table_name as String
				var ns = db_name + "." + table_name
				var id = table_name.to_camel_case()
				if not vo_ids.has(ns):
					var count = 1
					for i in vo_ids:
						if vo_ids[i].begins_with(id):
							count += 1
					if count != 1:
						id += "_" + str(count)
					vo_ids[db_name + "." + table_name] = id
					var vo = "select %s from %s" % [", ".join(arr_columns[node_name]), 
						table_name]
					xml_arr.push_back('\n\t<sql id="%sVo">\n\t\t%s\n\t</sql>\n\t' % \
						[id, split_for_long_content(vo, "\n\t\t")])
		# nesting resultMap 需要使用left join，把所有表形成一条sql
		else:
			vo_ids[leading_db_name + "." + leading_table_name] = leading_result_map_id
			var vo = ""
			var all_column_name = []
			for node_n in arr_columns:
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
										alias1, k[1], alias0, k[0]
									])
								break
					vo += "\n\t\tleft join %s.%s %s on %s" % [
						db_name, table_name, t_alias, " and ".join(acond)
					]
			xml_arr.push_back('\n\t<sql id="%sVo">\n\t\t%s\n\t</sql>\n\t' % \
			[leading_result_map_id, vo])
			
		# mapper_arr
		var mp_id = '%s.%sMapper' % [leading_db_name, leading_class_n]
		if mapper_map.has(mp_id):
			var count = 1
			for i in mapper_map:
				if i.begins_with(mp_id):
					count += 1
			if count != 1:
				mp_id = '%s.%s%sMapper' % [leading_db_name, leading_class_n, count]
		var mapper_arr = ['@tool\nextends GBatisMapper\nclass_name %sMapper\n' % leading_class_n]
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
				[leading_method, leading_table_name.to_camel_case() + "Result",
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
			if m.info.link_type == graph_edit.LINK_TYPE.ASSOCIATION:
				return_type = m.info.link_prop_type.capitalize().replace(" ", "") + "Entity"
			else:
				return_type = 'Array[%sEntity]' % m.info.link_prop_type
			mapper_arr.push_back('\nfunc %s(%s) -> %s:' % [
				m.id, ", ".join(args), return_type
			])
			mapper_arr.push_back('\n\treturn query("%s", %s)\n\t' % [
				m.id, ", ".join(arg_names)
			])
			
			# xml_arr
			var acond = []
			for arg in m.arg_names:
				acond.push_back('%s == #{%s}' % [arg, arg.to_snake_case()])
				
			xml_arr.push_back('\n\t<select id="%s" resultMap="%s"%s>' % \
				[m.id, m.result_map, 
				(' databaseId="%s"' % m.db_name) if select_use_db else ""])
			xml_arr.push_back('\n\t\t<include refid="%sVo"/>' % vo_ids[m.namespace])
			xml_arr.push_back('\n\t\twhere %s' % " and ".join(acond))
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
		xml_arr[0] = xml_arr[0] % leading_class_n # replace namespace
		var xml_ns = '%s.%sMapper' % [leading_db_name, leading_class_n]
		if xml_map.has(xml_ns):
			var a_index = 1
			for n: String in xml_map:
				if n.begins_with(xml_ns):
					a_index += 1
			if a_index > 1:
				xml_ns = '%s.%s%sMapper' % [leading_db_name, leading_class_n, a_index]
		xml_map[xml_ns] = xml_arr
		
	# popup confirm dialog
	popup_generate_dialog(xml_map, mapper_map, entity_map)
	
var _generate_dialog
func popup_generate_dialog(xml_map, mapper_map, entity_map):
	var hbox = HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var line_edit_path = LineEdit.new()
	line_edit_path.placeholder_text = "Save path"
	line_edit_path.caret_blink = true
	line_edit_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line_edit_path.text = line_edit_save_path.text
	hbox.add_child(line_edit_path)
	
	var option_button_choose = OptionButton.new()
	option_button_choose.add_item("Resource")
	option_button_choose.add_item("UserData")
	option_button_choose.add_item("FileSystem")
	option_button_choose.tooltip_text = "Pick a path from Resource, UserData or FileSystem."
	option_button_choose.allow_reselect = true
	option_button_choose.selected = option_button_choose_path.selected
	option_button_choose.item_selected.connect(
		_on_option_button_choose_path_item_selected.bind(line_edit_path))
	hbox.add_child(option_button_choose)
	
	var btn_save_all = Button.new()
	btn_save_all.icon = get_theme_icon("Save", "EditorIcons")
	btn_save_all.text = "Save All"
	hbox.add_child(btn_save_all)
	
	var tree = Tree.new()
	tree.columns = 3
	tree.hide_root = true
	tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.set_column_expand(0, false)
	
	var root = tree.create_item()
	var check_all_item = tree.create_item(root)
	check_all_item.set_text(1, "Select All")
	check_all_item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
	check_all_item.set_editable(0, true)
	
	btn_save_all.pressed.connect(func():
		if line_edit_path.text == "":
			mgr.create_accept_dialog("Save path is empty!")
			return
		for i: TreeItem in root.get_children():
			if i.get_text(2) != "":
				var content = i.get_metadata(0)
				var path = line_edit_path.text.path_join(i.get_text(2).replace("(*)", ""))
				var file = FileAccess.open(path, FileAccess.WRITE)
				file.store_string(content)
				file.flush()
				file = null
		var old_icon = btn_save_all.icon
		btn_save_all.icon = get_theme_icon("ImportCheck", "EditorIcons")
		btn_save_all.disabled = true
		EditorInterface.get_resource_filesystem().scan()
		if _generate_dialog:
			# scan后窗口可能被最小化了，所以用窗口的方法，能重新激活
			while EditorInterface.get_resource_filesystem().is_scanning():
				await get_tree().process_frame
			_generate_dialog.transient = false
			if _generate_dialog.mode != Window.MODE_WINDOWED:
				_generate_dialog.mode = Window.MODE_WINDOWED
			_generate_dialog.grab_focus() # TODO FIXME WAIT_FOR_UPDATE which is useless in 4.3.dev6
		await get_tree().create_timer(2).timeout
		btn_save_all.icon = old_icon
		btn_save_all.disabled = false
	)
	
	for map in [xml_map, mapper_map, entity_map]:
		for i: String in map:
			var item = tree.create_item(root)
			item.set_metadata(0, ''.join(map[i]) + '\n')
			item.set_meta("origin", item.get_metadata(0))
			item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
			item.set_checked(0, true)
			item.set_editable(0, true)
			item.set_text(1, i)
			item.set_text(2, i.get_slice(".", 1) + (".xml" if map == xml_map else ".gd"))
			item.add_button(2, CompressedTexture2D.new(), 3, true, "Revert")
			item.add_button(2, get_theme_icon("Edit", "EditorIcons"), 0, false, "Edit")
			item.add_button(2, get_theme_icon("Save", "EditorIcons"), 1, false, "Save As...")
			item.add_button(2, get_theme_icon("ActionCopy", "EditorIcons"), 2, false, "Copy")
			
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
			match id:
				0: # Edit
					popup_edit_dialog(item)
				1: # Save As...
					popup_saveas_dialog(option_button_choose.selected, item, 
						line_edit_path.text)
				2: # Copy to clipboard
					DisplayServer.clipboard_set(item.get_metadata(0))
				3: # Revert
					item.set_metadata(0, item.get_meta("origin"))
					item.set_button(2, 0, CompressedTexture2D.new())
					item.set_button_disabled(2, 0, true)
					item.set_button_tooltip_text(2, 0, "")
					if item.get_text(2).ends_with("(*)"):
						item.set_text(2, item.get_text(2).substr(
							0, item.get_text(2).length()-3))
	)
	tree.ready.connect(func():
		check_all_item.set_checked(0, true)
		tree.get_parent_control().size_flags_vertical = Control.SIZE_EXPAND_FILL
	)
	var arr = [[hbox], [tree]] as Array[Array]
	
	var confirm = func():
		if line_edit_path.text == "":
			mgr.create_accept_dialog("Save path is empty!")
			return [true, null]
		var save_at_least_one = false
		for i: TreeItem in root.get_children():
			if i.get_text(2) != "" and i.is_checked(0):
				var content = i.get_metadata(0)
				var path = line_edit_path.text.path_join(i.get_text(2).replace("(*)", ""))
				var file = FileAccess.open(path, FileAccess.WRITE)
				file.store_string(content)
				file.flush()
				file = null
				save_at_least_one = true
		if save_at_least_one:
			EditorInterface.get_resource_filesystem().scan()
			return [true, null]
		else:
			mgr.create_accept_dialog("None selected.")
			return [true, null]
			
	var defer = func(_a, _b):
		_generate_dialog = null
		hbox.queue_free()
		tree.queue_free()
	_generate_dialog = mgr.create_custom_dialog(arr, confirm, Callable(), defer, 0.3)
	_generate_dialog.add_button("Compare", true, "Compare")
	_generate_dialog.get_ok_button().text = "Save"
	
	_generate_dialog.custom_action.connect(func(_action):
		var arr_content = []
		for i: TreeItem in root.get_children():
			if i.is_checked(0):
				if i.get_text(2) != "":
					arr_content.push_back({
						"file": i.get_text(2),
						"content": i.get_metadata(0),
						"item": i,
					})
		popup_diff_dialog(arr_content)
	)
	
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
	EditorInterface.get_resource_filesystem().scan()
	if _generate_dialog:
		# scan后窗口可能被最小化了，所以用窗口的方法，能重新激活
		while EditorInterface.get_resource_filesystem().is_scanning():
			await get_tree().process_frame
		_generate_dialog.transient = false
		if _generate_dialog.mode != Window.MODE_WINDOWED:
			_generate_dialog.mode = Window.MODE_WINDOWED
		_generate_dialog.grab_focus() # TODO FIXME WAIT_FOR_UPDATE which is useless in 4.3.dev6
	await get_tree().create_timer(2).timeout
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
		editor_file_dialog.current_file = item.get_text(2).replace("(*)", "")
	)
	
	editor_file_dialog.file_selected.connect(
		self.comfirm_save.bind(item, editor_file_dialog), CONNECT_DEFERRED)
		
	var defer = func(_confirmed, _dummy):
		editor_file_dialog.queue_free()
	mgr.popup_user_dialog(editor_file_dialog, Callable(), Callable(), defer, 0.5)
	
func reset_content(item: TreeItem, editor):
	item.set_metadata(0, editor.text_editor.text)
	if item.get_meta("origin") == editor.text_editor.text:
		item.set_button(2, 0, CompressedTexture2D.new())
		item.set_button_disabled(2, 0, true)
		item.set_button_tooltip_text(2, 0, "")
		if item.get_text(2).ends_with("(*)"):
			item.set_text(2, item.get_text(2).substr(0, item.get_text(2).length()-3))
	elif not item.get_text(2).ends_with("(*)"):
		item.set_button(2, 0, get_theme_icon("RotateLeft", "EditorIcons"))
		item.set_button_disabled(2, 0, false)
		item.set_button_tooltip_text(2, 0, "Revert")
		item.set_text(2, item.get_text(2) + "(*)")
		
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
		editor.text_editor.text_changed.disconnect(self.reset_content)
		editor.text_editor.text_set.disconnect(self.reset_content)
		editor.queue_free()
		
	var dialog = mgr.create_custom_dialog(arr, Callable(), Callable(), defer, 0.6)
	dialog.get_cancel_button().hide()
	
func popup_diff_dialog(arr_content: Array):
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
	for i in arr_content:
		columns.push_back(i.file)
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
			code_edit.highlight_current_line = true
			code_edit.minimap_draw = true
			code_edit.caret_blink = true
			code_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			code_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
			code_edit.text = i.content
			code_edit.selecting_enabled = false
			code_edit.text_changed.connect(reset_content.bind(i.item, editor))
			code_edit.text_set.connect(reset_content.bind(i.item, editor))
			await get_tree().process_frame
			code_edit.selecting_enabled = true
		)
	for editor in arr_editor:
		editor.zoomed.connect(func(factor):
			for a_editor in arr_editor:
				if a_editor != editor:
					a_editor.set_zoom_factor(factor)
		)
		
	table.columns = columns
	table.datas = [data]
	table.support_select_border = false
	var arr = [[table]] as Array[Array]
	var defer = func(_confirmed, _dummy):
		for editor in arr_editor:
			editor.text_editor.text_changed.disconnect(self.reset_content)
			editor.text_editor.text_set.disconnect(self.reset_content)
		arr_editor.clear()
		arr_v_scroll_bar.clear()
		table.queue_free()
	mgr.create_custom_dialog(arr, Callable(), Callable(), defer, 0.9)
	
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
	return var_to_str(DataTypeDef.DEFUALT_VALUES[type]).replace('""', "''")
	
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
