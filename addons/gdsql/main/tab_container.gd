@tool
extends TabContainer

var mgr: GDSQL.WorkbenchManagerClass:
	get: return GDSQL.WorkbenchManager
	
var SQLFile = load("res://addons/gdsql/tabs/sql_file/sql_file.tscn")
var SQLGraph = load("res://addons/gdsql/tabs/sql_graph/sql_graph.tscn")
var MAPPER_GRAPH = load("res://addons/gdsql/tabs/mapper_graph/mapper_graph.tscn")

@onready var welcome_page: PanelContainer = %Welcome
@onready var new_tab_button: Control = %"➕"

const WELCOME_PAGE_TAB_INDEX = 0
var _tab_index = 1

var _tab_activate_time: float = 0
var _tab_history: Array

enum CLOSE_OPTION {
	CLOSE_CURRENT_TAB = 0,
	CLOSE_OTHER_TABS = 1,
	CLOSE_TABS_TO_THE_RIGHT = 2,
	CLOSE_ALL_TABS = 3,
}

func _ready() -> void:
	if mgr == null or not mgr.run_in_plugin(self):
		return
		
	if not mgr.open_add_schema_tab.is_connected(add_tab_new_schema):
		mgr.open_add_schema_tab.connect(add_tab_new_schema, CONNECT_DEFERRED)
	if not mgr.open_add_table_tab.is_connected(add_tab_new_table):
		mgr.open_add_table_tab.connect(add_tab_new_table, CONNECT_DEFERRED)
	if not mgr.open_alter_schema_tab.is_connected(add_tab_alter_schema):
		mgr.open_alter_schema_tab.connect(add_tab_alter_schema, CONNECT_DEFERRED)
	if not mgr.open_alter_table_tab.is_connected(add_tab_alter_table):
		mgr.open_alter_table_tab.connect(add_tab_alter_table, CONNECT_DEFERRED)
	if not mgr.open_table_inspector_tab.is_connected(add_tab_table_inspector):
		mgr.open_table_inspector_tab.connect(add_tab_table_inspector, CONNECT_DEFERRED)
	if not mgr.open_table_data_export_tab.is_connected(add_tab_table_data_export):
		mgr.open_table_data_export_tab.connect(add_tab_table_data_export, CONNECT_DEFERRED)
	if not mgr.open_table_data_import_tab.is_connected(add_tab_table_data_import):
		mgr.open_table_data_import_tab.connect(add_tab_table_data_import, CONNECT_DEFERRED)
	if not mgr.open_select_data_export_tab.is_connected(add_tab_select_data_export):
		mgr.open_select_data_export_tab.connect(add_tab_select_data_export, CONNECT_DEFERRED)
	if not mgr.open_mapper_graph_tab.is_connected(add_tab_mapper_graph):
		mgr.open_mapper_graph_tab.connect(add_tab_mapper_graph, CONNECT_DEFERRED)
	if not mgr.open_sql_text_file_tab.is_connected(add_tab_sql_file):
		mgr.open_sql_text_file_tab.connect(add_tab_sql_file)
	if not mgr.open_sql_graph_file_tab.is_connected(add_tab_graph_file):
		mgr.open_sql_graph_file_tab.connect(add_tab_graph_file)
	if not mgr.open_mapper_graph_file_tab.is_connected(add_tab_mapper_graph_file):
		mgr.open_mapper_graph_file_tab.connect(add_tab_mapper_graph_file)
	if not mgr.open_settings_tab.is_connected(add_tab_settings):
		mgr.open_settings_tab.connect(add_tab_settings, CONNECT_DEFERRED)
	if not mgr.open_license_tab.is_connected(add_tab_license):
		mgr.open_license_tab.connect(add_tab_license, CONNECT_DEFERRED)
		
	if not mgr.sys_confirm_add_schema.is_connected(close_content_window):
		mgr.sys_confirm_add_schema.connect(close_content_window, CONNECT_DEFERRED)
	if not mgr.sys_confirm_add_table.is_connected(close_content_window):
		mgr.sys_confirm_add_table.connect(close_content_window, CONNECT_DEFERRED)
	if not mgr.sys_confirm_alter_schema.is_connected(close_content_window):
		mgr.sys_confirm_alter_schema.connect(close_content_window, CONNECT_DEFERRED)
	if not mgr.sys_confirm_alter_table.is_connected(close_content_window):
		mgr.sys_confirm_alter_table.connect(close_content_window, CONNECT_DEFERRED)
	
	if not mgr.send_to_editor.is_connected(receive_content):
		mgr.send_to_editor.connect(receive_content, CONNECT_DEFERRED)
	if not mgr.send_to_editor_and_execute.is_connected(receive_content_and_execute):
		mgr.send_to_editor_and_execute.connect(receive_content_and_execute, CONNECT_DEFERRED)
		
	set_tab_icon(WELCOME_PAGE_TAB_INDEX, load("res://addons/gdsql/img/gdsql_text_icon.svg"))
	get_tab_bar().active_tab_rearranged.connect(_on_active_tab_rearranged)
	_add_tab_context_menu()
	
func _exit_tree():
	if mgr == null or not mgr.run_in_plugin(self):
		return
		
	# 清理右键菜单
	if _tab_context_menu:
		if _tab_context_menu.is_connected("popup_hide", _tab_context_menu.queue_free):
			_tab_context_menu.disconnect("popup_hide", _tab_context_menu.queue_free)
		_tab_context_menu.queue_free()
		_tab_context_menu = null
		
	if mgr.open_add_schema_tab.is_connected(add_tab_new_schema):
		mgr.open_add_schema_tab.disconnect(add_tab_new_schema)
	if mgr.open_add_table_tab.is_connected(add_tab_new_table):
		mgr.open_add_table_tab.disconnect(add_tab_new_table)
	if mgr.open_alter_schema_tab.is_connected(add_tab_alter_schema):
		mgr.open_alter_schema_tab.disconnect(add_tab_alter_schema)
	if mgr.open_alter_table_tab.is_connected(add_tab_alter_table):
		mgr.open_alter_table_tab.disconnect(add_tab_alter_table)
	if mgr.open_table_inspector_tab.is_connected(add_tab_table_inspector):
		mgr.open_table_inspector_tab.disconnect(add_tab_table_inspector)
	if mgr.open_table_data_export_tab.is_connected(add_tab_table_data_export):
		mgr.open_table_data_export_tab.disconnect(add_tab_table_data_export)
	if mgr.open_table_data_import_tab.is_connected(add_tab_table_data_import):
		mgr.open_table_data_import_tab.disconnect(add_tab_table_data_import)
	if mgr.open_select_data_export_tab.is_connected(add_tab_select_data_export):
		mgr.open_select_data_export_tab.disconnect(add_tab_select_data_export)
	if mgr.open_sql_text_file_tab.is_connected(add_tab_sql_file):
		mgr.open_sql_text_file_tab.disconnect(add_tab_sql_file)
	if mgr.open_sql_graph_file_tab.is_connected(add_tab_graph_file):
		mgr.open_sql_graph_file_tab.disconnect(add_tab_graph_file)
	if mgr.open_mapper_graph_tab.is_connected(add_tab_mapper_graph):
		mgr.open_mapper_graph_tab.disconnect(add_tab_mapper_graph)
	if mgr.open_mapper_graph_file_tab.is_connected(add_tab_mapper_graph_file):
		mgr.open_mapper_graph_file_tab.disconnect(add_tab_mapper_graph_file)
	if mgr.open_settings_tab.is_connected(add_tab_settings):
		mgr.open_settings_tab.disconnect(add_tab_settings)
	if mgr.open_license_tab.is_connected(add_tab_license):
		mgr.open_license_tab.disconnect(add_tab_license)
		
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
		
	# Fix files not saved to recent files.
	_on_tab_context_menu_pressed(CLOSE_OPTION.CLOSE_ALL_TABS)
	
	while get_child_count() > 0:
		var child = get_child(0)
		remove_child(child)
		child.queue_free()
		
	mgr = null
	
func _on_tab_clicked(tab: int) -> void:
	# 点击了“新建SQL页面”（加号），增加一个编辑页面，并激活
	if get_child(tab) == new_tab_button:
		add_tab_empty_graph()
		
func add_tab_empty_sql_file():
	var sql_file = SQLFile.instantiate()
	sql_file.request_open_file.connect(add_tab_sql_file)
	sql_file.change_tab_title.connect(func(page, title):
		var idx = get_tab_idx_from_control(page)
		if idx >= 0:
			set_tab_title(idx, title.get_basename())
	)
	add_child(sql_file)
	move_child(new_tab_button, get_child_count() - 1)
	current_tab = get_child_count() - 2
	set_tab_title(current_tab, "SQL File %d" % _tab_index)
	set_tab_icon(current_tab, load("res://addons/gdsql/img/sql_file.svg"))
	_tab_index += 1
	return sql_file
	
func add_tab_sql_file(path: String):
	if path.is_empty():
		add_tab_empty_sql_file()
		return
		
	# 是否已经打开过了，就直接激活
	for i in get_tab_count():
		var page = get_tab_control(i)
		if page.get_meta("type") == "sql_file" and \
		GDSQL.GDSQLUtils.localize_path(page.get_meta("file_path", "")) == GDSQL.GDSQLUtils.localize_path(path):
			current_tab = i
			return
			
	var sql_file = SQLFile.instantiate()
	sql_file.request_open_file.connect(add_tab_sql_file)
	sql_file.change_tab_title.connect(func(page, title):
		var idx = get_tab_idx_from_control(page)
		if idx >= 0:
			set_tab_title(idx, title)
	)
	add_child(sql_file)
	move_child(new_tab_button, get_child_count() - 1)
	current_tab = get_child_count() - 2
	set_tab_title(current_tab, path.get_file().get_basename())
	set_tab_icon(current_tab, load("res://addons/gdsql/img/sql_file.svg"))
	_tab_index += 1
	sql_file.load_graph_file(path)
	mgr.file_tab_opened.emit(path)
	
func add_tab_empty_graph():
	var sql_graph = SQLGraph.instantiate()
	sql_graph.request_open_file.connect(add_tab_graph_file)
	sql_graph.change_tab_title.connect(func(page, title):
		var idx = get_tab_idx_from_control(page)
		if idx >= 0:
			set_tab_title(idx, title.get_basename())
	)
	add_child(sql_graph)
	move_child(new_tab_button, get_child_count() - 1)
	current_tab = get_child_count() - 2
	set_tab_title(current_tab, "Graph File %d" % _tab_index)
	set_tab_icon(current_tab, load("res://addons/gdsql/img/GDSQLGraph.svg"))
	_tab_index += 1
	return sql_graph
	
func add_tab_graph_file(path: String) -> void:
	if path.is_empty():
		add_tab_empty_graph()
		return
		
	# 是否已经打开过了，就直接激活
	for i in get_tab_count():
		var page = get_tab_control(i)
		if page.get_meta("type") == "sql_graph" and \
		GDSQL.GDSQLUtils.localize_path(page.get_meta("file_path", "")) == GDSQL.GDSQLUtils.localize_path(path):
			current_tab = i
			return
			
	var sql_graph = SQLGraph.instantiate()
	sql_graph.request_open_file.connect(add_tab_graph_file)
	sql_graph.change_tab_title.connect(func(page, title):
		var idx = get_tab_idx_from_control(page)
		if idx >= 0:
			set_tab_title(idx, title)
	)
	add_child(sql_graph)
	move_child(new_tab_button, get_child_count() - 1)
	current_tab = get_child_count() - 2
	set_tab_title(current_tab, path.get_file().get_basename())
	set_tab_icon(current_tab, load("res://addons/gdsql/img/GDSQLGraph.svg"))
	_tab_index += 1
	sql_graph.load_graph_file(path)
	mgr.file_tab_opened.emit(path)
	
func add_tab_new_schema() -> void:
	var new_schema = load("res://addons/gdsql/tabs/new_schema/new_schema.tscn").instantiate()
	add_child(new_schema)
	move_child(new_tab_button, get_child_count() - 1)
	current_tab = get_child_count() - 2
	set_tab_title(current_tab, "new_schema")
	
func add_tab_alter_schema(db_name, path) -> void:
	var alter_schema = load("res://addons/gdsql/tabs/alter_schema/alter_schema.tscn").instantiate()
	alter_schema.old_db_name = db_name
	alter_schema.db_name = GDSQL.RootConfig.get_database_display_name(db_name)
	alter_schema.path = path
	add_child(alter_schema)
	move_child(new_tab_button, get_child_count() - 1)
	current_tab = get_child_count() - 2
	set_tab_title(current_tab, "alter_schema")
	
func add_tab_new_table(db_name, like_db_name = "", like_table_name = "") -> void:
	var new_table = load("res://addons/gdsql/tabs/new_table/new_table.tscn").instantiate()
	new_table.schema = db_name
	# 如果是create table like，把参考表的表结构复制过来
	if like_db_name != "" and like_table_name != "":
		var defination = mgr.databases.get(like_db_name, {}).get("tables", {}).get(like_table_name, {}) as Dictionary
		new_table.table_name = defination.get("display_name", like_table_name)
		new_table.comment = defination.get("comment", "")
		var datas = defination.get("columns", [])
		for i in datas:
			if not i.has("Index"):
				i.Index = false
		new_table.raw_datas = datas
	add_child(new_table)
	move_child(new_tab_button, get_child_count() - 1)
	current_tab = get_child_count() - 2
	set_tab_title(current_tab, "new_table")
	
func add_tab_alter_table(db_name, table_name) -> void:
	var alter_table = load("res://addons/gdsql/tabs/alter_table/alter_table.tscn").instantiate()
	var db_display = GDSQL.RootConfig.get_database_display_name(db_name)
	var table_def = mgr.databases.get(db_name, {}).get("tables", {}).get(table_name, {})
	var table_display = table_def.get("display_name", table_name) if table_def else table_name
	alter_table.schema = db_display
	alter_table.old_table_name = table_name
	alter_table.table_name = table_display
	var defination = table_def as Dictionary
	alter_table.comment = defination.get("comment", "")
	alter_table.valid_if_not_exist = defination.get("valid_if_not_exist", false)
	var datas = defination.get("columns", [])
	for i in datas:
		if not i.has("Index"):
			i.Index = false
	alter_table.raw_datas = datas
	add_child(alter_table)
	move_child(new_tab_button, get_child_count() - 1)
	current_tab = get_child_count() - 2
	set_tab_title(current_tab, "alter_table")
	
func add_tab_table_inspector(db_name, table_name) -> void:
	var table_inspector = load("res://addons/gdsql/tabs/table_inspector/table_inspector.tscn").instantiate()
	table_inspector.schema = db_name
	table_inspector.table_name = table_name
	var defination = mgr.databases.get(db_name, {}).get("tables", {}).get(table_name, {}) as Dictionary
	table_inspector.comment = defination.get("comment", "")
	var data_file_path = GDSQL.RootConfig.get_table_data_path(db_name, table_name)
	var absolute_path = GDSQL.GDSQLUtils.globalize_path(data_file_path)
	table_inspector.data_file_path = data_file_path if data_file_path == absolute_path \
		else "%s (%s)" % [data_file_path, absolute_path]
	var data_file = FileAccess.open(absolute_path, FileAccess.READ)
	table_inspector.data_file_size = "%d KB (%d Byte)" % [ceili(data_file.get_length() / 1024.0), data_file.get_length()]
	var update_total_data_count = func():
		if mgr.databases[db_name]["tables"][table_name]["encrypted"] == "" or GDSQL.ConfManager.has_conf(data_file_path):
			table_inspector.total_data_count = str(GDSQL.ConfManager.get_conf(data_file_path, "").get_sections().size())
		else:
			table_inspector.total_data_count = ""
	table_inspector.update_total_data_count = update_total_data_count
	update_total_data_count.call()
	table_inspector.comment = defination.get("comment", "")
	var datas = defination.get("columns", [])
	for i in datas:
		if not i.has("Index"):
			i.Index = false
	table_inspector.raw_datas = datas
	add_child(table_inspector)
	move_child(new_tab_button, get_child_count() - 1)
	current_tab = get_child_count() - 2
	set_tab_title(current_tab, "Inspector:%s" % table_name)
	
func add_tab_table_data_export(db_name, table_name) -> void:
	var table_data_export = load("res://addons/gdsql/tabs/table_data_export/table_data_export.tscn").instantiate()
	add_child(table_data_export)
	move_child(new_tab_button, get_child_count() - 1)
	current_tab = get_child_count() - 2
	set_tab_title(current_tab, "Table Data Export")
	table_data_export.select_table(db_name, table_name)
	
func add_tab_table_data_import(db_name, table_name) -> void:
	var table_data_import = load("res://addons/gdsql/tabs/table_data_import/table_data_import.tscn").instantiate()
	add_child(table_data_import)
	move_child(new_tab_button, get_child_count() - 1)
	current_tab = get_child_count() - 2
	set_tab_title(current_tab, "Table Data Import")
	table_data_import.select_table(db_name, table_name)
	
func add_tab_select_data_export(columns: Array, datas: Array) -> void:
	var select_data_export = load("res://addons/gdsql/tabs/select_data_export/select_data_export.tscn").instantiate()
	add_child(select_data_export)
	move_child(new_tab_button, get_child_count() - 1)
	current_tab = get_child_count() - 2
	set_tab_title(current_tab, "Select Data Export")
	select_data_export.load_data(columns, datas)
	
func add_tab_mapper_graph(info: Dictionary):
	var mapper_file = add_tab_empty_mapper_graph()
	mapper_file.load_data(info)
	
func add_tab_empty_mapper_graph():
	var mapper_file = MAPPER_GRAPH.instantiate()
	mapper_file.request_open_file.connect(add_tab_mapper_graph_file)
	mapper_file.change_tab_title.connect(func(page, title):
		var idx = get_tab_idx_from_control(page)
		if idx >= 0:
			set_tab_title(idx, title)
	)
	add_child(mapper_file)
	move_child(new_tab_button, get_child_count() - 1)
	current_tab = get_child_count() - 2
	set_tab_title(current_tab, "Mapper File %d" % _tab_index)
	set_tab_icon(current_tab, load("res://addons/gdsql/gbatis/img/GBMapperGraph.svg"))
	_tab_index += 1
	return mapper_file
	
func add_tab_mapper_graph_file(path: String):
	if path.is_empty():
		add_tab_empty_mapper_graph()
		return
		
	# 是否已经打开过了，就直接激活
	for i in get_tab_count():
		var page = get_tab_control(i)
		if page.get_meta("type") == "mapper_graph" and \
		GDSQL.GDSQLUtils.localize_path(page.get_meta("file_path", "")) == GDSQL.GDSQLUtils.localize_path(path):
			current_tab = i
			return
			
	var mapper_file = MAPPER_GRAPH.instantiate()
	mapper_file.request_open_file.connect(add_tab_mapper_graph_file)
	mapper_file.change_tab_title.connect(func(page, title):
		var idx = get_tab_idx_from_control(page)
		if idx >= 0:
			set_tab_title(idx, title)
	)
	add_child(mapper_file)
	move_child(new_tab_button, get_child_count() - 1)
	current_tab = get_child_count() - 2
	set_tab_title(current_tab, path.get_file().get_basename())
	set_tab_icon(current_tab, load("res://addons/gdsql/gbatis/img/GBMapperGraph.svg"))
	_tab_index += 1
	mapper_file.load_mapper_file(path)
	mgr.file_tab_opened.emit(path)
	
func add_tab_settings() -> void:
	# 检查是否已经打开了设置页签，直接激活
	for i in get_tab_count():
		var page = get_tab_control(i)
		if page.get_meta("type") == "settings":
			current_tab = i
			return
			
	var settings_tab = load("res://addons/gdsql/tabs/settings/gsql_tab_settings.tscn").instantiate()
	add_child(settings_tab)
	move_child(new_tab_button, get_child_count() - 1)
	current_tab = get_child_count() - 2
	set_tab_title(current_tab, "Settings")
	
func add_tab_license() -> void:
	for i in get_tab_count():
		var page = get_tab_control(i)
		if page.get_meta("type") == "license":
			current_tab = i
			return

	var license_page = load("res://addons/gdsql/tabs/license/license.gd").new()
	license_page.set_meta("type", "license")
	add_child(license_page)
	move_child(new_tab_button, get_child_count() - 1)
	current_tab = get_child_count() - 2
	set_tab_title(current_tab, "Licenses")


func _on_tab_button_pressed(tab: int) -> void:
	if tab != current_tab:
		current_tab = tab
		return
		
	if Time.get_unix_time_from_system() - _tab_activate_time < 0.5:
		return
		
	_close_tab(tab)
	# TODO 有内容的时候要提示保存或者二次确认
	
func _on_active_tab_rearranged(_idx_to: int):
	await get_tree().process_frame
	if get_tab_control(WELCOME_PAGE_TAB_INDEX) != welcome_page:
		move_child(welcome_page, WELCOME_PAGE_TAB_INDEX)
		
func _switch_to_previous_page(current_page: Node):
	for i in range(_tab_history.size() -1, -1, -1):
		if _tab_history[i] == current_page:
			continue
		current_tab = get_tab_idx_from_control(_tab_history[i])
		break
		
func close_content_window(content_id: String):
	var child = get_node(content_id)
	if child:
		_switch_to_previous_page(child)
		remove_child(child)
		child.queue_free()
		

var _tab_context_menu: PopupMenu

func _add_tab_context_menu():
	_tab_context_menu = PopupMenu.new()
	_tab_context_menu.add_item(tr("Close"), CLOSE_OPTION.CLOSE_CURRENT_TAB)
	_tab_context_menu.add_item(tr("Close Other Tabs"), CLOSE_OPTION.CLOSE_OTHER_TABS)
	_tab_context_menu.add_item(tr("Close Tabs to the Right"), CLOSE_OPTION.CLOSE_TABS_TO_THE_RIGHT)
	_tab_context_menu.add_item(tr("Close All Tabs"), CLOSE_OPTION.CLOSE_ALL_TABS)
	_tab_context_menu.id_pressed.connect(_on_tab_context_menu_pressed)
	# 注意：不能 add_child 到 TabContainer，会影响 get_child_count() 导致➕按钮下标计算错误
	get_tree().root.add_child(_tab_context_menu)
	get_tab_bar().gui_input.connect(_on_tab_bar_gui_input)

func _on_tab_bar_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed:
		var tab_bar = get_tab_bar()
		var tab_idx = -1
		for i in tab_bar.get_tab_count():
			if tab_bar.get_tab_rect(i).has_point(event.position):
				tab_idx = i
				break
		if tab_idx < 0:
			return
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				_on_tab_right_clicked(tab_idx)
			MOUSE_BUTTON_MIDDLE:
				_close_tab(tab_idx)

func _on_tab_right_clicked(clicked_tab: int):
	# 只对实际的内容标签页显示右键菜单（排除欢迎页和➕按钮）
	if clicked_tab <= WELCOME_PAGE_TAB_INDEX:
		return
	var tab_control = get_tab_control(clicked_tab)
	if tab_control == null or tab_control == new_tab_button:
		return
	current_tab = clicked_tab

	# 检查是否有“其他选项卡”
	var has_other_tabs = false
	var has_tabs_to_right = false
	for i in get_tab_count():
		if i == WELCOME_PAGE_TAB_INDEX or get_tab_control(i) == new_tab_button:
			continue
		if i != clicked_tab:
			has_other_tabs = true
		if i > clicked_tab:
			has_tabs_to_right = true

	_tab_context_menu.set_item_disabled(_tab_context_menu.get_item_index(CLOSE_OPTION.CLOSE_CURRENT_TAB), false)  # Close 永远可用
	_tab_context_menu.set_item_disabled(_tab_context_menu.get_item_index(CLOSE_OPTION.CLOSE_OTHER_TABS), not has_other_tabs)  # Close Other Tabs
	_tab_context_menu.set_item_disabled(_tab_context_menu.get_item_index(CLOSE_OPTION.CLOSE_TABS_TO_THE_RIGHT), not has_tabs_to_right)  # Close Tabs to the Right
	_tab_context_menu.set_item_disabled(_tab_context_menu.get_item_index(CLOSE_OPTION.CLOSE_ALL_TABS), false)  # Close All 永远可用

	_tab_context_menu.position = DisplayServer.mouse_get_position()
	_tab_context_menu.popup()
	_tab_context_menu.grab_focus()

func _on_tab_context_menu_pressed(id: int):
	match id:
		CLOSE_OPTION.CLOSE_CURRENT_TAB:  # Close current
			_close_tab(current_tab)
		CLOSE_OPTION.CLOSE_OTHER_TABS:  # Close other tabs
			_close_tabs(func(i): return i != current_tab and i != WELCOME_PAGE_TAB_INDEX and get_child(i) != new_tab_button)
		CLOSE_OPTION.CLOSE_TABS_TO_THE_RIGHT:  # Close tabs to the right
			_close_tabs(func(i): return i > current_tab and get_child(i) != new_tab_button)
		CLOSE_OPTION.CLOSE_ALL_TABS:  # Close all tabs
			_close_tabs(func(i): return i != WELCOME_PAGE_TAB_INDEX and get_child(i) != new_tab_button)

func _close_tab(tab_idx: int):
	if tab_idx < 0 or tab_idx >= get_tab_count():
		return
	var child = get_tab_control(tab_idx)
	if child == new_tab_button or tab_idx == WELCOME_PAGE_TAB_INDEX:
		return
		
	if child.get_meta("type") in ["sql_graph", "mapper_graph"]:
		if child.get_meta("file_path", ""):
			mgr.file_tab_closed.emit(child.get_meta("file_path"))
			
	_switch_to_previous_page(child)
	remove_child(child)
	child.queue_free()

func _close_tabs(filter: Callable):
	# Collect tabs to close (from right to left to keep indices stable)
	var tabs_to_close = []
	for i in get_tab_count():
		if filter.call(i):
			tabs_to_close.push_back(i)
	tabs_to_close.reverse()
	for i in tabs_to_close:
		_close_tab(i)

## 切换标签的时候，把激活的标签上加一个关闭按钮，没激活的标签取消关闭按钮防止误触
func _on_tab_changed(tab: int) -> void:
	var tab_control = get_tab_control(tab)
	
	# 保持最新的tab在最尾端
	if tab_control != new_tab_button:
		if _tab_history.has(tab_control):
			_tab_history.erase(tab_control)
		_tab_history.push_back(tab_control)
		
	_tab_activate_time = Time.get_unix_time_from_system()
	#if tab == WELCOME_PAGE_TAB_INDEX:
		#welcome_page.name = tr("Welcome")
	#else:
		#welcome_page.name = "\n"
	if tab_control != new_tab_button:
		if tab != WELCOME_PAGE_TAB_INDEX:
			set_tab_button_icon(tab, get_theme_icon("Close", "EditorIcons"))
			
		for i in get_tab_count():
			if i != tab and i > WELCOME_PAGE_TAB_INDEX:
				set_tab_button_icon(i, null)
				
func receive_content(_content: String, force_new: bool = false, file_path: String = ""):
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
		
	#var graph_edit = get_tab_control(current_tab).graph_edit as GraphEdit
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
			
func _on_child_exiting_tree(node: Node) -> void:
	if node in _tab_history:
		_tab_history.erase(node)
