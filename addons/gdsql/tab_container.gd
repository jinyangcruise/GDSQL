@tool
extends TabContainer

var mgr: GDSQLWorkbenchManagerClass = Engine.get_singleton("GDSQLWorkbenchManager")

var SQLGraph = preload("res://addons/gdsql/tabs/sql_graph.tscn")

@onready var new_tab_button: Control = $"➕"

var _tab_index = 1

var _tab_activate_time: float = 0

func _ready() -> void:
	if not mgr.run_in_plugin(self):
		return
		
	if not mgr.open_add_schema_tab.is_connected(add_tab_new_schema):
		mgr.open_add_schema_tab.connect(add_tab_new_schema)
	if not mgr.open_add_table_tab.is_connected(add_tab_new_table):
		mgr.open_add_table_tab.connect(add_tab_new_table)
	if not mgr.open_alter_schema_tab.is_connected(add_tab_alter_schema):
		mgr.open_alter_schema_tab.connect(add_tab_alter_schema)
	if not mgr.open_alter_table_tab.is_connected(add_tab_alter_table):
		mgr.open_alter_table_tab.connect(add_tab_alter_table)
	
	if not mgr.sys_confirm_add_schema.is_connected(close_content_window):
		mgr.sys_confirm_add_schema.connect(close_content_window)
	if not mgr.sys_confirm_add_table.is_connected(close_content_window):
		mgr.sys_confirm_add_table.connect(close_content_window)
	if not mgr.sys_confirm_alter_schema.is_connected(close_content_window):
		mgr.sys_confirm_alter_schema.connect(close_content_window)
	if not mgr.sys_confirm_alter_table.is_connected(close_content_window):
		mgr.sys_confirm_alter_table.connect(close_content_window)
	
	if not mgr.send_to_editor.is_connected(receive_content):
		mgr.send_to_editor.connect(receive_content)
	if not mgr.send_to_editor_and_execute.is_connected(receive_content_and_execute):
		mgr.send_to_editor_and_execute.connect(receive_content_and_execute)
	
	_on_tab_clicked(0)
	
func _exit_tree():
	if not mgr.run_in_plugin(self):
		return
		
	if mgr.open_add_schema_tab.is_connected(add_tab_new_schema):
		mgr.open_add_schema_tab.disconnect(add_tab_new_schema)
	if mgr.open_add_table_tab.is_connected(add_tab_new_table):
		mgr.open_add_table_tab.disconnect(add_tab_new_table)
	if mgr.open_alter_schema_tab.is_connected(add_tab_alter_schema):
		mgr.open_alter_schema_tab.disconnect(add_tab_alter_schema)
	if mgr.open_alter_table_tab.is_connected(add_tab_alter_table):
		mgr.open_alter_table_tab.disconnect(add_tab_alter_table)
	
	if mgr.sys_confirm_add_schema.is_connected(close_content_window):
		mgr.sys_confirm_add_schema.disconnect(close_content_window)
	if mgr.sys_confirm_add_table.is_connected(close_content_window):
		mgr.sys_confirm_add_table.disconnect(close_content_window)
	if mgr.sys_confirm_alter_schema.is_connected(close_content_window):
		mgr.sys_confirm_alter_schema.disconnect(close_content_window)
	if mgr.sys_confirm_alter_table.is_connected(close_content_window):
		mgr.sys_confirm_alter_table.disconnect(close_content_window)
	
	if mgr.send_to_editor.is_connected(receive_content):
		mgr.send_to_editor.disconnect(receive_content)
	if mgr.send_to_editor_and_execute.is_connected(receive_content_and_execute):
		mgr.send_to_editor_and_execute.disconnect(receive_content_and_execute)
		
	while get_child_count() > 0:
		var child = get_child(0)
		remove_child(child)
		child.queue_free()
	
func _on_tab_clicked(tab: int) -> void:
	# 点击了“新建SQL页面”（加号），增加一个编辑页面，并激活
	if get_child(tab) == new_tab_button:
		var sql_file = SQLGraph.instantiate()
		sql_file.request_open_file.connect(func(path):
			# 是否已经打开过了，就直接激活
			for i in get_tab_count():
				var page = get_tab_control(i)
				if page.get_meta("type") == "sql_graph" and page.get_meta("file_path") == path:
					current_tab = i
					return
					
			var file = FileAccess.open(path, FileAccess.READ)
			var content = file.get_as_text()
			receive_content(content, true, path)
		)
		sql_file.change_tab_title.connect(func(page, title):
			var idx = get_tab_idx_from_control(page)
			if idx >= 0:
				set_tab_title(idx, title)
		)
		add_child(sql_file)
		move_child(new_tab_button, get_child_count() - 1)
		current_tab = get_child_count() - 2
		set_tab_title(current_tab, "SQL File %d" % _tab_index)
		_tab_index += 1
		
func add_tab_new_schema() -> void:
	var new_schema = preload("res://addons/gdsql/tabs/new_schema.tscn").instantiate()
	add_child(new_schema)
	move_child(new_tab_button, get_child_count() - 1)
	current_tab = get_child_count() - 2
	set_tab_title(current_tab, "new_schema")
		
func add_tab_alter_schema(db_name, path) -> void:
	var alter_schema = preload("res://addons/gdsql/tabs/alter_schema.tscn").instantiate()
	alter_schema.old_db_name = db_name
	alter_schema.db_name = db_name
	alter_schema.path = path
	add_child(alter_schema)
	move_child(new_tab_button, get_child_count() - 1)
	current_tab = get_child_count() - 2
	set_tab_title(current_tab, "alter_schema")
	
func add_tab_new_table(db_name, like_db_name = "", like_table_name = "") -> void:
	var new_table = preload("res://addons/gdsql/tabs/new_table.tscn").instantiate()
	new_table.schema = db_name
	# 如果是create table like，把参考表的表结构复制过来
	if like_db_name != "" and like_table_name != "":
		var defination = mgr.databases.get(like_db_name, {}).get("tables", {}).get(like_table_name, {}) as Dictionary
		new_table.comment = defination.get("comment", "")
		new_table.raw_datas = defination.get("columns", [])
	add_child(new_table)
	move_child(new_tab_button, get_child_count() - 1)
	current_tab = get_child_count() - 2
	set_tab_title(current_tab, "new_table")
	
func add_tab_alter_table(db_name, table_name) -> void:
	var alter_table = preload("res://addons/gdsql/tabs/alter_table.tscn").instantiate()
	alter_table.schema = db_name
	alter_table.old_table_name = table_name
	alter_table.table_name = table_name
	var defination = mgr.databases.get(db_name, {}).get("tables", {}).get(table_name, {}) as Dictionary
	alter_table.comment = defination.get("comment", "")
	alter_table.raw_datas = defination.get("columns", [])
	add_child(alter_table)
	move_child(new_tab_button, get_child_count() - 1)
	current_tab = get_child_count() - 2
	set_tab_title(current_tab, "alter_table")
	
func _on_tab_button_pressed(tab: int) -> void:
	if tab != current_tab:
		current_tab = tab
		return
		
	if Time.get_unix_time_from_system() - _tab_activate_time < 0.5:
		return
		
	remove_child(get_tab_control(tab))
	# TODO 有内容的时候要提示保存或者二次确认
	
func close_content_window(content_id: String):
	var child = get_node(content_id)
	if child:
		child.queue_free()

## 切换标签的时候，把激活的标签上加一个关闭按钮，没激活的标签取消关闭按钮防止误触
func _on_tab_changed(tab: int) -> void:
	_tab_activate_time = Time.get_unix_time_from_system()
	if get_tab_control(tab) != new_tab_button:
		set_tab_button_icon(tab, preload("res://addons/gdsql/img/xmark.png"))
		
		for i in get_tab_count():
			if i != tab:
				set_tab_button_icon(i, null)
				
func receive_content(content: String, force_new: bool = false, file_path: String = ""):
	#TODO
	# 当前打开的页签是一个编辑器，则直接发送，否则创建一个
	if get_tab_control(current_tab).get_meta("type") == "sql_graph":
		if force_new:
			var graph_edit_1 = get_tab_control(current_tab).graph_edit as GraphEdit
			# 空的可以直接用，非空的还是需要创建新的；如果是文件，即使是空的，也要开新的
			if graph_edit_1.get_child_count() > 0 or get_tab_control(current_tab).has_meta("is_file"):
				_on_tab_clicked(get_tab_count()-1)
	else :
		_on_tab_clicked(get_tab_count()-1)
		
	var graph_edit = get_tab_control(current_tab).graph_edit as GraphEdit
	#code_edit.text += content TODO
	
	if not file_path.is_empty():
		var file_name = file_path.get_file()
		var page = get_current_tab_control()
		page.set_meta("is_file", true)
		page.set_meta("file_name", file_name)
		page.set_meta("file_path", file_path)
		set_tab_title(current_tab, file_name)
	
func receive_content_and_execute(title: String, info: Dictionary):
	# 因为要执行，所以直接创建新页面
	_on_tab_clicked(get_tab_count()-1)
	
	set_tab_title(current_tab, title)
	
	var sql_graph = get_tab_control(current_tab)
	if not sql_graph.is_node_ready():
		await sql_graph.ready
		
	if not sql_graph.graph_edit.is_node_ready():
		await sql_graph.graph_edit.ready
		
	match info["cmd"]:
		"select":
			sql_graph.add_select_node(info["db_name"], info["table_name"], info["fields"])
