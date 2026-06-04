@tool
extends MarginContainer

@onready var panel_container: PanelContainer = %PanelContainer
@onready var panel_container_2: PanelContainer = %PanelContainer2
@onready var tree_databases: Tree = %TreeDatabases
@onready var tab_container: TabContainer = %TabContainer
@onready var log_table: VBoxContainer = %LogTable
@onready var popup_menu_file: PopupMenu = %PopupMenuFile
@onready var popup_menu_edit: PopupMenu = %PopupMenuEdit
@onready var popup_menu_search: PopupMenu = %PopupMenuSearch
@onready var popup_menu_view: PopupMenu = %PopupMenuView
@onready var popup_menu_query: PopupMenu = %PopupMenuQuery
@onready var popup_menu_database: PopupMenu = %PopupMenuDatabase
@onready var popup_menu_tools: PopupMenu = %PopupMenuTools
@onready var popup_menu_help: PopupMenu = %PopupMenuHelp

var xml_editor_window: Window
var recent_files_sub_menu: PopupMenu
var file_not_exist_dialog: AcceptDialog

const RECENT_FILES_CONFIG_PATH = "user://gdsql/recent_files.cfg"
var recent_files_config: ConfigFile

enum FILE_MENU {
	NEW_QUERY_TAB = 0,
	NEW_GRAPH_TAB = 1,
	NEW_MAPPER_TAB = 2,
	OPEN = 3,
	OPEN_RECENT = 4,
	CLOSE_TAB = 6,
	SAVE = 8,
	SAVE_AS = 9,
	EXIT = 11,
}

enum EDIT_MENU {
	UNDO = 0,
	REDO = 1,
	CUT = 3,
	COPY = 4,
	PASTE = 5,
	DELETE = 6,
	SELECT_ALL = 8,
	AUTO_COMPLETE = 10,
	FORMAT = 11,
	SETTINGS = 13,
}

enum SEARCH_MENU {
	FIND = 0,
	FIND_NEXT = 1,
	FIND_PREVIOUS = 2,
	REPLACE = 3,
	FIND_IN_FILES = 5,
	REPLACE_IN_FILES = 6,
}

enum VIEW_MENU {
	WELCOME = 0,
	PANELS = 1,
	SELECT_NEXT_TAB = 3,
	SELECT_PREVIOUS_TAB = 4,
}

enum QUERY_MENU {
	EXECUTE_ALL_OR_SELECTION = 0,
	EXECUTE_CURRENT_STATEMENT = 1,
	STOP = 3,
	STOP_EXECUTION_ON_ERRORS = 4,
	LIMIT_ROWS = 6,
	AUTO_COMMIT_TRANSACTIONS = 8,
	COMMIT_TRANSACTION = 9,
	ROLLBACK_TRANSACTION = 10,
	COMMIT_RESULT_EDITS = 12,
	DISCARD_RESULT_EDITS = 13,
	EXPORT_RESULTS = 15,
}

enum DATABASE_MENU {
	SCHEMA_TRANSFER_WIZARD = 0,
	SEARCH_TABLE_DATA = 2,
}

enum TOOLS_MENU {
	XML_EDITOR = 0,
}

enum HELP_MENU {
	SEARCH_HELP = 0,
	ONLINE_DOCUMENTATION = 2,
	FORUM = 3,
	COMMUNITY = 4,
	COPY_SYSTEM_INFO = 6,
	REPORT_A_BUG = 7,
	SUGGEST_A_FEATURE = 8,
	SEND_DOCS_FEEDBACK = 9,
	ABOUT_GDSQL = 11,
	SUPPORT_GDSQL_DEVELOPMENT = 12,
}

func _ready() -> void:
	if GDSQL.WorkbenchManager == null or not GDSQL.WorkbenchManager.run_in_plugin(self):
		return
		
	set_translation_domain("GDSQL")
	
	if not GDSQL.WorkbenchManager.add_log_history.is_connected(add_a_log):
		GDSQL.WorkbenchManager.add_log_history.connect(add_a_log)
		
	if not GDSQL.WorkbenchManager.file_tab_opened.is_connected(remove_from_recent_history):
		GDSQL.WorkbenchManager.file_tab_opened.connect(remove_from_recent_history)
	if not GDSQL.WorkbenchManager.file_tab_closed.is_connected(add_to_recent_history):
		GDSQL.WorkbenchManager.file_tab_closed.connect(add_to_recent_history)
		
	var sb: StyleBoxFlat = get_theme_stylebox(&"panel", &"TabContainer").duplicate()
	sb.corner_radius_top_left = 0
	sb.corner_radius_top_right = 5
	sb.corner_radius_bottom_left = 5
	sb.corner_radius_bottom_right = 5
	sb.content_margin_left = 0
	panel_container.add_theme_stylebox_override(&"panel", sb)
	
	var sb2: StyleBoxFlat = get_theme_stylebox(&"panel", &"TabContainer").duplicate()
	sb2.corner_radius_top_left = 5
	sb2.corner_radius_top_right = 0
	sb2.corner_radius_bottom_left = 5
	sb2.corner_radius_bottom_right = 5
	panel_container_2.add_theme_stylebox_override(&"panel", sb2)
	
	var sb3: StyleBoxFlat = get_theme_stylebox(&"panel", &"TabContainer").duplicate()
	sb3.corner_radius_top_left = 5
	sb3.corner_radius_top_right = 0
	sb3.corner_radius_bottom_left = 5
	sb3.corner_radius_bottom_right = 0
	tab_container.add_theme_stylebox_override(&"panel", sb3)
	tab_container.set_theme_type_variation("TabContainerInner")
	
	log_table.ratios = [22.0, 30.0, 8.0, 1.5, 0.4, 1.0] as Array[float]
	log_table.columns = [tr("Status"), "#", tr("Time"), tr("Action"), tr("Message"), tr("Duration / Cost")] as Array[String]
	
	_init_menus()
	
func _init_menus() -> void:
	# File menu
	popup_menu_file.add_item(tr("New Text Query Tab"), FILE_MENU.NEW_QUERY_TAB)
	popup_menu_file.add_item(tr("New SQL Graph Tab"), FILE_MENU.NEW_GRAPH_TAB)
	popup_menu_file.set_item_icon(popup_menu_file.get_item_index(FILE_MENU.NEW_GRAPH_TAB), load("res://addons/gdsql/img/GDSQLGraph.svg"))
	popup_menu_file.add_item(tr("New Mapper Graph Tab"), FILE_MENU.NEW_MAPPER_TAB)
	popup_menu_file.set_item_icon(popup_menu_file.get_item_index(FILE_MENU.NEW_MAPPER_TAB), load("res://addons/gdsql/gbatis/img/GBMapperGraph.svg"))
	popup_menu_file.add_separator()
	popup_menu_file.add_item(tr("Open..."), FILE_MENU.OPEN)
	popup_menu_file.add_item(tr("Open Recent"), FILE_MENU.OPEN_RECENT)
	popup_menu_file.add_separator()
	popup_menu_file.add_item(tr("Close Tab"), FILE_MENU.CLOSE_TAB)
	popup_menu_file.add_separator()
	popup_menu_file.add_item(tr("Save"), FILE_MENU.SAVE)
	popup_menu_file.add_item(tr("Save As..."), FILE_MENU.SAVE_AS)
	popup_menu_file.add_separator()
	popup_menu_file.add_item(tr("Exit"), FILE_MENU.EXIT)
	popup_menu_file.id_pressed.connect(_on_file_menu_id_pressed)
	_init_recent_files()
	
	# Edit menu
	popup_menu_edit.add_item(tr("Undo"), EDIT_MENU.UNDO)
	popup_menu_edit.add_item(tr("Redo"), EDIT_MENU.REDO)
	popup_menu_edit.add_separator()
	popup_menu_edit.add_item(tr("Cut"), EDIT_MENU.CUT)
	popup_menu_edit.add_item(tr("Copy"), EDIT_MENU.COPY)
	popup_menu_edit.add_item(tr("Paste"), EDIT_MENU.PASTE)
	popup_menu_edit.add_item(tr("Delete"), EDIT_MENU.DELETE)
	popup_menu_edit.add_separator()
	popup_menu_edit.add_item(tr("Select All"), EDIT_MENU.SELECT_ALL)
	popup_menu_edit.add_separator()
	popup_menu_edit.add_item(tr("Auto Complete"), EDIT_MENU.AUTO_COMPLETE)
	popup_menu_edit.add_item(tr("Format"), EDIT_MENU.FORMAT)
	popup_menu_edit.add_separator()
	popup_menu_edit.add_item(tr("Settings..."), EDIT_MENU.SETTINGS)
	popup_menu_edit.id_pressed.connect(_on_edit_menu_id_pressed)
	
	# Search menu
	popup_menu_search.add_item(tr("Find"), SEARCH_MENU.FIND)
	popup_menu_search.add_item(tr("Find Next"), SEARCH_MENU.FIND_NEXT)
	popup_menu_search.add_item(tr("Find Previous"), SEARCH_MENU.FIND_PREVIOUS)
	popup_menu_search.add_item(tr("Replace..."), SEARCH_MENU.REPLACE)
	popup_menu_search.add_separator()
	popup_menu_search.add_item(tr("Find in Files..."), SEARCH_MENU.FIND_IN_FILES)
	popup_menu_search.add_item(tr("Replace in Files..."), SEARCH_MENU.REPLACE_IN_FILES)
	popup_menu_search.id_pressed.connect(_on_search_menu_id_pressed)
	
	# View menu
	popup_menu_view.add_item(tr("Welcome"), VIEW_MENU.WELCOME)
	popup_menu_view.add_item(tr("Panels"), VIEW_MENU.PANELS)
	popup_menu_view.add_separator()
	popup_menu_view.add_item(tr("Select Next Tab"), VIEW_MENU.SELECT_NEXT_TAB)
	popup_menu_view.add_item(tr("Select Previous Tab"), VIEW_MENU.SELECT_PREVIOUS_TAB)
	popup_menu_view.id_pressed.connect(_on_view_menu_id_pressed)
	
	# Query menu
	popup_menu_query.add_item(tr("Execute (All or Selection)"), QUERY_MENU.EXECUTE_ALL_OR_SELECTION)
	popup_menu_query.add_item(tr("Execute Current Statement"), QUERY_MENU.EXECUTE_CURRENT_STATEMENT)
	popup_menu_query.add_separator()
	popup_menu_query.add_item(tr("Stop"), QUERY_MENU.STOP)
	popup_menu_query.add_check_item(tr("Stop Execution on Errors"), QUERY_MENU.STOP_EXECUTION_ON_ERRORS)
	popup_menu_query.add_separator()
	popup_menu_query.add_item(tr("Limit Rows"), QUERY_MENU.LIMIT_ROWS)
	popup_menu_query.add_separator()
	popup_menu_query.add_check_item(tr("Auto-Commit Transactions"), QUERY_MENU.AUTO_COMMIT_TRANSACTIONS)
	popup_menu_query.add_item(tr("Commit Transaction"), QUERY_MENU.COMMIT_TRANSACTION)
	popup_menu_query.add_item(tr("Rollback Transaction"), QUERY_MENU.ROLLBACK_TRANSACTION)
	popup_menu_query.add_separator()
	popup_menu_query.add_item(tr("Commit Result Edits"), QUERY_MENU.COMMIT_RESULT_EDITS)
	popup_menu_query.add_item(tr("Discard Result Edits"), QUERY_MENU.DISCARD_RESULT_EDITS)
	popup_menu_query.add_separator()
	popup_menu_query.add_item(tr("Export Results..."), QUERY_MENU.EXPORT_RESULTS)
	popup_menu_query.id_pressed.connect(_on_query_menu_id_pressed)
	
	# Database menu
	popup_menu_database.add_item(tr("Schema Transfer Wizard..."), DATABASE_MENU.SCHEMA_TRANSFER_WIZARD)
	popup_menu_database.add_separator()
	popup_menu_database.add_item(tr("Search Table Data..."), DATABASE_MENU.SEARCH_TABLE_DATA)
	popup_menu_database.id_pressed.connect(_on_database_menu_id_pressed)
	
	# Tools menu
	popup_menu_tools.add_item(tr("XML Editor"), TOOLS_MENU.XML_EDITOR)
	popup_menu_tools.set_item_icon(popup_menu_tools.get_item_index(TOOLS_MENU.XML_EDITOR), load("res://addons/gdsql/gbatis/img/xml.svg"))
	popup_menu_tools.id_pressed.connect(_on_tools_menu_id_pressed)
	
	# Help menu
	popup_menu_help.add_item(tr("Search Help..."), HELP_MENU.SEARCH_HELP)
	popup_menu_help.add_separator()
	popup_menu_help.add_item(tr("Online Documentation"), HELP_MENU.ONLINE_DOCUMENTATION)
	popup_menu_help.add_item(tr("Forum"), HELP_MENU.FORUM)
	popup_menu_help.add_item(tr("Community"), HELP_MENU.COMMUNITY)
	popup_menu_help.add_separator()
	popup_menu_help.add_item(tr("Copy System Info"), HELP_MENU.COPY_SYSTEM_INFO)
	popup_menu_help.add_item(tr("Report a Bug"), HELP_MENU.REPORT_A_BUG)
	popup_menu_help.add_item(tr("Suggest a Feature"), HELP_MENU.SUGGEST_A_FEATURE)
	popup_menu_help.add_item(tr("Send Docs Feedback"), HELP_MENU.SEND_DOCS_FEEDBACK)
	popup_menu_help.add_separator()
	popup_menu_help.add_item(tr("About GDSQL..."), HELP_MENU.ABOUT_GDSQL)
	popup_menu_help.add_item(tr("Support GDSQL Development"), HELP_MENU.SUPPORT_GDSQL_DEVELOPMENT)
	popup_menu_help.id_pressed.connect(_on_help_menu_id_pressed)
	
func _init_recent_files() -> void:
	if not DirAccess.dir_exists_absolute("user://gdsql"):
		DirAccess.make_dir_absolute("user://gdsql")
	recent_files_config = ConfigFile.new()
	recent_files_config.load(RECENT_FILES_CONFIG_PATH)
	
	recent_files_sub_menu = PopupMenu.new()
	recent_files_sub_menu.index_pressed.connect(_on_recent_files_sub_menu_index_pressed)
	refresh_recent_files_menu()
	popup_menu_file.set_item_submenu_node(popup_menu_file.get_item_index(FILE_MENU.OPEN_RECENT), recent_files_sub_menu)
	
	file_not_exist_dialog = AcceptDialog.new()
	file_not_exist_dialog.set_translation_domain("GDSQL")
	add_child(file_not_exist_dialog)
	
func refresh_recent_files_menu() -> void:
	var recent_files = recent_files_config.get_value("history", "files", [])
	recent_files_sub_menu.clear()
	var id = -1
	for path: String in recent_files:
		id += 1
		recent_files_sub_menu.add_item(path, id)
		match path.get_extension().to_lower():
			"gdsqlgraph":
				recent_files_sub_menu.set_item_icon(recent_files_sub_menu.get_item_index(id), load("res://addons/gdsql/img/GDSQLGraph.svg"))
			"gdmappergraph":
				recent_files_sub_menu.set_item_icon(recent_files_sub_menu.get_item_index(id), load("res://addons/gdsql/gbatis/img/GBMapperGraph.svg"))
				
	recent_files_sub_menu.add_separator()
	recent_files_sub_menu.add_item(tr("Clear Recent Files"))
	if recent_files.is_empty():
		recent_files_sub_menu.set_item_disabled(recent_files_sub_menu.get_item_count() - 1, true)
		
func add_to_recent_history(path: String) -> void:
	path = GDSQL.GDSQLUtils.localize_path(path)
	var recent_files = recent_files_config.get_value("history", "files", []) as Array
	if recent_files.has(path):
		recent_files.erase(path)
	recent_files.push_front(path)
	# 最多保留 20 个最近文件
	if recent_files.size() > 20:
		recent_files.resize(20)
	recent_files_config.set_value("history", "files", recent_files)
	recent_files_config.save(RECENT_FILES_CONFIG_PATH)
	refresh_recent_files_menu()
	
func remove_from_recent_history(path: String) -> void:
	path = GDSQL.GDSQLUtils.localize_path(path)
	var recent_files = recent_files_config.get_value("history", "files", []) as Array
	if recent_files.has(path):
		recent_files.erase(path)
		recent_files_config.set_value("history", "files", recent_files)
		recent_files_config.save(RECENT_FILES_CONFIG_PATH)
		refresh_recent_files_menu()
		
func clear_recent_history() -> void:
	recent_files_config.set_value("history", "files", [])
	recent_files_config.save(RECENT_FILES_CONFIG_PATH)
	
func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		if panel_container:
			var sb: StyleBoxFlat = get_theme_stylebox(&"panel", &"TabContainer").duplicate()
			sb.corner_radius_top_left = 0
			sb.corner_radius_top_right = 5
			sb.corner_radius_bottom_left = 5
			sb.corner_radius_bottom_right = 5
			sb.content_margin_left = 0
			panel_container.add_theme_stylebox_override(&"panel", sb)
		if panel_container_2:
			var sb2: StyleBoxFlat = get_theme_stylebox(&"panel", &"TabContainer").duplicate()
			sb2.corner_radius_top_left = 5
			sb2.corner_radius_top_right = 0
			sb2.corner_radius_bottom_left = 5
			sb2.corner_radius_bottom_right = 5
			panel_container_2.add_theme_stylebox_override(&"panel", sb2)
		if tab_container:
			var sb3: StyleBoxFlat = get_theme_stylebox(&"panel", &"TabContainer").duplicate()
			sb3.corner_radius_top_left = 5
			sb3.corner_radius_top_right = 0
			sb3.corner_radius_bottom_left = 5
			sb3.corner_radius_bottom_right = 0
			tab_container.add_theme_stylebox_override(&"panel", sb3)
			
func _exit_tree():
	if GDSQL.WorkbenchManager == null or not GDSQL.WorkbenchManager.run_in_plugin(self):
		return
		
	if GDSQL.WorkbenchManager.add_log_history.is_connected(add_a_log):
		GDSQL.WorkbenchManager.add_log_history.disconnect(add_a_log)
		
	if GDSQL.WorkbenchManager.file_tab_opened.is_connected(remove_from_recent_history):
		GDSQL.WorkbenchManager.file_tab_opened.disconnect(remove_from_recent_history)
	if GDSQL.WorkbenchManager.file_tab_closed.is_connected(add_to_recent_history):
		GDSQL.WorkbenchManager.file_tab_closed.disconnect(add_to_recent_history)
		
func _on_button_refresh_pressed() -> void:
	tree_databases.refresh()
	
func add_a_log(status: String, begin_timestamp: float, action: String, message, cost: float = 0) -> void:
	var now = Time.get_unix_time_from_system()
	if message is Array:
		message = " ".join(message)
	var new_log = [
		status,
		log_table.datas.size() + 1,
		Time.get_datetime_string_from_system(false, true) if is_zero_approx(begin_timestamp) else (
			Time.get_datetime_string_from_unix_time(
				now + Time.get_time_zone_from_system().get("bias", 0) * 60, true
			)
		),
		action,
		message,
		"%.3f sec / %.3f" % [(0.0 if is_zero_approx(begin_timestamp) else (now - begin_timestamp)), cost]
	]
	log_table.append_data(new_log)
	log_table.scroll_to_bottom()
	if status != "OK":
		EditorInterface.get_editor_toaster().push_toast(message, EditorToaster.SEVERITY_ERROR)
		
func _on_button_clear_log_pressed():
	log_table.datas = []

# ==================== Menu Handlers ====================

func _on_file_menu_id_pressed(id: int) -> void:
	match id:
		FILE_MENU.NEW_QUERY_TAB:
			_on_file_new_query_tab()
		FILE_MENU.NEW_GRAPH_TAB:
			_on_file_new_graph_tab()
		FILE_MENU.NEW_MAPPER_TAB:
			_on_file_new_mapper_tab()
		FILE_MENU.OPEN:
			_on_file_open("")
		FILE_MENU.OPEN_RECENT:
			_on_file_open_recent()
		FILE_MENU.CLOSE_TAB:
			_on_file_close_tab()
		FILE_MENU.SAVE:
			_on_file_save()
		FILE_MENU.SAVE_AS:
			_on_file_save_as()
		FILE_MENU.EXIT:
			_on_file_exit()

func _on_file_new_query_tab() -> void:
	# TODO: Implement new query tab
	pass

func _on_file_new_graph_tab() -> void:
	GDSQL.WorkbenchManager.open_sql_graph_file_tab.emit("")
	
func _on_file_new_mapper_tab() -> void:
	GDSQL.WorkbenchManager.open_mapper_graph_file_tab.emit("")
	
func _on_file_open(path: String) -> void:
	match path.get_extension().to_lower():
		"gdsqlgraph":
			GDSQL.WorkbenchManager.open_sql_graph_file_tab.emit(path)
		"gdmappergraph":
			GDSQL.WorkbenchManager.open_mapper_graph_file_tab.emit(path)
		_:
			file_not_exist_dialog.dialog_text = tr("Not support this.") + "\n" + path
			file_not_exist_dialog.popup_centered()
			
func _on_file_open_recent() -> void:
	# This is now handled by the recent_files_sub_menu submenu node.
	# Kept as a no-op for backward compatibility.
	pass

func _on_recent_files_sub_menu_index_pressed(index: int) -> void:
	var text = recent_files_sub_menu.get_item_text(index)
	# 最后一项是 "Clear Recent Files"
	if text in ["Clear Recent Files", tr("Clear Recent Files")]:
		clear_recent_history()
		refresh_recent_files_menu()
		return
		
	var path = text
	if not GDSQL.GDSQLUtils.file_exists(path):
		remove_from_recent_history(path)
		refresh_recent_files_menu()
		file_not_exist_dialog.dialog_text = tr("File does not exist.") + "\n" + path
		file_not_exist_dialog.popup_centered()
		return
		
	# 打开选中的文件
	_on_file_open(path)

func _on_file_close_tab() -> void:
	# TODO: Implement close current tab
	pass

func _on_file_save() -> void:
	# TODO: Implement save current file
	pass

func _on_file_save_as() -> void:
	# TODO: Implement save as dialog
	pass

func _on_file_exit() -> void:
	# TODO: Implement exit/quit
	pass

func _on_edit_menu_id_pressed(id: int) -> void:
	match id:
		EDIT_MENU.UNDO:
			_on_edit_undo()
		EDIT_MENU.REDO:
			_on_edit_redo()
		EDIT_MENU.CUT:
			_on_edit_cut()
		EDIT_MENU.COPY:
			_on_edit_copy()
		EDIT_MENU.PASTE:
			_on_edit_paste()
		EDIT_MENU.DELETE:
			_on_edit_delete()
		EDIT_MENU.SELECT_ALL:
			_on_edit_select_all()
		EDIT_MENU.AUTO_COMPLETE:
			_on_edit_auto_complete()
		EDIT_MENU.FORMAT:
			_on_edit_format()
		EDIT_MENU.SETTINGS:
			_on_edit_settings()

func _on_edit_undo() -> void:
	# TODO: Implement undo
	pass

func _on_edit_redo() -> void:
	# TODO: Implement redo
	pass

func _on_edit_cut() -> void:
	# TODO: Implement cut
	pass

func _on_edit_copy() -> void:
	# TODO: Implement copy
	pass

func _on_edit_paste() -> void:
	# TODO: Implement paste
	pass

func _on_edit_delete() -> void:
	# TODO: Implement delete
	pass

func _on_edit_select_all() -> void:
	# TODO: Implement select all
	pass

func _on_edit_auto_complete() -> void:
	# TODO: Implement auto complete
	pass

func _on_edit_format() -> void:
	# TODO: Implement format code
	pass

func _on_edit_settings() -> void:
	GDSQL.WorkbenchManager.open_settings_tab.emit()

func _on_search_menu_id_pressed(id: int) -> void:
	match id:
		SEARCH_MENU.FIND:
			_on_search_find()
		SEARCH_MENU.FIND_NEXT:
			_on_search_find_next()
		SEARCH_MENU.FIND_PREVIOUS:
			_on_search_find_previous()
		SEARCH_MENU.REPLACE:
			_on_search_replace()
		SEARCH_MENU.FIND_IN_FILES:
			_on_search_find_in_files()
		SEARCH_MENU.REPLACE_IN_FILES:
			_on_search_replace_in_files()

func _on_search_find() -> void:
	# TODO: Implement find
	pass

func _on_search_find_next() -> void:
	# TODO: Implement find next
	pass

func _on_search_find_previous() -> void:
	# TODO: Implement find previous
	pass

func _on_search_replace() -> void:
	# TODO: Implement replace
	pass

func _on_search_find_in_files() -> void:
	# TODO: Implement find in files
	pass

func _on_search_replace_in_files() -> void:
	# TODO: Implement replace in files
	pass

func _on_view_menu_id_pressed(id: int) -> void:
	match id:
		VIEW_MENU.WELCOME:
			_on_view_welcome()
		VIEW_MENU.PANELS:
			_on_view_panels()
		VIEW_MENU.SELECT_NEXT_TAB:
			_on_view_select_next_tab()
		VIEW_MENU.SELECT_PREVIOUS_TAB:
			_on_view_select_previous_tab()

func _on_view_welcome() -> void:
	tab_container.current_tab = tab_container.WELCOME_PAGE_TAB_INDEX

func _on_view_panels() -> void:
	# TODO: Implement panels visibility toggle
	pass

func _on_view_select_next_tab() -> void:
	var count = tab_container.get_tab_count()
	if count <= 1:
		return
	var next_tab = (tab_container.current_tab + 1) % count
	if next_tab == tab_container.get_tab_count() - 1:
		next_tab = (next_tab + 1) % count
	tab_container.current_tab = next_tab

func _on_view_select_previous_tab() -> void:
	var count = tab_container.get_tab_count()
	if count <= 1:
		return
	var prev_tab = (tab_container.current_tab - 1 + count) % count
	if prev_tab == tab_container.get_tab_count() - 1:
		prev_tab = (prev_tab - 1 + count) % count
	tab_container.current_tab = prev_tab

func _on_query_menu_id_pressed(id: int) -> void:
	match id:
		QUERY_MENU.EXECUTE_ALL_OR_SELECTION:
			_on_query_execute_all_or_selection()
		QUERY_MENU.EXECUTE_CURRENT_STATEMENT:
			_on_query_execute_current_statement()
		QUERY_MENU.STOP:
			_on_query_stop()
		QUERY_MENU.STOP_EXECUTION_ON_ERRORS:
			_on_query_stop_execution_on_errors()
		QUERY_MENU.LIMIT_ROWS:
			_on_query_limit_rows()
		QUERY_MENU.AUTO_COMMIT_TRANSACTIONS:
			_on_query_auto_commit_transactions()
		QUERY_MENU.COMMIT_TRANSACTION:
			_on_query_commit_transaction()
		QUERY_MENU.ROLLBACK_TRANSACTION:
			_on_query_rollback_transaction()
		QUERY_MENU.COMMIT_RESULT_EDITS:
			_on_query_commit_result_edits()
		QUERY_MENU.DISCARD_RESULT_EDITS:
			_on_query_discard_result_edits()
		QUERY_MENU.EXPORT_RESULTS:
			_on_query_export_results()

func _on_query_execute_all_or_selection() -> void:
	# TODO: Implement execute all or selection
	pass

func _on_query_execute_current_statement() -> void:
	# TODO: Implement execute current statement
	pass

func _on_query_stop() -> void:
	# TODO: Implement stop execution
	pass

func _on_query_stop_execution_on_errors() -> void:
	# TODO: Implement stop execution on errors toggle
	pass

func _on_query_limit_rows() -> void:
	# TODO: Implement limit rows dialog
	pass

func _on_query_auto_commit_transactions() -> void:
	# TODO: Implement auto-commit transactions toggle
	pass

func _on_query_commit_transaction() -> void:
	# TODO: Implement commit transaction
	pass

func _on_query_rollback_transaction() -> void:
	# TODO: Implement rollback transaction
	pass

func _on_query_commit_result_edits() -> void:
	# TODO: Implement commit result edits
	pass

func _on_query_discard_result_edits() -> void:
	# TODO: Implement discard result edits
	pass

func _on_query_export_results() -> void:
	# TODO: Implement export results
	pass

func _on_database_menu_id_pressed(id: int) -> void:
	match id:
		DATABASE_MENU.SCHEMA_TRANSFER_WIZARD:
			_on_database_schema_transfer_wizard()
		DATABASE_MENU.SEARCH_TABLE_DATA:
			_on_database_search_table_data()

func _on_database_schema_transfer_wizard() -> void:
	# TODO: Implement schema transfer wizard
	pass

func _on_database_search_table_data() -> void:
	# TODO: Implement search table data
	pass

func _on_tools_menu_id_pressed(id: int) -> void:
	match id:
		TOOLS_MENU.XML_EDITOR:
			_on_tools_xml_editor()

func _on_tools_xml_editor() -> void:
	if xml_editor_window:
		xml_editor_window.open_file("")

func _on_help_menu_id_pressed(id: int) -> void:
	match id:
		HELP_MENU.SEARCH_HELP:
			_on_help_search_help()
		HELP_MENU.ONLINE_DOCUMENTATION:
			_on_help_online_documentation()
		HELP_MENU.FORUM:
			_on_help_forum()
		HELP_MENU.COMMUNITY:
			_on_help_community()
		HELP_MENU.COPY_SYSTEM_INFO:
			_on_help_copy_system_info()
		HELP_MENU.REPORT_A_BUG:
			_on_help_report_a_bug()
		HELP_MENU.SUGGEST_A_FEATURE:
			_on_help_suggest_a_feature()
		HELP_MENU.SEND_DOCS_FEEDBACK:
			_on_help_send_docs_feedback()
		HELP_MENU.ABOUT_GDSQL:
			_on_help_about_gdsql()
		HELP_MENU.SUPPORT_GDSQL_DEVELOPMENT:
			_on_help_support_gdsql_development()

func _on_help_search_help() -> void:
	# TODO: Implement search help
	pass

func _on_help_online_documentation() -> void:
	OS.shell_open("https://github.com/jinyangcruise/GDSQL/wiki")

func _on_help_forum() -> void:
	OS.shell_open("https://github.com/jinyangcruise/GDSQL/discussions")

func _on_help_community() -> void:
	# TODO: Implement community link
	pass

func _on_help_copy_system_info() -> void:
	# TODO: Implement copy system info
	pass

func _on_help_report_a_bug() -> void:
	OS.shell_open("https://github.com/jinyangcruise/GDSQL/issues/new?template=bug_report.md")

func _on_help_suggest_a_feature() -> void:
	OS.shell_open("https://github.com/jinyangcruise/GDSQL/issues/new?template=feature_request.md")

func _on_help_send_docs_feedback() -> void:
	# TODO: Implement send docs feedback
	pass

func _on_help_about_gdsql() -> void:
	# TODO: Implement about GDSQL dialog
	pass

func _on_help_support_gdsql_development() -> void:
	# TODO: Implement support GDSQL development
	pass
