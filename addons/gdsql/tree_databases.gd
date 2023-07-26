@tool
extends Tree

signal new_schema
signal alter_schema(db_name, path, save)
signal new_sql_command(cmd: String)
signal add_db_to_config_success(id: String)
signal modify_db_to_config_success(id: String)
signal send_to_editor(content: String)

@onready var popup_menu_database: PopupMenu = $PopupMenuDatabase
@onready var popup_menu_table_item: PopupMenu = $PopupMenuTableItem
@onready var popup_menu_tables: PopupMenu = $PopupMenuTables
@onready var popup_menu_veiws: PopupMenu = $PopupMenuVeiws
@onready var popup_menu_stored_procedures: PopupMenu = $PopupMenuStoredProcedures
@onready var popup_menu_functions: PopupMenu = $PopupMenuFunctions
@onready var popup_menu_empty: PopupMenu = $PopupMenuEmpty

@onready var popup_menu_copy_to: PopupMenu = $PopupMenuDatabase/PopupMenuCopyTo
@onready var popup_menu_send_to: PopupMenu = $PopupMenuDatabase/PopupMenuSendTo

@onready var popup_menu_create_table_like_tables: PopupMenu = $PopupMenuTables/PopupMenuCreateTableLike
@onready var popup_menu_create_table_like_table_item: PopupMenu = $PopupMenuTableItem/PopupMenuCreateTableLike


var root: TreeItem

var databases: Array[Dictionary]

var database_items: Array[TreeItem] = []
var _default_database_path: String = ""
var _config_file: ConfigFile
var _tmp_config: ConfigFile # 只在内存里，非持久化。重启godot或插件会丢失

func _clear():
	clear()
	database_items.clear()
	popup_menu_create_table_like_tables.clear()
	popup_menu_create_table_like_table_item.clear()
	for i in databases:
		i["table_items"].clear()
		
func load_config():
	_config_file = ConfigFile.new()
	_config_file.load("res://addons/gdsql/config/config.cfg")
	_tmp_config = ConfigFile.new()
	
func refresh_databases():
	_config_file.clear()
	_config_file.load("res://addons/gdsql/config/config.cfg")
	databases = []
	for conf in [_config_file, _tmp_config] as Array[ConfigFile]:
		for db_name in conf.get_sections():
			databases.push_back({
				"name": conf.get_value(db_name, "name"),
				"path": conf.get_value(db_name, "path"),
				"table_items": [],
			})
		
func add_db_to_config(db_name: String, path: String, save: bool, id: String):
	for conf in [_config_file, _tmp_config] as Array[ConfigFile]:
		for a_db_name in conf.get_sections():
			if a_db_name.to_lower() == db_name.to_lower() or conf.get_value(a_db_name, "path") == path:
				var dialog := AcceptDialog.new()
				if a_db_name == db_name:
					dialog.dialog_text = "failed! database name `%s` already exist!" % db_name
				else:
					dialog.dialog_text = "failed! database path `%s`(%s) already exist!" % [path, a_db_name]
					
				add_child(dialog)
				dialog.popup_centered()
				dialog.close_requested.connect(func():
					dialog.queue_free()
				)
				return
		
	var conf: ConfigFile = _config_file if save else _tmp_config
	conf.set_value(db_name, "name", db_name)
	conf.set_value(db_name, "path", path)
	if save:
		conf.save("res://addons/gdsql/config/config.cfg")
		
	add_db_to_config_success.emit(id)
	
	refresh()
	
	# TODO 日志
		
func modify_db_to_config(old_db_name: String, new_db_name: String, path: String, save: bool, id: String):
	if _config_file.has_section(old_db_name):
		_config_file.erase_section(old_db_name)
	elif _tmp_config.has_section(old_db_name):
		_tmp_config.erase_section(old_db_name)
			
	var conf: ConfigFile = _config_file if save else _tmp_config
	conf.set_value(new_db_name, "name", new_db_name)
	conf.set_value(new_db_name, "path", path)
	
	if save:
		conf.save("res://addons/gdsql/config/config.cfg")
		
	modify_db_to_config_success.emit(id)
	
	refresh()
	
	# TODO 日志

func _ready():
	load_config()
	popup_menu_database.set_item_submenu(2, "PopupMenuCopyTo")
	popup_menu_database.set_item_submenu(3, "PopupMenuSendTo")
	popup_menu_tables.set_item_submenu(1, "PopupMenuCreateTableLike")
	popup_menu_table_item.set_item_submenu(3, "PopupMenuCreateTableLike")
	refresh()
	
func refresh() -> void:
	_clear()
	refresh_databases()
	await get_tree().create_timer(0.1).timeout
	root = create_item()
	var collapsed = false
	for data in databases:
		var db := add_database(data["name"], data["path"])
		db.collapsed = collapsed if _default_database_path.is_empty() else _default_database_path != data["path"]
		database_items.push_back(db)
		collapsed = true # 在没默认数据库的情况下，除了第一个数据库不折叠，其他都折叠
		var table_files = _get_gsql_file(data["path"])
		for file_name in table_files:
			var table_item = add_table(db, file_name, file_name)
			data["table_items"].push_back(table_item)
			
	# create table like 子菜单重新生成
	for data in databases:
		if !data["table_items"].is_empty():
			popup_menu_create_table_like_tables.add_separator("数据库：%s" % data["name"])
			popup_menu_create_table_like_table_item.add_separator("数据库：%s" % data["name"])
		for t in data["table_items"]:
			popup_menu_create_table_like_tables.add_item((t as TreeItem).get_meta("table_name"))
			popup_menu_create_table_like_table_item.add_item((t as TreeItem).get_meta("table_name"))
	
func _get_gsql_file(path: String) -> Array[String]:
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
				if file_name.ends_with(".gsql") or file_name.ends_with(".cfg"):
					ret.push_back(file_name)
					
			file_name = dir.get_next()
		dir.list_dir_end()
	else:
		push_error("An error occurred when trying to access the path:" + path)
		
	return ret

func add_database(db_name: String, path: String) -> TreeItem:
	var database_item = create_item(root)
	database_item.set_text(0, db_name)
	database_item.set_icon(0, preload("res://addons/gdsql/img/icon_db.png"))
	database_item.set_icon_max_width(0, 20)
	database_item.add_button(0, preload("res://addons/gdsql/img/folder.png"), 1, false, "打开目录")
	database_item.set_tooltip_text(0, path)
	database_item.set_meta("db_name", db_name)
	database_item.set_meta("path", path)
	database_item.set_meta("type", "database")
	if path == _default_database_path:
		database_item.set_custom_bg_color(0, Color.BLUE_VIOLET)
	
	var arr := ["Tables", "Views", "Stored Procedures", "Functions"]
	var tooltips := ["数据表", "视图", "存储过程", "函数"]
	for i in arr.size():
		var item = create_item(database_item)
		item.set_text(0, arr[i])
		item.set_icon(0, preload("res://addons/gdsql/img/windows.png"))
		item.set_icon_max_width(0, 16)
		item.set_tooltip_text(0, tooltips[i])
		item.set_meta("type", arr[i])
		if i > 0:
			item.set_collapsed_recursive(true)
	
	return database_item
	
func add_table(db: TreeItem, file_name: String, tooltip: String = "") -> TreeItem:
	var table_item = create_item(db.get_child(0))
	var table_name = file_name.replace(".gsql", "").replace(".cfg", "")
	table_item.set_text(0, table_name)
	table_item.set_icon(0, preload("res://addons/gdsql/img/table.png"))
	table_item.set_icon_max_width(0, 20)
	table_item.set_tooltip_text(0, tooltip)
	table_item.add_button(0, preload("res://addons/gdsql/img/quick_search.png"), 0, false, "select * from %s limit 0, 1000" % table_name)
	table_item.set_meta("table_name", table_name)
	table_item.set_meta("path", db.get_meta("path") + file_name)
	table_item.set_meta("type", "table")
#	table_item.add_button(0, preload("res://addons/gdsql/img/arrow-up-right-from-square.png"), 1, false, "在文件管理器中显示")
	return table_item


func _on_button_clicked(item: TreeItem, column: int, id: int, _mouse_button_index: int) -> void:
	if column == 0:
		match id:
			0:
				new_sql_command.emit(item.get_button_tooltip_text(column, id))
			1:
				var path = ProjectSettings.globalize_path(item.get_meta("path"))
				OS.shell_show_in_file_manager(path, true)


func _on_item_activated(item: TreeItem = null) -> void:
	if item == null:
		item = get_item_at_position(get_local_mouse_position())
	if item:
		var need_collapsed = true
		var is_db_item = false
		for db_item in database_items:
			if db_item == item:
				is_db_item = true
				_default_database_path = db_item.get_meta("path")
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
		if item:
			item.select(0)
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
					
#			printt(DisplayServer.mouse_get_position(), get_viewport().get_mouse_position(), get_window().get_mouse_position())
			popup_menu.position = DisplayServer.mouse_get_position() # 为什么要用这个方法获取鼠标位置？不知道……在插件中该方法是正确的
			popup_menu.popup()
			
func _on_popup_menu_table_item_index_pressed(index: int) -> void:
	printt(popup_menu_table_item.get_item_text(index))
	match popup_menu_table_item.get_item_text(index):
		"Select Rows - Limit 1000":
			pass
		"Create Table ...":
			pass
		"Create Table Like...":
			pass
			
			
func _on_popup_menu_create_table_like_tables_index_pressed(index: int) -> void:
	printt("aaa", popup_menu_create_table_like_tables.get_item_text(index))

func _on_popup_menu_create_table_like_table_item_index_pressed(index: int) -> void:
	printt("aaa", popup_menu_create_table_like_table_item.get_item_text(index))
	
func _on_popup_menu_database_index_pressed(index: int) -> void:
	match popup_menu_database.get_item_text(index):
		"Set as Default Schema [Double Click]":
			_on_item_activated(get_selected())
		"Create Schema...":
			new_schema.emit()
		"Alter Schema...":
			var item := get_selected()
			if item:
				alter_schema.emit(item.get_meta("db_name"), item.get_meta("path"), _config_file.has_section(item.get_meta("db_name")))
		"Drop Schema...":
			var item := get_selected()
			if item:
				var dialog := ConfirmationDialog.new()
				dialog.dialog_text = "Are you sure to drop this database `%s`? This will not delete the folder from your operation system." % get_selected().get_meta("db_name")
				dialog.confirmed.connect(func():
					var conf: ConfigFile = _config_file if _config_file.has_section(item.get_meta("db_name")) else _tmp_config
					if _default_database_path == conf.get_value(item.get_meta("db_name"), "path"):
						_default_database_path = ""
					conf.erase_section(item.get_meta("db_name"))
					if conf == _config_file:
						conf.save("res://addons/gdsql/config/config.cfg")
					refresh()
				)
				add_child(dialog)
				dialog.popup_centered()
				dialog.close_requested.connect(func():
					dialog.queue_free()
				)
		"Refresh All":
			refresh()
		_:
			push_error("not support this %s" % popup_menu_database.get_item_text(index))


func _on_empty_clicked(_position: Vector2, mouse_button_index: int) -> void:
	# 右键
	if mouse_button_index == 2:
		popup_menu_empty.position = DisplayServer.mouse_get_position() # 为什么要用这个方法获取鼠标位置？不知道……在插件中该方法是正确的
		popup_menu_empty.popup()


func _on_popup_menu_empty_index_pressed(index: int) -> void:
	match popup_menu_empty.get_item_text(index):
		"Create Schema...":
			new_schema.emit()
		"Refresh All":
			refresh()


func _on_popup_menu_copy_to_index_pressed(index: int) -> void:
	match popup_menu_copy_to.get_item_text(index):
		"Name":
			var item := get_selected()
			if item:
				DisplayServer.clipboard_set(item.get_meta("db_name"))
		"Path":
			var item := get_selected()
			if item:
				DisplayServer.clipboard_set(item.get_meta("path"))
		"Create Statement":
			var item := get_selected()
			if item:
				var statement = "CREATE DATABASE `%s` AS `%s`;" % [item.get_meta("path"), item.get_meta("db_name")]
				DisplayServer.clipboard_set(statement)


func _on_popup_menu_send_to_index_pressed(index: int) -> void:
	match popup_menu_send_to.get_item_text(index):
		"Name":
			var item := get_selected()
			if item:
				send_to_editor.emit(item.get_meta("db_name"))
		"Path":
			var item := get_selected()
			if item:
				send_to_editor.emit(item.get_meta("path"))
		"Create Statement":
			var item := get_selected()
			if item:
				var statement = "CREATE DATABASE `%s` AS `%s`;" % [item.get_meta("path"), item.get_meta("db_name")]
				send_to_editor.emit(statement)


func _on_popup_menu_tables_index_pressed(index: int) -> void:
	match popup_menu_table_item.get_item_text(index):
		"Create Table ...":
			pass
		"Create Table Like...":
			pass
		"Refresh All":
			refresh()
