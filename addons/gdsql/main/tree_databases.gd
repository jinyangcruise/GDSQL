@tool
extends Tree

var mgr: GDSQL.WorkbenchManagerClass:
	get: return GDSQL.WorkbenchManager
	
@onready var popup_menu_database: PopupMenu = $PopupMenuDatabase
@onready var popup_menu_table_item: PopupMenu = $PopupMenuTableItem
@onready var popup_menu_tables: PopupMenu = $PopupMenuTables
@onready var popup_menu_veiws: PopupMenu = $PopupMenuVeiws
@onready var popup_menu_stored_procedures: PopupMenu = $PopupMenuStoredProcedures
@onready var popup_menu_functions: PopupMenu = $PopupMenuFunctions
@onready var popup_menu_empty: PopupMenu = $PopupMenuEmpty
@onready var popup_menu_column: PopupMenu = $PopupMenuColumn

@onready var popup_menu_copy_to: PopupMenu = $PopupMenuDatabase/PopupMenuCopyTo
@onready var popup_menu_send_to: PopupMenu = $PopupMenuDatabase/PopupMenuSendTo
@onready var popup_menu_password: PopupMenu = $PopupMenuDatabase/PopupMenuPassword

@onready var popup_menu_copy_to_of_table: PopupMenu = $PopupMenuTableItem/PopupMenuCopyTo
@onready var popup_menu_send_to_of_table: PopupMenu = $PopupMenuTableItem/PopupMenuSendTo
@onready var popup_menu_password_of_table = $PopupMenuTableItem/PopupMenuPassword

@onready var popup_menu_copy_to_of_column: PopupMenu = $PopupMenuColumn/PopupMenuCopyTo
@onready var popup_menu_send_to_of_column: PopupMenu = $PopupMenuColumn/PopupMenuSendTo

@onready var popup_menu_create_table_like_tables: PopupMenu = $PopupMenuTables/PopupMenuCreateTableLike
@onready var popup_menu_create_table_like_table_item: PopupMenu = $PopupMenuTableItem/PopupMenuCreateTableLike


var root: TreeItem

var database_items: Array[TreeItem] = []
var _default_database_path: String = ""
var _password_correct: Dictionary # 保存输入正确密码的表. {datapath: dek}

var disk_changed: ConfirmationDialog
var disk_changed_list: Tree

enum ITEM_BUTTON_INDEX {
	QUICK_SEARCH = 0,
	FOLDER = 1,
	COLUMN_PROPERTY = 2,
	ENCRYPT = 3,
}

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_VISIBILITY_CHANGED:
		if not is_visible_in_tree() or not disk_changed_list:
			return
		# 提示用户配置被外部工具修改了
		disk_changed_list.clear()
		disk_changed_list.columns = 2
		var r = disk_changed_list.create_item()
		disk_changed_list.hide_root = true
		for path: String in GDSQL.ConfManager._conf_modified_time:
			if not GDSQL.GDSQLUtils.file_exists(path):
				var ti = disk_changed_list.create_item(r)
				ti.set_meta("path", path)
				ti.set_icon(0, get_theme_icon("FileDead", "EditorIcons"))
				ti.set_text(0, path.get_file())
				ti.set_text(1, GDSQL.GDSQLUtils.localize_path(path))
				ti.add_button(1, get_theme_icon("Clear", "EditorIcons"), 0, 
					false, tr("Clear cache"))
			elif FileAccess.get_modified_time(path) != GDSQL.ConfManager._conf_modified_time[path]:
				var ti = disk_changed_list.create_item(r)
				ti.set_meta("path", path)
				ti.set_icon(0, get_theme_icon("Edit", "EditorIcons"))
				ti.set_text(0, path.get_file())
				ti.set_text(1, GDSQL.GDSQLUtils.localize_path(path))
				ti.add_button(1, get_theme_icon("Reload", "EditorIcons"), 1, 
					false, tr("Clear cache"))
				ti.add_button(1, get_theme_icon("ExternalLink", "EditorIcons"), 2, 
					false, tr("Open in External Program"))
				ti.add_button(1, get_theme_icon("FileDialog", "EditorIcons"), 3, 
					false, tr("Show in File Manager"))
		if disk_changed_list.get_root().get_child_count() > 0:
			disk_changed.popup_centered_ratio(0.3)
			
func _clear():
	clear()
	database_items.clear()
	popup_menu_create_table_like_tables.clear()
	popup_menu_create_table_like_table_item.clear()
	
func refresh_databases():
	GDSQL.RootConfig.reload()
	mgr.databases = GDSQL.RootConfig.get_databases_info()
	for db_name in mgr.databases:
		for table_name in mgr.databases[db_name]["tables"]:
			if mgr.databases[db_name]["tables"][table_name]["valid_if_not_exist"]:
				GDSQL.ConfManager.mark_valid_if_not_exit(
					GDSQL.RootConfig.get_table_data_path(db_name, table_name))
					
func _get_drag_data(at_position: Vector2) -> Variant:
	var item = get_item_at_position(at_position)
	if not item or item.get_meta("type", "") != "table":
		return
	var texture_rect = TextureRect.new()
	texture_rect.texture = load("res://addons/gdsql/img/document_table.svg")
	texture_rect.size = Vector2(36, 36)
	set_drag_preview(texture_rect)
	return make_drag_data(item)
	
func make_drag_data(item: TreeItem):
	var db_name = item.get_meta("db_name")
	var table_name = item.get_meta("table_name")
	var map = {
		"__table_item": true,
		"db_name": db_name,
		"table_name": table_name,
		"comment": mgr.databases[db_name]["tables"][table_name]["comment"],
		"columns": mgr.databases[db_name]["tables"][table_name]["columns"],
	}
	return map
	
func add_db_to_config(db_name: String, path: String, id: String) -> void:
	var dao = GDSQL.AdminDao.new()
	var err = dao.create_database(db_name, path)
	if err == OK:
		mgr.sys_confirm_add_schema.emit(id)
		refresh()
		
func add_table_to_config(db_name: String, table_name: String, comment: String,
	password: String, valid_if_not_exist: bool, column_infos: Array, id: String = "") -> void:
	var dao = GDSQL.AdminDao.new()
	var err = await dao.create_table(db_name, table_name, column_infos, comment, password, valid_if_not_exist)
	if err == OK:
		if id != "":
			mgr.sys_confirm_add_table.emit(id)
		refresh()
		
func modify_db_to_config(old_db_name: String, new_db_name: String, _path: String, id: String) -> void:
	var dao = GDSQL.AdminDao.new()
	var err = await dao.alter_database(old_db_name, new_db_name)
	if err == OK:
		refresh()
		mgr.sys_confirm_alter_schema.emit(id)
		
func modify_table_to_config(db_name: String, old_table_name: String, new_table_name,
		comments: String, valid_if_not_exist: bool, column_infos: Array, id: String) -> void:
	var dao = GDSQL.AdminDao.new()
	var err = await dao.alter_table(db_name, old_table_name, new_table_name, column_infos, comments, valid_if_not_exist)
	if err == OK:
		refresh()
		mgr.sys_confirm_alter_table.emit(id)
		
func set_password_for_database(db_name: String, password: String) -> void:
	var dao = GDSQL.AdminDao.new()
	var err = dao.set_db_password(db_name, password)
	if err == OK:
		for table_name in mgr.databases[db_name]["tables"]:
			var table_data_path = GDSQL.RootConfig.get_table_data_path(db_name, table_name)
			_password_correct.erase(table_data_path)
		_password_correct.erase(GDSQL.RootConfig.get_database_data_path(db_name))
		refresh()
		
func clear_password_for_database(db_name: String) -> void:
	var dao = GDSQL.AdminDao.new()
	var err = dao.clear_db_password(db_name)
	if err == OK:
		for table_name in mgr.databases[db_name]["tables"]:
			var table_data_path = GDSQL.RootConfig.get_table_data_path(db_name, table_name)
			_password_correct.erase(table_data_path)
		_password_correct.erase(GDSQL.RootConfig.get_database_data_path(db_name))
		refresh()
		
func change_password_for_database(db_name: String, password: String) -> void:
	var dao = GDSQL.AdminDao.new()
	var err = dao.change_db_password(db_name, password)
	if err == OK:
		for table_name in mgr.databases[db_name]["tables"]:
			var table_data_path = GDSQL.RootConfig.get_table_data_path(db_name, table_name)
			_password_correct.erase(table_data_path)
		_password_correct.erase(GDSQL.RootConfig.get_database_data_path(db_name))
		refresh()
		
func set_password(db_name: String, table_name: String, password: String) -> void:
	var dao = GDSQL.AdminDao.new()
	var err = dao.set_table_password(db_name, table_name, password)
	if err == OK:
		var table_data_path = GDSQL.GDSQLUtils.globalize_path(GDSQL.RootConfig.get_table_data_path(db_name, table_name))
		_password_correct.erase(table_data_path)
		refresh()
		
func clear_password(db_name: String, table_name: String) -> void:
	var dao = GDSQL.AdminDao.new()
	var err = dao.clear_table_password(db_name, table_name)
	if err == OK:
		var table_data_path = GDSQL.GDSQLUtils.globalize_path(GDSQL.RootConfig.get_table_data_path(db_name, table_name))
		_password_correct.erase(table_data_path)
		refresh()
		
func change_password(db_name: String, table_name: String, password: String) -> void:
	var dao = GDSQL.AdminDao.new()
	var err = dao.change_table_password(db_name, table_name, password)
	if err == OK:
		var table_data_path = GDSQL.GDSQLUtils.globalize_path(GDSQL.RootConfig.get_table_data_path(db_name, table_name))
		_password_correct.erase(table_data_path)
		refresh()
		
func drop_db_from_config(db_name: String) -> void:
	if mgr.databases.has(db_name) and _default_database_path == GDSQL.RootConfig.get_database_data_path(db_name):
		_default_database_path = ""
	var dao = GDSQL.AdminDao.new()
	var err = await dao.drop_database(db_name)
	if err == OK:
		refresh()
		
func drop_table_from_config(db_name: String, table_name: String) -> void:
	var dao = GDSQL.AdminDao.new()
	var err = await dao.drop_table(db_name, table_name)
	if err == OK:
		var data_path = GDSQL.GDSQLUtils.globalize_path(GDSQL.RootConfig.get_table_data_path(db_name, table_name))
		_password_correct.erase(data_path)
		refresh()
		mgr.sys_confirm_drop_table.emit(db_name, table_name)
		
func truncate_table_from_config(db_name: String, table_name: String) -> void:
	var dao = GDSQL.AdminDao.new()
	var err = await dao.truncate_table(db_name, table_name)
	if err == OK:
		refresh()
		
func _ready():
	if mgr == null or not mgr.run_in_plugin(self):
		return
		
	set_translation_domain("GDSQL")
	if not mgr.user_confirm_add_schema.is_connected(add_db_to_config):
		mgr.user_confirm_add_schema.connect(add_db_to_config, CONNECT_DEFERRED)
	if not mgr.user_confirm_add_table.is_connected(add_table_to_config):
		mgr.user_confirm_add_table.connect(add_table_to_config, CONNECT_DEFERRED)
	if not mgr.user_confirm_alter_schema.is_connected(modify_db_to_config):
		mgr.user_confirm_alter_schema.connect(modify_db_to_config, CONNECT_DEFERRED)
	if not mgr.user_confirm_alter_table.is_connected(modify_table_to_config):
		mgr.user_confirm_alter_table.connect(modify_table_to_config, CONNECT_DEFERRED)
	if not mgr.request_user_enter_password.is_connected(deal_password_before_table_cmd_2):
		mgr.request_user_enter_password.connect(deal_password_before_table_cmd_2, CONNECT_DEFERRED)
	if not mgr.need_user_enter_password.is_connected(need_password):
		mgr.need_user_enter_password.connect(need_password) # 不能用CONNECT_DEFERRED
	if not mgr.request_drop_table.is_connected(drop_table_from_config):
		mgr.request_drop_table.connect(drop_table_from_config, CONNECT_DEFERRED)
	if not mgr.request_create_table.is_connected(add_table_to_config):
		mgr.request_create_table.connect(add_table_to_config, CONNECT_DEFERRED)
		
	popup_menu_database.set_item_submenu_node(2, popup_menu_copy_to)
	popup_menu_database.set_item_submenu_node(3, popup_menu_send_to)
	popup_menu_database.set_item_submenu_node(8, popup_menu_password)
	popup_menu_tables.set_item_submenu_node(1, popup_menu_create_table_like_tables)
	popup_menu_table_item.set_item_submenu_node(3, popup_menu_copy_to_of_table)
	popup_menu_table_item.set_item_submenu_node(7, popup_menu_send_to_of_table)
	popup_menu_table_item.set_item_submenu_node(10, popup_menu_create_table_like_table_item)
	popup_menu_table_item.set_item_submenu_node(12, popup_menu_password_of_table)
	popup_menu_column.set_item_submenu_node(2, popup_menu_copy_to_of_column)
	popup_menu_column.set_item_submenu_node(3, popup_menu_send_to_of_column)
	refresh()
	
	# 配置变化检测
	disk_changed = ConfirmationDialog.new()
	var vbc = VBoxContainer.new()
	disk_changed.add_child(vbc)
	
	var dl = Label.new()
	dl.text = tr("The following files are newer on disk.\nWhat action should be taken?")
	vbc.add_child(dl)
	
	disk_changed_list = Tree.new()
	vbc.add_child(disk_changed_list)
	disk_changed_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	disk_changed_list.button_clicked.connect(_on_disk_changed_list_button_clicked)
	disk_changed.confirmed.connect(_reload_modified_scenes)
	disk_changed.ok_button_text = tr("Reload")
	add_child(disk_changed)
	
func _on_disk_changed_list_button_clicked(item: TreeItem, _column: int, id: int, _mouse_button_index: int):
	match id:
		0, 1:
			GDSQL.ConfManager.remove_conf(item.get_meta("path"))
			_password_correct.erase(item.get_meta("path"))
			refresh()
		2:
			var path = GDSQL.GDSQLUtils.globalize_path(item.get_meta("path"))
			OS.shell_open(path)
		3:
			var path = GDSQL.GDSQLUtils.globalize_path(item.get_meta("path"))
			OS.shell_show_in_file_manager(path, true)
			
func _reload_modified_scenes():
	for i in disk_changed_list.get_root().get_child_count():
		var path = disk_changed_list.get_root().get_child(i).get_meta("path")
		GDSQL.ConfManager.remove_conf(path)
		_password_correct.erase(path)
	refresh()
	
func _exit_tree():
	if mgr == null or not mgr.run_in_plugin(self):
		return
		
	_clear()
	if mgr.user_confirm_add_schema.is_connected(add_db_to_config):
		mgr.user_confirm_add_schema.disconnect(add_db_to_config)
	if mgr.user_confirm_add_table.is_connected(add_table_to_config):
		mgr.user_confirm_add_table.disconnect(add_table_to_config)
	if mgr.user_confirm_alter_schema.is_connected(modify_db_to_config):
		mgr.user_confirm_alter_schema.disconnect(modify_db_to_config)
	if mgr.user_confirm_alter_table.is_connected(modify_table_to_config):
		mgr.user_confirm_alter_table.disconnect(modify_table_to_config)
	if mgr.request_user_enter_password.is_connected(deal_password_before_table_cmd_2):
		mgr.request_user_enter_password.disconnect(deal_password_before_table_cmd_2)
	if mgr.need_user_enter_password.is_connected(need_password):
		mgr.need_user_enter_password.disconnect(need_password)
	if mgr.request_drop_table.is_connected(drop_table_from_config):
		mgr.request_drop_table.disconnect(drop_table_from_config)
	if mgr.request_create_table.is_connected(add_table_to_config):
		mgr.request_create_table.disconnect(add_table_to_config)
		
	mgr = null
	
func refresh() -> void:
	_clear()
	refresh_databases()
	root = create_item()
	var collapsed = false
	for db_name in mgr.databases:
		var data = mgr.databases[db_name]
		var db := add_database(db_name, data)
		db.collapsed = collapsed if _default_database_path.is_empty() else _default_database_path != data["data_path"]
		database_items.push_back(db)
		collapsed = true # 在没默认数据库的情况下，除了第一个数据库不折叠，其他都折叠
		
		for table_name in data["tables"]:
			add_table(db, table_name)
			
	# create table like 子菜单重新生成
	var id = 0
	for db_name in mgr.databases:
		var data = mgr.databases[db_name]
		if !data["tables"].is_empty():
			popup_menu_create_table_like_tables.add_separator("SCHEMA：%s" % data.get("display_name", db_name), id)
			popup_menu_create_table_like_table_item.add_separator("SCHEMA：%s" % data.get("display_name", db_name), id)
		for t in data["tables"]:
			var t_display_name = data["tables"][t].get("display_name", t)
			id += 1
			popup_menu_create_table_like_tables.add_item(t_display_name, id)
			var idx_1 = popup_menu_create_table_like_tables.get_item_index(id)
			popup_menu_create_table_like_tables.set_item_metadata(idx_1, {
				"db_name": db_name,
				"table_name": t
			})
			
			popup_menu_create_table_like_table_item.add_item(t_display_name, id)
			var idx_2 = popup_menu_create_table_like_table_item.get_item_index(id)
			popup_menu_create_table_like_table_item.set_item_metadata(idx_2, {
				"db_name": db_name,
				"table_name": t
			})
			
func _get_specific_extension_files(path: String, extension: String) -> Array[String]:
	var ret: Array[String] = []
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			# 子目录
			if dir.current_is_dir():
				# print("Found directory: " + file_name)
				pass # 不支持发现子目录里的数据，用户可自行把子目录创建为新的数据库即可
			# 文件
			else:
				if file_name.get_extension().to_lower() == extension:
					ret.push_back(file_name)
					
			file_name = dir.get_next()
		dir.list_dir_end()
	else:
		# 注意：git不能提交空目录，可能是因为这个导致clone下来的代码没有空目录
		# 这种情况下，请自己手动创建个空目录即可
		var msg = "Can not open the path: %s." % path
		EditorInterface.get_editor_toaster().push_toast(msg, EditorToaster.SEVERITY_WARNING)
		push_warning(msg)
		
	return ret
	
func add_database(db_name: String, data: Dictionary) -> TreeItem:
	var data_path = data["data_path"]
	var database_item = create_item(root)
	database_item.set_auto_translate_mode(0, Node.AUTO_TRANSLATE_MODE_DISABLED)
	database_item.set_text(0, data.get("display_name", db_name))
	database_item.set_icon(0, load("res://addons/gdsql/img/icon_db.svg"))
	database_item.set_icon_max_width(0, 20)
	database_item.set_tooltip_text(0, data_path)
	database_item.set_meta("db_name", db_name)
	database_item.set_meta("display_name", data.get("display_name", db_name))
	database_item.set_meta("data_path", data_path)
	database_item.set_meta("type", "database")
	if data["encrypted"] != "":
		var texture
		var tooltip
		if _password_correct.has(data_path):
			texture = load("res://addons/gdsql/img/unlock.svg")
			tooltip = tr("This database is encrypted, and you've entered the correct password.")
		else:
			texture = load("res://addons/gdsql/img/lock.svg") 
			tooltip = tr("This database is encrypted. Please enter your password to proceed.")
		database_item.add_button(0, texture, ITEM_BUTTON_INDEX.ENCRYPT, false, tooltip)
	database_item.add_button(0, load("res://addons/gdsql/img/folder.svg"), 
		ITEM_BUTTON_INDEX.FOLDER, false, tr("Show in File Manager"))
	if data_path == _default_database_path:
		database_item.set_custom_bg_color(0, Color.BLUE_VIOLET)
		
	var arr := ["Tables", "Views", "Stored Procedures", "Functions"]
	for i in arr.size():
		var item = create_item(database_item)
		item.set_auto_translate_mode(0, Node.AUTO_TRANSLATE_MODE_ALWAYS)
		item.set_text(0, tr(arr[i]))
		item.set_icon(0, load("res://addons/gdsql/img/windows.svg"))
		item.set_icon_max_width(0, 16)
		item.set_meta("type", arr[i])
		item.set_meta("db_name", db_name)
		item.set_meta("data_path", data_path)
		if i > 0:
			item.set_collapsed_recursive(true)
			
	return database_item
	
func add_table(db: TreeItem, table_name: String):
	var table_item = create_item(db.get_child(0)) # child 0 是 Tables。其他是Views、Stored Procedures等等
	var file_name = table_name + GDSQL.RootConfig.DATA_EXTENSION
	var db_name = db.get_meta("db_name")
	var data_path = db.get_meta("data_path").path_join(file_name)
	var table_def = mgr.databases[db_name]["tables"][table_name]
	table_item.set_text(0, table_def.get("display_name", table_name))
	table_item.set_auto_translate_mode(0, Node.AUTO_TRANSLATE_MODE_DISABLED)
	table_item.set_icon(0, load("res://addons/gdsql/img/document_table.svg"))
	table_item.set_icon_max_width(0, 20)
	table_item.set_tooltip_text(0, file_name)
	if mgr.databases[db_name]["tables"][table_name]["encrypted"] != "":
		var texture
		var tooltip
		if GDSQL.ConfManager.has_conf(data_path) and _password_correct.has(data_path):
			texture = load("res://addons/gdsql/img/unlock.svg")
			tooltip = tr("This table is encrypted and you have entered the right password.")
		else:
			texture = load("res://addons/gdsql/img/lock.svg") 
			tooltip = tr("This table's data file is encrypted. Enter password before using it.")
		table_item.add_button(0, texture, ITEM_BUTTON_INDEX.ENCRYPT, false, tooltip)
	table_item.add_button(0, load("res://addons/gdsql/img/table_edit.svg"), 
		ITEM_BUTTON_INDEX.QUICK_SEARCH, false, "select * from %s.%s;" % [db_name, table_name])
	table_item.set_meta("db_name", db_name)
	table_item.set_meta("table_name", table_name)
	table_item.set_meta("display_name", table_def.get("display_name", table_name))
	table_item.set_meta("data_path", data_path)
	table_item.set_meta("type", "table")
	table_item.collapsed = true
	
	# TODO 让column可以多选
	# column的子tree
	var table_columns = mgr.databases[db_name]["tables"][table_name]["columns"]
	for col in table_columns:
		var col_item = create_item(table_item)
		var texts = [col["Column Name"]]
		texts.push_back(type_string(col["Data Type"]))
		col_item.set_auto_translate_mode(0, Node.AUTO_TRANSLATE_MODE_DISABLED)
		col_item.set_text(0, ": ".join(texts))
		col_item.set_tooltip_text(0, "Comment: %s\nDefault(Expression): %s" % \
			[col["Comment"], col["Default(Expression)"]])
		col_item.set_icon(0, load("res://addons/gdsql/img/circle_dot.svg"))
		col_item.set_meta("db_name", db_name)
		col_item.set_meta("table_name", table_name)
		col_item.set_meta("column_name", col["Column Name"])
		col_item.set_meta("type", "column")
		var properties = ["AI", "NN", "UQ", "PK"]
		var tooltips = ["Auto Increment", "Not NULL", "Uniq", "Primary Key"]
		for i in properties.size():
			if col.get(properties[i], false):
				col_item.add_button(0, load("res://addons/gdsql/img/word_%s.svg" \
				% (properties[i] as String).to_lower()), ITEM_BUTTON_INDEX.COLUMN_PROPERTY
				, true, tooltips[i])
		if col.get("Index", false):
			col_item.add_button(0, load("res://addons/gdsql/img/word_in.svg"), 
				ITEM_BUTTON_INDEX.COLUMN_PROPERTY, true, tr("Indexed"))
				
func _on_button_clicked(item: TreeItem, column: int, id: int, _mouse_button_index: int) -> void:
	if column == 0:
		match id:
			# Select Rows
			ITEM_BUTTON_INDEX.QUICK_SEARCH:
				var exe_select = func():
					mgr.send_to_editor_and_execute.emit(item.get_meta("display_name"), {
						"cmd": "select",
						"db_name": GDSQL.RootConfig.get_database_display_name(item.get_meta("db_name")),
						"table_name": item.get_meta("display_name"),
						"fields": "*"
					})
				deal_password_before_table_cmd(item, "", exe_select)
			# Show in File Manager
			ITEM_BUTTON_INDEX.FOLDER:
				var path = GDSQL.GDSQLUtils.globalize_path(item.get_meta("data_path"))
				OS.shell_show_in_file_manager(path, true)
			ITEM_BUTTON_INDEX.COLUMN_PROPERTY:
				pass
			ITEM_BUTTON_INDEX.ENCRYPT:
				var item_is_table: bool = item.get_meta("type") == "table"
				var table_name = item.get_meta("table_name") if item_is_table else ""
				var data_path = item.get_meta("data_path")
				deal_password_before_table_cmd_3(item, item.get_meta("db_name"), table_name, 
					data_path, "", Callable(), Callable(), true)
					
func _on_item_activated(item: TreeItem = null) -> void:
	if item == null:
		item = get_item_at_position(get_local_mouse_position())
	if item:
		var need_collapsed = true
		var is_db_item = false
		for db_item in database_items:
			if db_item == item:
				is_db_item = true
				_default_database_path = db_item.get_meta("data_path")
				if db_item.get_custom_bg_color(0) != Color.BLUE_VIOLET:
					db_item.set_custom_bg_color(0, Color.BLUE_VIOLET)
					need_collapsed = false # 双击数据库，优先改背景颜色，改了背景颜色就不折叠，而且直接展开（保持展开）
					db_item.collapsed = false
					
		if is_db_item:
			for db_item in database_items:
				if db_item != item:
					db_item.clear_custom_bg_color(0)
				
		if need_collapsed:
			item.collapsed = !item.collapsed
			
func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var item := get_item_at_position(get_local_mouse_position())
		if item and item.has_meta("type"):
			var popup_menu: PopupMenu
			match item.get_meta("type"):
				"database":
					popup_menu = popup_menu_database
				"Tables":
					popup_menu = popup_menu_tables
				"Views":
					popup_menu = popup_menu_veiws
				"Stored Procedures":
					popup_menu = popup_menu_stored_procedures
				"Functions":
					popup_menu = popup_menu_functions
				"table":
					popup_menu = popup_menu_table_item
				"column":
					popup_menu = popup_menu_column
					
#			printt(DisplayServer.mouse_get_position(), get_viewport().get_mouse_position(), get_window().get_mouse_position())
			popup_menu.position = DisplayServer.mouse_get_position() # 为什么要用这个方法获取鼠标位置？不知道……在插件中该方法是正确的
			popup_menu.popup()
			
func _on_popup_menu_table_item_index_pressed(index: int) -> void:
	match popup_menu_table_item.get_item_text(index):
		"Select Rows":
			var item := get_selected()
			if item:
				var exe_select = func():
					mgr.send_to_editor_and_execute.emit(item.get_meta("display_name"), {
						"cmd": "select",
						"db_name": GDSQL.RootConfig.get_database_display_name(item.get_meta("db_name")),
						"table_name": item.get_meta("display_name"),
						"fields": "*"
					})
				deal_password_before_table_cmd(item, "", exe_select)
		"Table Inspector":
			var item := get_selected()
			if item:
				mgr.open_table_inspector_tab.emit(item.get_meta("db_name"), item.get_meta("table_name"))
		"Table Data Export Wizard":
			var item := get_selected()
			if item:
				var db_name = item.get_meta("db_name")
				var table_name = item.get_meta("table_name")
				var open_tab = func():
					mgr.open_table_data_export_tab.emit(db_name, table_name)
				deal_password_before_table_cmd(item, "", open_tab)
		"Table Data Import Wizard":
			var item := get_selected()
			if item:
				var db_name = item.get_meta("db_name")
				var table_name = item.get_meta("table_name")
				var open_tab = func():
					mgr.open_table_data_import_tab.emit(db_name, table_name)
				deal_password_before_table_cmd(item, "", open_tab)
		"Create Table...":
			var item := get_selected()
			if item:
				mgr.open_add_table_tab.emit(item.get_meta("db_name"))
		"Alter Table...":
			var item := get_selected()
			if item:
				var db_name = item.get_meta("db_name")
				var table_name = item.get_meta("table_name")
				var open_tab = func():
					mgr.open_alter_table_tab.emit(db_name, table_name)
				deal_password_before_table_cmd(item, "", open_tab)
		"Drop Table...":
			var item := get_selected()
			if item:
				var db_name = item.get_meta("db_name")
				var table_name = item.get_meta("table_name")
				var open_dialog = func():
					mgr.create_confirmation_dialog(
						tr("Are you sure to Drop table `%s`.`%s`? Config file and data file of this table will be moved to trash.") % \
						[db_name, table_name], drop_table_from_config.bind(db_name, table_name))
				deal_password_before_table_cmd(item, "", open_dialog)
		"Truncate Table...":
			var item := get_selected()
			if item:
				var db_name = item.get_meta("db_name")
				var table_name = item.get_meta("table_name")
				var open_dialog = func():
					mgr.create_confirmation_dialog(
						tr("Are you sure to Truncate table `%s`.`%s`?") % \
						[db_name, table_name], truncate_table_from_config.bind(db_name, table_name))
				deal_password_before_table_cmd(item, "", open_dialog)
		"Show in File Manager":
			var item := get_selected()
			if item:
				var path = GDSQL.GDSQLUtils.globalize_path(item.get_meta("data_path"))
				OS.shell_show_in_file_manager(path, true)
		"Open in External Program":
			var item := get_selected()
			if item:
				var path = GDSQL.GDSQLUtils.globalize_path(item.get_meta("data_path"))
				OS.shell_open(path)
		"Generate Mapper...":
			var item := get_selected()
			if item:
				mgr.open_mapper_graph_tab.emit(make_drag_data(item))
		"Refresh All":
			refresh()
			
func need_password(db_name: String, table_name: String, try_password: String, result: Array = []) -> bool:
	table_name = table_name.get_basename()
	for db_item in root.get_children():
		if db_item.get_meta("db_name") == db_name or \
		db_item.get_meta("data_path") == db_name or \
		db_item.get_meta("data_path") == db_name + "/":
			for collection in db_item.get_children():
				if collection.get_meta("type") == "Tables":
					for table_item in collection.get_children():
						if table_item.get_meta("table_name") == table_name or \
						table_item.get_meta("data_path").get_file() == table_name:
							var ret = _need_password(table_item, try_password)
							result.push_back(ret)
							return ret
	# 在树中找不到表（可能是新建表还没刷新），直接检查数据库加密
	if mgr and mgr.databases.has(db_name) and mgr.databases[db_name]["encrypted"] != "":
		var db_path = GDSQL.RootConfig.get_database_data_path(db_name)
		if _password_correct.has(db_path):
			result.push_back(false)
			return false
		result.push_back(true)
		return true
	result.push_back(false)
	return false
	
func _need_password(table_item: TreeItem, try_password: String) -> bool:
	var db_name = table_item.get_meta("db_name")
	var table_name = table_item.get_meta("table_name")
	var table_path = table_item.get_meta("data_path")
	
	var dek_info = ""
	var path = ""
	var is_db_locked = mgr.databases[db_name]["encrypted"] != ""
	if mgr.databases[db_name]["tables"][table_name]["encrypted"] != "":
		if GDSQL.ConfManager.has_conf(table_path) and _password_correct.has(table_path):
			return false
		dek_info = mgr.databases[db_name]["tables"][table_name]["encrypted"]
		path = table_path
	elif is_db_locked:
		var db_path = GDSQL.RootConfig.get_database_data_path(db_name)
		if _password_correct.has(db_path):
			return false
		dek_info = mgr.databases[db_name]["encrypted"]
		path = db_path
	else:
		return false
		
	if try_password != "":
		var recovered_dek = GDSQL.CryptoUtil.decrypt_dek(dek_info, try_password)
		if not recovered_dek:
			return true # Wrong password
		# 在内存中load一次表，后续再通过__CONF_MANAGER获取表就不需要密码了
		if not is_db_locked:
			GDSQL.ConfManager.get_conf(table_path, recovered_dek)
		_password_correct[path] = recovered_dek
		return false
	return true
	
func deal_password_before_table_cmd_2(db_name: String, table_name: String, try_password: String, pass_callback: Callable, fail_callabck: Callable = Callable()):
	if not db_name.contains("/"):
		db_name = GDSQL.RootConfig.validate_name(db_name)
	table_name = GDSQL.RootConfig.validate_name(table_name)
	table_name = table_name.get_basename()
	var find_db = false
	var find_table = false
	var possible = []
	for db_item in root.get_children():
		if db_item.get_meta("db_name") == db_name or \
		db_item.get_meta("data_path") == db_name or \
		db_item.get_meta("data_path") == db_name + "/":
			find_db = true
			possible.clear()
			for collection in db_item.get_children():
				if collection.get_meta("type") == "Tables":
					for table_item in collection.get_children():
						if table_item.get_meta("table_name") == table_name or \
						table_item.get_meta("data_path").get_file() == table_name:
							deal_password_before_table_cmd(table_item, try_password, pass_callback, fail_callabck)
							return
						elif table_item.get_meta("table_name").similarity(table_name) >= 0.60:
							possible.push_back(table_item.get_meta("table_name"))
						elif table_item.get_meta("data_path").get_file().similarity(table_name) >= 0.60:
							possible.push_back(table_item.get_meta("data_path"))
							
		elif db_item.get_meta("db_name").similarity(db_name) >= 0.60:
			possible.push_back(db_item.get_meta("db_name"))
		elif db_item.get_meta("data_path").similarity(db_name) >= 0.60:
			possible.push_back(db_item.get_meta("data_path"))
			
	if fail_callabck and fail_callabck.is_valid():
		fail_callabck.call()
		
	if not find_db:
		if possible.is_empty():
			mgr.create_accept_dialog(tr("Not find database `%s`!") % db_name)
		else:
			mgr.create_accept_dialog(tr("Not find database `%s`! Possible database:\n%s?") % [db_name, "\n,".join(possible)])
	elif not find_table:
		if possible.is_empty():
			mgr.create_accept_dialog(tr("Not find table `%s`!") % table_name)
		else:
			mgr.create_accept_dialog(tr("Not find table `%s`! Possible table:\n%s?") % [table_name, "\n,".join(possible)])
			
func deal_password_before_table_cmd(item: TreeItem, try_password: String, pass_callback: Callable, fail_callback: Callable = Callable()):
	var item_is_table: bool = item.get_meta("type") == "table"
	var db_name = item.get_meta("db_name")
	var data_path = item.get_meta("data_path")
	var table_name = item.get_meta("table_name") if item_is_table else ""
	deal_password_before_table_cmd_3(item, db_name, table_name, data_path, try_password, pass_callback, fail_callback)
	
func _switch_item_lock_status(item: TreeItem, lock: bool = true):
	var index = item.get_button_by_id(0, ITEM_BUTTON_INDEX.ENCRYPT)
	if index < 0:
		return
	var tooltip = ""
	var item_is_table: bool = item.get_meta("type") == "table"
	var db_name = item.get_meta("db_name")
	var table_name = item.get_meta("table_name") if item_is_table else ""
	if item_is_table:
		if lock:
			tooltip = tr("This table: %s.%s is encrypted. Please input password of this table.") % [db_name, table_name]
		else:
			tooltip = tr("This table: %s.%s is encrypted and you have entered the right password.") % [db_name, table_name]
	else:
		if lock:
			tooltip = tr("This database: %s is encrypted. Please input password of this databse.") % db_name
		else:
			tooltip = tr("This database: %s is encrypted and you have entered the right password.") % db_name
	var texture = load("res://addons/gdsql/img/lock.svg") if lock else load("res://addons/gdsql/img/unlock.svg")
	item.set_button(0, index, texture)
	item.set_button_tooltip_text(0, index, tooltip)
	
	if lock:
		if item_is_table:
			_password_correct.erase(GDSQL.RootConfig.get_table_data_path(db_name, table_name))
		else:
			for a_table_name in mgr.databases[db_name]["tables"]:
				var table_data_path = GDSQL.RootConfig.get_table_data_path(db_name, a_table_name)
				GDSQL.ConfManager.remove_conf(table_data_path)
				_password_correct.erase(table_data_path)
			_password_correct.erase(GDSQL.RootConfig.get_database_data_path(db_name))
			
func deal_password_before_table_cmd_3(item: TreeItem, db_name: String, table_name: String, 
data_path: String, try_password: String, pass_callback: Callable, fail_callback: Callable = Callable(),
lock_if_already_passed: bool = false):
	var password_dict_obj = GDSQL.DictionaryObject.new({tr("Password"): ""}, 
		{tr("Password"): {"hint": PROPERTY_HINT_PASSWORD}})
		
	var dek_info = ""
	var msg
	var item_is_table: bool = item.get_meta("type") == "table"
	var is_db_locked = mgr.databases[db_name]["encrypted"] != ""
	if item_is_table and mgr.databases[db_name]["tables"][table_name]["encrypted"] != "":
		if GDSQL.ConfManager.has_conf(data_path) and _password_correct.has(data_path):
			if pass_callback.is_valid():
				pass_callback.call()
			if lock_if_already_passed:
				_switch_item_lock_status(item, true)
			return
		dek_info = mgr.databases[db_name]["tables"][table_name]["encrypted"]
		msg = tr("This table: %s.%s is encrypted. Please input password of this table.") % [db_name, table_name]
	elif is_db_locked:
		var db_path = data_path
		if db_path.ends_with(GDSQL.RootConfig.DATA_EXTENSION):
			db_path = db_path.get_base_dir()
		if _password_correct.has(db_path):
			if pass_callback.is_valid():
				pass_callback.call()
			if lock_if_already_passed:
				_switch_item_lock_status(item.get_parent().get_parent() if item_is_table else item, true)
			return
		dek_info = mgr.databases[db_name]["encrypted"]
		msg = tr("This database: %s is encrypted. Please input password of this databse.") % db_name
	else:
		if pass_callback.is_valid():
			pass_callback.call()
		return
		
	if try_password != "":
		var recovered_dek = GDSQL.CryptoUtil.decrypt_dek(dek_info, try_password)
		if not recovered_dek:
			msg = tr("Your password is incorrect! Please enter again!")
		else:
			# 在内存中load一次表，后续再通过__CONF_MANAGER获取表就不需要密码了
			if data_path.ends_with(GDSQL.RootConfig.DATA_EXTENSION):
				var conf = GDSQL.ConfManager.get_conf(data_path, recovered_dek)
				if conf == null:
					return
					
				if is_db_locked:
					_password_correct[data_path.get_base_dir()] = recovered_dek
				else:
					_password_correct[data_path] = recovered_dek
			else:
				_password_correct[data_path] = recovered_dek
				
			if item_is_table:
				if is_db_locked:
					_switch_item_lock_status(item.get_parent().get_parent(), false)
				else:
					_switch_item_lock_status(item, false)
			else:
				_switch_item_lock_status(item, false)
			if pass_callback.is_valid():
				pass_callback.call()
			return
			
	var arr: Array[Array] = [
		[msg],
		[password_dict_obj],
	]
	var confirmed = func():
		var recovered_dek = GDSQL.CryptoUtil.decrypt_dek(dek_info, password_dict_obj._get(tr("Password")))
		if recovered_dek:
			# 在内存中load一次表，后续再通过__CONF_MANAGER获取表就不需要密码了
			if data_path.ends_with(GDSQL.RootConfig.DATA_EXTENSION):
				var conf = GDSQL.ConfManager.get_conf(data_path, recovered_dek)
				if conf == null:
					return [true, false]
					
				if is_db_locked:
					_password_correct[data_path.get_base_dir()] = recovered_dek
				else:
					_password_correct[data_path] = recovered_dek
			else:
				_password_correct[data_path] = recovered_dek
				
			return [false, true] # false表示让对话框关闭，true表示密码正确
		mgr.create_accept_dialog(tr("Incorrect password!"))
		return [true, false] # true表示让对话框存在，false表示密码错误
		
	var defered = func(clicked_confirm: bool, validation):
		if clicked_confirm:
			if validation is bool and validation == true:
				# 更新锁的图标为打开的样式
				if item_is_table:
					if is_db_locked:
						_switch_item_lock_status(item.get_parent().get_parent(), false)
					else:
						_switch_item_lock_status(item, false)
				else:
					_switch_item_lock_status(item, false)
				# 执行用户传入的函数
				if pass_callback.is_valid():
					pass_callback.call()
				return
		if fail_callback and fail_callback.is_valid():
			fail_callback.call()
			
	mgr.create_custom_dialog(arr, confirmed, Callable(), defered)
	
## Tables目录的create table like子目录的菜单
func _on_popup_menu_create_table_like_tables_index_pressed(index: int) -> void:
	var item = get_selected()
	if item:
		var db_name = item.get_meta("db_name")
		var meta_data = popup_menu_create_table_like_tables.get_item_metadata(index)
		var like_db_name = meta_data["db_name"]
		var like_table_name = meta_data["table_name"]
		deal_password_before_table_cmd_3(item.get_parent(), db_name, "", 
			item.get_meta("data_path"), "",
			mgr.open_add_table_tab.emit.bind(db_name, like_db_name, like_table_name))
			
## Table Item的create table like子目录的菜单
func _on_popup_menu_create_table_like_table_item_index_pressed(index: int) -> void:
	var item = get_selected()
	if item:
		var db_name = item.get_meta("db_name")
		var meta_data = popup_menu_create_table_like_table_item.get_item_metadata(index)
		var like_db_name = meta_data["db_name"]
		var like_table_name = meta_data["table_name"]
		deal_password_before_table_cmd_3(item.get_parent().get_parent(), db_name, "",
			item.get_meta("data_path"), "",
			mgr.open_add_table_tab.emit.bind(db_name, like_db_name, like_table_name))
			
## 数据库目录的右键菜单
func _on_popup_menu_database_index_pressed(index: int) -> void:
	match popup_menu_database.get_item_text(index):
		"Set as Default Schema [Double Click]":
			_on_item_activated(get_selected())
		"Create Schema...":
			mgr.open_add_schema_tab.emit()
		"Alter Schema...":
			var item := get_selected()
			if item:
				deal_password_before_table_cmd(item, "", 
					mgr.open_alter_schema_tab.emit.bind(item.get_meta("db_name"), item.get_meta("data_path")))
		"Drop Schema...":
			var item := get_selected()
			if item:
				var db_name = item.get_meta("db_name")
				var open_dialog = func():
					mgr.create_confirmation_dialog(
						tr("Are you sure you want to drop the database `%s`? For safety purposes, this operation will Not delete the corresponding folder on your operating system. You may delete it manually if needed.")
							% db_name, drop_db_from_config.bind(db_name))
				deal_password_before_table_cmd(item, "", open_dialog)
		"Refresh All":
			refresh()
		_:
			push_error("not support this %s" % popup_menu_database.get_item_text(index))
			
## 在空白位置弹出右键菜单
func _on_empty_clicked(_position: Vector2, mouse_button_index: int) -> void:
	# 右键
	if mouse_button_index == 2:
		popup_menu_empty.position = DisplayServer.mouse_get_position() # 为什么要用这个方法获取鼠标位置？不知道……在插件中该方法是正确的
		popup_menu_empty.popup()
		
## 树的空白位置的右键菜单
func _on_popup_menu_empty_index_pressed(index: int) -> void:
	match popup_menu_empty.get_item_text(index):
		"Create Schema...":
			mgr.open_add_schema_tab.emit()
		"Refresh All":
			refresh()
			
## 数据库“复制到”子菜单
func _on_popup_menu_copy_to_index_pressed(index: int) -> void:
	match popup_menu_copy_to.get_item_text(index):
		"Name":
			var item := get_selected()
			if item:
				DisplayServer.clipboard_set(item.get_meta("display_name"))
		"Config Path":
			var item := get_selected()
			if item:
				DisplayServer.clipboard_set(GDSQL.RootConfig.get_database_config_path(item.get_meta("db_name")))
		"Data Path":
			var item := get_selected()
			if item:
				DisplayServer.clipboard_set(item.get_meta("data_path"))
		"Create Statement":
			var item := get_selected()
			if item:
				var statement = "CREATE DATABASE %s PATH %s;" % [item.get_meta("display_name"), item.get_meta("path")]
				DisplayServer.clipboard_set(statement)
				
## 数据库“发送到”子菜单
func _on_popup_menu_send_to_index_pressed(index: int) -> void:
	match popup_menu_send_to.get_item_text(index):
		"Name":
			var item := get_selected()
			if item:
				mgr.send_to_editor.emit(item.get_meta("display_name"))
		"Path":
			var item := get_selected()
			if item:
				mgr.send_to_editor.emit(item.get_meta("data_path"))
		"Create Statement":
			var item := get_selected()
			if item:
				var statement = "CREATE DATABASE %s PATH %s;" % [item.get_meta("display_name"), item.get_meta("path")]
				mgr.send_to_editor.emit(statement)
				
## Tables目录右键菜单
func _on_popup_menu_tables_index_pressed(index: int) -> void:
	match popup_menu_tables.get_item_text(index):
		"Create Table...":
			var item := get_selected()
			if item:
				mgr.open_add_table_tab.emit(item.get_meta("db_name"))
		"Create Table Like...":
			pass # 子menu实现，所以留空
		"Refresh All":
			refresh()
			
func _on_popup_menu_copy_to_of_table_item_index_pressed(index):
	match popup_menu_copy_to_of_table.get_item_text(index):
		"Name (Short)":
			var item := get_selected()
			if item:
				DisplayServer.clipboard_set(item.get_meta("display_name"))
		"Name (long)":
			var item := get_selected()
			if item:
				var db_name = item.get_meta("db_name")
				var db_display = GDSQL.RootConfig.get_database_display_name(db_name)
				var table_name = item.get_meta("table_name")
				DisplayServer.clipboard_set("`%s`.`%s`" % [db_display, item.get_meta("display_name")])
		"Select All Statement":
			var item := get_selected()
			if item:
				var db_name = item.get_meta("db_name")
				var db_display = GDSQL.RootConfig.get_database_display_name(db_name)
				var table_name = item.get_meta("display_name")
				var table_columns = GDSQL.RootConfig.get_table_columns(db_name, item.get_meta("table_name"))
				var column_names = []
				for i in table_columns:
					column_names.push_back(i["Column Name"])
				var cmd = """
var dao = GDSQL.BaseDao.new()
var ret = dao.use_db("%s")\\
	.set_password("")\\
	.select("%s", true)\\
	.from("%s")\\
	.query()
""" % [db_display, ",".join(column_names), table_name]
				DisplayServer.clipboard_set(cmd)
		"Insert Statement":
			var item := get_selected()
			if item:
				var db_name = item.get_meta("db_name")
				var db_display = GDSQL.RootConfig.get_database_display_name(db_name)
				var table_name = item.get_meta("display_name")
				var cmd = """
var dao = GDSQL.BaseDao.new()
var ret = dao.use_db("%s")\\
	.set_password("")\\
	.insert_into("%s")\\
	.values(<data: Dictionary>)\\
	.query()
""" % [db_display, table_name]
				DisplayServer.clipboard_set(cmd)
		"Update Statement":
			var item := get_selected()
			if item:
				var db_name = item.get_meta("db_name")
				var db_display = GDSQL.RootConfig.get_database_display_name(db_name)
				var table_name = item.get_meta("display_name")
				var cmd = """
var dao = GDSQL.BaseDao.new()
var ret = dao.use_db("%s")\\
	.set_password("")\\
	.update("%s")\\
	.sets(<data: Dictionary>)\\
	.where(<cond: String>)\\
	.query()
""" % [db_display, table_name]
				DisplayServer.clipboard_set(cmd)
		"Delete Statement":
			var item := get_selected()
			if item:
				var db_name = item.get_meta("db_name")
				var db_display = GDSQL.RootConfig.get_database_display_name(db_name)
				var table_name = item.get_meta("display_name")
				var cmd = """
var dao = GDSQL.BaseDao.new()
var ret = dao.use_db("%s")\\
	.set_password("")\\
	.delete_from("%s")\\
	.where(<cond: String>)\\
	.query()
""" % [db_display, table_name]
				DisplayServer.clipboard_set(cmd)
		"Config Path":
			var item := get_selected()
			if item:
				var db_name = item.get_meta("db_name")
				var table_name = item.get_meta("table_name")
				var config_path = GDSQL.RootConfig.get_table_config_path(db_name, table_name)
				DisplayServer.clipboard_set(config_path)
		"Data Path":
			var item := get_selected()
			if item:
				DisplayServer.clipboard_set(item.get_meta("data_path"))
		"Create Statement":
			var item := get_selected()
			if item:
				var statement = "TODO"
				DisplayServer.clipboard_set(statement)
				
func _on_popup_menu_password_index_pressed(index):
	match popup_menu_password_of_table.get_item_text(index):
		"Set Password":
			var item := get_selected()
			if item == null:
				return
				
			var db_name = item.get_meta("db_name")
			var table_name = item.get_meta("table_name")
			
			var password_dict_obj_1 = GDSQL.DictionaryObject.new({tr("Password"): ""}, 
				{tr("Password"): {"hint": PROPERTY_HINT_PASSWORD}})
			var password_dict_obj_2 = GDSQL.DictionaryObject.new({tr("Password"): ""}, 
				{tr("Password"): {"hint": PROPERTY_HINT_PASSWORD, "hint_string": tr("Enter same password agian.")}})
				
			var arr: Array[Array] = [
				[tr("Set password for this table:")],
				[password_dict_obj_1],
				[password_dict_obj_2],
			]
			var confirmed = func():
				if password_dict_obj_1._get(tr("Password")) != password_dict_obj_2._get(tr("Password")):
					mgr.create_accept_dialog(tr("Passwords are different!"))
					return [true, false]
				return [false, true]
				
			var defered = func(clicked_confirm: bool, validation):
				if clicked_confirm:
					if validation is bool and validation == true:
						# 安全起见还是通过检查是否需要用户输入密码再执行后续方法
						deal_password_before_table_cmd(item, "", 
							set_password.bind(db_name, table_name, password_dict_obj_1._get(tr("Password"))))
							
			mgr.create_custom_dialog(arr, confirmed, Callable(), defered)
			
		"Clear Password":
			var item := get_selected()
			if item == null:
				return
				
			var db_name = item.get_meta("db_name")
			var table_name = item.get_meta("table_name")
			
			var password_dict_obj = GDSQL.DictionaryObject.new({tr("Password"): ""}, 
				{tr("Password"): {"hint": PROPERTY_HINT_PASSWORD}})
			var arr: Array[Array] = [
				[tr("Are you sure to clear password for this table?")],
				[tr("Please enter password to apply.")],
				[password_dict_obj],
			]
			var confirmed = func():
				var dek_info = mgr.databases[db_name]["tables"][table_name]["encrypted"]
				var recovered_dek = GDSQL.CryptoUtil.decrypt_dek(dek_info, password_dict_obj._get(tr("Password")))
				if not recovered_dek:
					mgr.create_accept_dialog(tr("Incorrect password!"))
					return [true, false]
				return [false, true]
				
			var defered = func(clicked_confirm: bool, validation):
				if clicked_confirm:
					if validation is bool and validation == true:
						clear_password(db_name, table_name)
						
			var callback = func():
				mgr.create_custom_dialog(arr, confirmed, Callable(), defered)
				
			deal_password_before_table_cmd(item, "", callback)
			
		"Change Password":
			var item := get_selected()
			if item == null:
				return
				
			var db_name = item.get_meta("db_name")
			var table_name = item.get_meta("table_name")
			
			var password_dict_obj = GDSQL.DictionaryObject.new({tr("oldPassword"): ""}, 
				{tr("oldPassword"): {"hint": PROPERTY_HINT_PASSWORD}})
			var password_dict_obj_1 = GDSQL.DictionaryObject.new({tr("newPassword"): ""}, 
				{tr("newPassword"): {"hint": PROPERTY_HINT_PASSWORD}})
			var password_dict_obj_2 = GDSQL.DictionaryObject.new({tr("newPassword"): ""}, 
				{tr("newPassword"): {"hint": PROPERTY_HINT_PASSWORD, "hint_string": "Enter new password again."}})
			var arr: Array[Array] = [
				[tr("Are you sure to change password for this table?")],
				[password_dict_obj],
				[password_dict_obj_1],
				[password_dict_obj_2],
			]
			var confirmed = func():
				if password_dict_obj_1._get(tr("newPassword")) != password_dict_obj_2._get(tr("newPassword")):
					mgr.create_accept_dialog(tr("The second password entered is not the same as the first one!"))
					return [true, false]
				if password_dict_obj_1._get(tr("newPassword")) == "":
					mgr.create_accept_dialog(tr("New password is empty!"))
					return [true, false]
				var dek_info = mgr.databases[db_name]["tables"][table_name]["encrypted"]
				var recovered_dek = GDSQL.CryptoUtil.decrypt_dek(dek_info, password_dict_obj._get(tr("oldPassword")))
				if not recovered_dek:
					mgr.create_accept_dialog(tr("Incorrect password!"))
					return [true, false]
				return [false, true]
				
			var defered = func(clicked_confirm: bool, validation):
				if clicked_confirm:
					if validation is bool and validation == true:
						change_password(db_name, table_name, password_dict_obj_1._get(tr("newPassword")))
						
			var callback = func():
				mgr.create_custom_dialog(arr, confirmed, Callable(), defered)
				
			deal_password_before_table_cmd(item, "", callback)
			
## 密码修改相关操作
func _on_popup_menu_password_about_to_popup():
	var item := get_selected()
	if item:
		var db_name = item.get_meta("db_name")
		var table_name = item.get_meta("table_name")
		if mgr.databases[db_name]["tables"][table_name]["encrypted"] == "":
			popup_menu_password_of_table.set_item_disabled(0, false)
			popup_menu_password_of_table.set_item_disabled(1, true)
			popup_menu_password_of_table.set_item_disabled(2, true)
		else:
			popup_menu_password_of_table.set_item_disabled(0, true)
			popup_menu_password_of_table.set_item_disabled(1, false)
			popup_menu_password_of_table.set_item_disabled(2, false)
			
func _on_popup_menu_password_database_index_pressed(index: int) -> void:
	match popup_menu_password_of_table.get_item_text(index):
		"Set Password":
			var item := get_selected()
			if item == null:
				return
				
			var db_name = item.get_meta("db_name")
			
			var password_dict_obj_1 = GDSQL.DictionaryObject.new({tr("Password"): ""}, 
				{tr("Password"): {"hint": PROPERTY_HINT_PASSWORD}})
			var password_dict_obj_2 = GDSQL.DictionaryObject.new({tr("Password"): ""}, 
				{tr("Password"): {"hint": PROPERTY_HINT_PASSWORD, "hint_string": tr("Enter same password agian.")}})
				
			var arr: Array[Array] = [
				[tr("Set password for this database:")],
				[password_dict_obj_1],
				[password_dict_obj_2],
			]
			var confirmed = func():
				if password_dict_obj_1._get(tr("Password")) != password_dict_obj_2._get(tr("Password")):
					mgr.create_accept_dialog(tr("Passwords are different!"))
					return [true, false]
				return [false, true]
				
			var defered = func(clicked_confirm: bool, validation):
				if clicked_confirm:
					if validation is bool and validation == true:
						# 安全起见还是通过检查是否需要用户输入密码再执行后续方法
						deal_password_before_table_cmd(item, "", 
							set_password_for_database.bind(db_name, password_dict_obj_1._get(tr("Password"))))
							
			mgr.create_custom_dialog(arr, confirmed, Callable(), defered)
			
		"Clear Password":
			var item := get_selected()
			if item == null:
				return
				
			var db_name = item.get_meta("db_name")
			
			var password_dict_obj = GDSQL.DictionaryObject.new({tr("Password"): ""}, 
				{tr("Password"): {"hint": PROPERTY_HINT_PASSWORD}})
			var arr: Array[Array] = [
				[tr("Are you sure to clear password for this database?")],
				[tr("Please enter password to apply.")],
				[password_dict_obj],
			]
			var confirmed = func():
				var dek_info = mgr.databases[db_name]["encrypted"]
				var recovered_dek = GDSQL.CryptoUtil.decrypt_dek(dek_info, password_dict_obj._get(tr("Password")))
				if not recovered_dek:
					mgr.create_accept_dialog(tr("Incorrect password!"))
					return [true, false]
				return [false, true]
				
			var defered = func(clicked_confirm: bool, validation):
				if clicked_confirm:
					if validation is bool and validation == true:
						clear_password_for_database(db_name)
						
			var callback = func():
				mgr.create_custom_dialog(arr, confirmed, Callable(), defered)
				
			deal_password_before_table_cmd(item, "", callback)
			
		"Change Password":
			var item := get_selected()
			if item == null:
				return
				
			var db_name = item.get_meta("db_name")
			
			var password_dict_obj = GDSQL.DictionaryObject.new({tr("oldPassword"): ""}, 
				{tr("oldPassword"): {"hint": PROPERTY_HINT_PASSWORD}})
			var password_dict_obj_1 = GDSQL.DictionaryObject.new({tr("newPassword"): ""}, 
				{tr("newPassword"): {"hint": PROPERTY_HINT_PASSWORD}})
			var password_dict_obj_2 = GDSQL.DictionaryObject.new({tr("newPassword"): ""}, 
				{tr("newPassword"): {"hint": PROPERTY_HINT_PASSWORD, "hint_string": tr("Enter new password again.")}})
			var arr: Array[Array] = [
				[tr("Are you sure you want to change this database's password?")],
				[password_dict_obj],
				[password_dict_obj_1],
				[password_dict_obj_2],
			]
			var confirmed = func():
				if password_dict_obj_1._get(tr("newPassword")) != password_dict_obj_2._get(tr("newPassword")):
					mgr.create_accept_dialog(tr("The second password entered is not the same as the first one!"))
					return [true, false]
				if password_dict_obj_1._get(tr("newPassword")) == "":
					mgr.create_accept_dialog(tr("New password is empty!"))
					return [true, false]
				var dek_info = mgr.databases[db_name]["encrypted"]
				var recovered_dek = GDSQL.CryptoUtil.decrypt_dek(dek_info, password_dict_obj._get(tr("oldPassword")))
				if not recovered_dek:
					mgr.create_accept_dialog(tr("Incorrect password!"))
					return [true, false]
				return [false, true]
				
			var defered = func(clicked_confirm: bool, validation):
				if clicked_confirm:
					if validation is bool and validation == true:
						change_password_for_database(db_name, password_dict_obj_1._get(tr("newPassword")))
						
			var callback = func():
				mgr.create_custom_dialog(arr, confirmed, Callable(), defered)
				
			deal_password_before_table_cmd(item, "", callback)
			
func _on_popup_menu_password_database_about_to_popup() -> void:
	var item := get_selected()
	if item:
		var db_name = item.get_meta("db_name")
		if mgr.databases[db_name]["encrypted"] == "":
			popup_menu_password.set_item_disabled(0, false)
			popup_menu_password.set_item_disabled(1, true)
			popup_menu_password.set_item_disabled(2, true)
		else:
			popup_menu_password.set_item_disabled(0, true)
			popup_menu_password.set_item_disabled(1, false)
			popup_menu_password.set_item_disabled(2, false)
