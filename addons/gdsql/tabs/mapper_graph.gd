@tool
extends VSplitContainer

@onready var button_open: Button = $VBoxContainer/HFlowContainer/ButtonOpen
@onready var button_save: Button = $VBoxContainer/HFlowContainer/ButtonSave
@onready var button_save_as: Button = $VBoxContainer/HFlowContainer/ButtonSaveAs
@onready var button_add_node: Button = $VBoxContainer/HFlowContainer/ButtonAddNode
@onready var line_edit_save_xml_path: LineEdit = $VBoxContainer/HFlowContainer/LineEditSaveXMLPath
@onready var option_button_choose_xml_file: OptionButton = $VBoxContainer/HFlowContainer/OptionButtonChooseXMLFile
@onready var line_edit_save_gd_path: LineEdit = $VBoxContainer/HFlowContainer/LineEditSaveGDPath
@onready var option_button_choose_gd_file: OptionButton = $VBoxContainer/HFlowContainer/OptionButtonChooseGDFile
@onready var option_button_link: OptionButton = $VBoxContainer/HFlowContainer/OptionButtonLink
@onready var button_run_selected: Button = $VBoxContainer/HFlowContainer/ButtonRunSelected
@onready var button_run: Button = $VBoxContainer/HFlowContainer/ButtonRun
@onready var button_preview: Button = $VBoxContainer/HFlowContainer/ButtonPreview

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
	var xml_path = config.get_value("data", "xml_path", "")
	var gd_path = config.get_value("data", "gd_path", "")
	
	line_edit_save_xml_path.text = xml_path
	line_edit_save_gd_path.text = gd_path
	
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
		config.set_value("data", "xml_path", line_edit_save_xml_path.text.strip_edges())
		config.set_value("data", "gd_path", line_edit_save_gd_path.text.strip_edges())
		
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
		config.set_value("data", "xml_path", line_edit_save_xml_path.text.strip_edges())
		config.set_value("data", "gd_path", line_edit_save_gd_path.text.strip_edges())
		
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
	
func _on_option_button_choose_xml_file_item_selected(access: int) -> void:
	var editor_file_dialog = EditorFileDialog.new()
	editor_file_dialog.filters = PackedStringArray(["*.xml; XML File"])
	editor_file_dialog.access = access
	editor_file_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	editor_file_dialog.file_selected.connect(func(path: String):
		line_edit_save_xml_path.text = path
	, CONNECT_DEFERRED)
	add_child(editor_file_dialog)
	editor_file_dialog.popup_centered_ratio(0.5)
	editor_file_dialog.close_requested.connect(func():
		editor_file_dialog.queue_free()
	, CONNECT_DEFERRED)
	
func _on_option_button_choose_gd_file_item_selected(access: int) -> void:
	var editor_file_dialog = EditorFileDialog.new()
	editor_file_dialog.filters = PackedStringArray(["*.gd; GDScript File"])
	editor_file_dialog.access = access
	editor_file_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	editor_file_dialog.file_selected.connect(func(path: String):
		line_edit_save_gd_path.text = path
	, CONNECT_DEFERRED)
	add_child(editor_file_dialog)
	editor_file_dialog.popup_centered_ratio(0.5)
	editor_file_dialog.close_requested.connect(func():
		editor_file_dialog.queue_free()
	, CONNECT_DEFERRED)
	
func _on_button_run_selected_pressed() -> void:
	var arr_node = []


func _on_button_run_pressed() -> void:
	pass # Replace with function body.


func _on_button_preview_pressed() -> void:
	pass # Replace with function body.


func _generate_xml(nodes: Array) -> String:
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
			var from_port_offset = -1 if from_node.get_meta("extra_enabled", false) else 0
			var from_col = from_columns[i.from_port + from_port_offset]["Column Name"]
			var from_data = from_node.get_meta("data")
			
			var to_node = nodes_map[i.to_node]
			var to_columns = to_node.get_meta("data").columns
			assert(to_node.get_meta("extra_enabled", false), 
				"This node is supposed to has meta extra_enabled's true.")
			var to_port_offset = -1
			var to_col = to_columns[i.to_port + to_port_offset]["Column Name"]
			var to_data = to_node.get_meta("data")
			
			#for j in [from_data, to_data]:
				#if not table_counts.has(j.db_name):
					#table_counts[j.db_name] = {}
				#if not table_counts[j.db_name].has(j.table_name):
					#table_counts[j.db_name][j.table_name] = 0
				#table_counts[j.db_name][j.table_name] += 1
				#
			#for cs in [from_columns, to_columns]:
				#for j in cs:
					#if not column_counts.has(j["Column Name"]):
						#column_counts[j["Column Name"]] = 0
					#column_counts[j["Column Name"]] += 1
					
			if not node_pair.has(i.from_node):
				node_pair[i.from_node] = {}
			if not node_pair[i.from_node].has(i.to_node):
				var to_node_extra = graph_edit.get_node_extra(to_node)
				node_link_prop[i.to_node] = to_node_extra.link_prop
				node_pair[i.from_node][i.to_node] = {
					"db_name": to_data.db_name,
					"table_name": to_data.table_name,
					"link_type": to_node_extra.link_type,
					"link_prop_type": to_node_extra.link_prop_type,
					"link_prop": to_node_extra.link_prop,
					"link_col": []
				}
				
			node_pair[i.from_node][i.to_node].link_col.push_back([from_col, to_col])
			
	var leading_nodes = nodes_map.keys()
	for from_node_name in node_pair:
		for to_node_name in node_pair[from_node_name]:
			leading_nodes.erase(to_node_name)
			
	const prefixes = "abcdefghijklmnopqrstuvwxyz"
	
	# 每一个起始节点，有一套生成的xml、entity、mapper
	for lead_node_name in leading_nodes:
		var xml_arr = ["""<?xml version="1.0" encoding="UTF-8" ?>
	<!DOCTYPE mapper
	PUBLIC "-//mybatis.org//DTD Mapper 3.0//EN"
	"http://mybatis.org/dtd/mybatis-3-mapper.dtd">
	<mapper namespace="TestSkillMapper">
		<cache eviction="LRU" flushInterval="0" size="50" />
		"""]
		var arr_method = []
		var arr_columns = {}
		var left_joins = {}
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
		var leading_db_name = null
		var leading_table_name = null
		var table_counts = {}
		var column_counts = {} # 同名列
		
		# 递归找到与起始节点关联的诸多节点
		var linked_nodes = []
		get_linked_nodes(node_pair, lead_node_name, linked_nodes)
		
		for node_name in linked_nodes:
			var data = nodes_map[node_name].get_meta("data") as Dictionary
			var db_name = data.db_name as String
			var table_name = data.table_name as String
			var columns = data.columns as Dictionary
			
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
					
		for node_name in linked_nodes:
			prefix_index += 1
			table_alias[node_name] = valid_prefixes.keys()[prefix_index]
			var node = nodes_map[node_name]
			var data = node.get_meta("data") as Dictionary
			var db_name = data.db_name as String
			var table_name = data.table_name as String
			var table_name_camel = table_name.to_camel_case()
			var columns = data.columns as Dictionary
			var result_map_id = table_name_camel
			if node_link_prop.has(node.name):
				result_map_id = node_link_prop[node.name].to_camel_case()
			if leading_result_map_id == null:
				leading_result_map_id = result_map_id
				leading_db_name = db_name
				leading_table_name = table_name
				
			var arr_col = []
			var arr_col_name = []
			for col in columns:
				var prefix = '<id    ' if col.PK else '<result'
				arr_col.push_back('%s property="%s"    column="%s"    />' % \
					[prefix, col["Column Name"].to_snake_case(), col["Column Name"]]
				)
				arr_col_name.push_back(col["Column Name"])
			arr_columns[node_name] = arr_col_name
			
			if node_pair.has(node_name):
				left_joins[node_name] = []
				for to_node_name in node_pair[node.name]:
					var info = node_pair[node.name][to_node_name]
					left_joins[node_name].push_back({
						"table_alias": table_alias[to_node_name],
						"db_name": info.db_name,
						"table_name": info.table_name
					})
					
					var s = null
					var prefix = "<association" if info.link_type == \
						graph_edit.LINK_TYPE.ASSOCIATION else "<collection"
					var a_result_map_id = info.link_prop.to_camel_case() + "Result"
					
					if option_button_link.selected == LINK_WAY.NESTING_SELECT:
						var by = info.link_col.map(func(v): return v[1])
						by.sort()
						var method = 'select_%s_by_%s' % \
							[info.link_prop, "_".join(by)]
						var method_info = {
							"id": method,
							"result_map": a_result_map_id,
							"arg_names": by,
							"namespace": info.db_name + "." + info.table_name
						}
						
						# 为了避免因为各种原因导致method相同但实际上不能共用method的情况，
						# 需要给method名称加后缀。
						var new_index = 1
						var need_add_surfix = false
						for i in arr_method:
							if i.id.begins_with(method_info.method):
								var a_index = Array(i.id.split("_")).back().to_int()
								new_index = max(a_index, new_index) + 1
							if i.id == method_info.method:
								if i.result_map != method_info.result_map or \
								i.arg_names != method_info.arg_names or \
								i.namespace != method_info.namespace:
									need_add_surfix = true
									
						if need_add_surfix:
							method_info.id = method_info.id + "_" + new_index
							
						s = '%s property="%s" column="%s" columnPrefix="%s" select="%s"    />' % \
							[prefix, info.link_prop, ",".join(by), table_alias[node_name], 
							method_info.id]
							
						if not arr_method.has(method_info):
							arr_method.push_back(method_info)
					else:
						s = '%s property="%s" columnPrefix="%s" resultMap="%s"    />' % \
							[prefix, info.link_prop, table_alias[node_name], 
							a_result_map_id]
							
					arr_col.push_back(s)
					
			xml_arr.push_back(
				'\n\t<resultMap id="%sResult" type="%sEntity">\n\t\t%s\n\t</resultMap>\n' % \
					[result_map_id, result_map_id, "\n\t\t".join(arr_col)]
			)
			
		# <sql>
		if left_joins.is_empty():
			var vo = "select %s from %s.%s" % [", ".join(arr_columns[lead_node_name]), 
				leading_db_name, leading_table_name]
			xml_arr.push_back('\n\t<sql id="%sVo">\n\t\t%s\n\t</sql>\n' % \
				[leading_result_map_id, split_for_long_content(vo)])
		# nesting select 不使用left join，直接select主表即可，但是有多个sql
		elif option_button_link.selected == LINK_WAY.NESTING_SELECT:
			for node_name in linked_nodes:
				var data = nodes_map[node_name].get_meta("data") as Dictionary
				var db_name = data.db_name as String
				var table_name = data.table_name as String
				var vo = "select %s from %s.%s" % [", ".join(arr_columns[node_name]), 
					db_name, table_name]
				xml_arr.push_back('\n\t<sql id="%sVo">\n\t\t%s\n\t</sql>\n' % \
					["TODO", split_for_long_content(vo)]) # TODO
		# nesting resultMap 需要使用left join，把所有表形成一条sql
		else:
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
						split_for_long_content(", ".join(all_column_name)),
						leading_db_name, leading_table_name, t_alias
					]
				else:
					var db_name = null
					var table_name = null
					var cond = []
					for f in node_pair:
						for t in node_pair[f]:
							if t == node_name:
								db_name = node_pair[f][t].db_name
								table_name = node_pair[f][t].table_name
								var alias0 = table_alias[f]
								var alias1 = table_alias[t]
								for k in node_pair[f][t].link_col:
									cond.push_back('%s.%s == %s.%s' % [
										alias0, k[0], alias1, k[1]
									])
								break
					vo += "\n\t\tleft join %s.%s %s on %s" % [
						db_name, table_name, t_alias, " and ".join(cond)
					]
			xml_arr.push_back('\n\t<sql id="%sVo">\n\t\t%s\n\t</sql>\n' % \
			[leading_result_map_id, vo])
			
			
	return ""
	
func get_linked_nodes(node_pair: Dictionary, head_name, result: Array):
	result.push_back(head_name)
	if node_pair.has(head_name):
		for to_node_name in node_pair[head_name]:
			get_linked_nodes(node_pair, to_node_name, result)
			
## ALERT 基于全英文内容，且不包含引号。一个单词不会被切分开。
func split_for_long_content(content: String, delimiter = "\n") -> String:
	const l = 75
	var total_l = content.length()
	if total_l <= l:
		return content
	var arr = []
	var start = 0
	while true:
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
					arr.push_back(content.substr(start, ll - start))
					start = ll
					continue
		if start + l >= total_l:
			break
		start += l
	return delimiter.join(arr)
