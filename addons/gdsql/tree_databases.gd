@tool
extends Tree

var mgr: GDSQLWorkbenchManagerClass = Engine.get_singleton("GDSQLWorkbenchManager")

signal new_schema
signal alter_schema(db_name, path, save)
signal new_table(db_name, db_path)
signal add_db_to_config_success(id: String)
signal modify_db_to_config_success(id: String)
signal add_table_to_config_success(id: String)
signal send_to_editor(content: String)
signal send_to_editor_and_execute(title: String, content: String)

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

@onready var popup_menu_copy_to_of_table: PopupMenu = $PopupMenuTableItem/PopupMenuCopyTo
@onready var popup_menu_send_to_of_table: PopupMenu = $PopupMenuTableItem/PopupMenuSendTo

@onready var popup_menu_copy_to_of_column: PopupMenu = $PopupMenuColumn/PopupMenuCopyTo
@onready var popup_menu_send_to_of_column: PopupMenu = $PopupMenuColumn/PopupMenuSendTo

@onready var popup_menu_create_table_like_tables: PopupMenu = $PopupMenuTables/PopupMenuCreateTableLike
@onready var popup_menu_create_table_like_table_item: PopupMenu = $PopupMenuTableItem/PopupMenuCreateTableLike


var root: TreeItem

var databases: Dictionary

var database_items: Array[TreeItem] = []
var _default_database_path: String = ""
var _config_file: ConfigFile
var _tmp_config: ConfigFile # 只在内存里，非持久化。重启godot或插件会丢失

static var data_types = [
	"TYPE_NIL:0",
	"TYPE_BOOL:1",
	"TYPE_INT:2",
	"TYPE_FLOAT:3",
	"TYPE_STRING:4",
	"TYPE_VECTOR2:5",
	"TYPE_VECTOR2I:6",
	"TYPE_RECT2:7",
	"TYPE_RECT2I:8",
	"TYPE_VECTOR3:9",
	"TYPE_VECTOR3I:10",
	"TYPE_TRANSFORM2D:11",
	"TYPE_VECTOR4:12",
	"TYPE_VECTOR4I:13",
	"TYPE_PLANE:14",
	"TYPE_QUATERNION:15",
	"TYPE_AABB:16",
	"TYPE_BASIS:17",
	"TYPE_TRANSFORM3D:18",
	"TYPE_PROJECTION:19",
	"TYPE_COLOR:20",
	"TYPE_STRING_NAME:21",
	"TYPE_NODE_PATH:22",
	"TYPE_RID:23",
	"TYPE_OBJECT:24",
	"TYPE_CALLABLE:25",
	"TYPE_SIGNAL:26",
	"TYPE_DICTIONARY:27",
	"TYPE_ARRAY:28",
	"TYPE_PACKED_BYTE_ARRAY:29",
	"TYPE_PACKED_INT32_ARRAY:30",
	"TYPE_PACKED_INT64_ARRAY:31",
	"TYPE_PACKED_FLOAT32_ARRAY:32",
	"TYPE_PACKED_FLOAT64_ARRAY:33",
	"TYPE_PACKED_STRING_ARRAY:34",
	"TYPE_PACKED_VECTOR2_ARRAY:35",
	"TYPE_PACKED_VECTOR3_ARRAY:36",
	"TYPE_PACKED_COLOR_ARRAY:37",
	"TYPE_MAX:38",
]

func _clear():
	clear()
	database_items.clear()
	popup_menu_create_table_like_tables.clear()
	popup_menu_create_table_like_table_item.clear()
		
func load_config():
	_config_file = ConfigFile.new()
	_config_file.load("res://addons/gdsql/config/config.cfg")
	_tmp_config = ConfigFile.new()
	
func refresh_databases():
	_config_file.clear()
	_config_file.load("res://addons/gdsql/config/config.cfg")
	databases = {}
	for conf in [_config_file, _tmp_config] as Array[ConfigFile]:
		for db_name in conf.get_sections():
			databases[conf.get_value(db_name, "name")] = {
				"name": conf.get_value(db_name, "name"),
				"path": conf.get_value(db_name, "path"),
				"table_items": {},
				"persistent": conf == _config_file, # 是否是持久化的
			}
		
func add_db_to_config(db_name: String, path: String, save: bool, id: String):
	for conf in [_config_file, _tmp_config] as Array[ConfigFile]:
		for a_db_name in conf.get_sections():
			if a_db_name.to_lower() == db_name.to_lower() or conf.get_value(a_db_name, "path") == path:
				var content = "failed! database name `%s` already exist!" % db_name if a_db_name == db_name \
					else "failed! database path `%s`(%s) already exist!" % [path, a_db_name]
				show_error_msg_dialog(content)
				return
		
	var conf: ConfigFile = _config_file if save else _tmp_config
	conf.set_value(db_name, "name", db_name)
	conf.set_value(db_name, "path", path)
	if save:
		conf.save("res://addons/gdsql/config/config.cfg")
		
	add_db_to_config_success.emit(id)
	
	refresh()
	
	# TODO 日志
func add_table_to_config(db_name: String, db_path: String, table_name: String, column_infos: Array, id: String):
	if !_config_file.has_section(db_name):
		show_error_msg_dialog("failed! database not exists!" % db_name)
		return
		
	if _config_file.get_value(db_name, "path") != db_path:
		show_error_msg_dialog("failed! database path might have changed!")
		return
		
	var table_confs = _config_file.get_value(db_name, "tables", {}) as Dictionary
	if table_confs.has(table_name):
		show_error_msg_dialog("failed! table already exist!")
		return
		
	table_confs[table_name] = column_infos
	_config_file.set_value(db_name, "tables", table_confs)
	_config_file.save("res://addons/gdsql/config/config.cfg")
	
	var file = FileAccess.open(db_path + table_name + ".gsql", FileAccess.WRITE)
	file.store_string("")
	
	add_table_to_config_success.emit(id)
	
	refresh()
	
func modify_db_to_config(old_db_name: String, new_db_name: String, path: String, save: bool, id: String):
	var conf: ConfigFile = _config_file if save else _tmp_config
	var old_data = {}
	
	for key in _config_file.get_section_keys(old_db_name):
		old_data[key] = _config_file.get_value(old_db_name, key)
		
	old_data["name"] = new_db_name
	old_data["path"] = path
	
	conf.erase_section(old_db_name)
	
	for key in old_data:
		conf.set_value(new_db_name, key, old_data[key])
	
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
	popup_menu_table_item.set_item_submenu(3, "PopupMenuCopyTo")
	popup_menu_table_item.set_item_submenu(7, "PopupMenuSendTo")
	popup_menu_table_item.set_item_submenu(10, "PopupMenuCreateTableLike")
	popup_menu_column.set_item_submenu(2, "PopupMenuCopyTo")
	popup_menu_column.set_item_submenu(3, "PopupMenuSendTo")
	refresh()
	
func refresh() -> void:
	_clear()
	refresh_databases()
	root = create_item()
	var collapsed = false
	for db_name in databases:
		var data = databases[db_name]
		var db := add_database(data["name"], data["path"], data["persistent"])
		db.collapsed = collapsed if _default_database_path.is_empty() else _default_database_path != data["path"]
		database_items.push_back(db)
		collapsed = true # 在没默认数据库的情况下，除了第一个数据库不折叠，其他都折叠
		
		var table_files = _get_gsql_file(data["path"])
		for file_name in table_files:
			var table_item = add_table(db, file_name, file_name)
			data["table_items"][table_item["table_name"]] = table_item
			
	mgr.databases = databases
	
	# create table like 子菜单重新生成
	for db_name in databases:
		var data = databases[db_name]
		if !data["table_items"].is_empty():
			popup_menu_create_table_like_tables.add_separator("SCHEMA：%s" % data["name"])
			popup_menu_create_table_like_table_item.add_separator("SCHEMA：%s" % data["name"])
		for t in data["table_items"]:
			popup_menu_create_table_like_tables.add_item(t)
			popup_menu_create_table_like_table_item.add_item(t)
	
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

func add_database(db_name: String, path: String, persistent: bool) -> TreeItem:
	var database_item = create_item(root)
	database_item.set_text(0, db_name)
	database_item.set_icon(0, preload("res://addons/gdsql/img/icon_db.png"))
	database_item.set_icon_max_width(0, 20)
	database_item.add_button(0, preload("res://addons/gdsql/img/folder.png"), 1, false, "打开目录")
	database_item.set_tooltip_text(0, path)
	database_item.set_meta("db_name", db_name)
	database_item.set_meta("path", path)
	database_item.set_meta("type", "database")
	database_item.set_meta("persistent", persistent)
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
		item.set_meta("db_name", db_name)
		item.set_meta("path", path)
		item.set_meta("persistent", persistent)
		if i > 0:
			item.set_collapsed_recursive(true)
	
	return database_item
	
func add_table(db: TreeItem, file_name: String, tooltip: String = "") -> Dictionary:
	var table_item = create_item(db.get_child(0))
	var table_name = file_name.replace(".gsql", "").replace(".cfg", "")
	table_item.set_text(0, table_name)
	table_item.set_icon(0, preload("res://addons/gdsql/img/table.png"))
	table_item.set_icon_max_width(0, 20)
	table_item.set_tooltip_text(0, tooltip)
	table_item.add_button(0, preload("res://addons/gdsql/img/quick_search.png"), 0, false, 
		"select * from %s.%s;" % [db.get_meta("db_name"), table_name])
	table_item.set_meta("db_name", db.get_meta("db_name"))
	table_item.set_meta("table_name", table_name)
	table_item.set_meta("path", db.get_meta("path") + file_name)
	table_item.set_meta("type", "table")
	table_item.set_meta("persistent", db.get_meta("persistent"))
	table_item.collapsed = true
	
	# TODO 让column可以多选
	# column的子tree
	var table_confs = _config_file.get_value(db.get_meta("db_name"), "tables", {}) as Dictionary
	if table_confs.has(table_name):
		for col in table_confs[table_name]:
			var col_item = create_item(table_item)
			var texts = [col["Column Name"]]
			texts.push_back(DataTypeDef.DATA_TYPE_NAMES[col["Data Type"]].replace("TYPE_", "").capitalize())
			col_item.set_text(0, ": ".join(texts))
			col_item.set_icon(0, preload("res://addons/gdsql/img/dot.png"))
			col_item.set_meta("db_name", db.get_meta("db_name"))
			col_item.set_meta("table_name", table_name)
			col_item.set_meta("column_name", col["Column Name"])
			col_item.set_meta("type", "column")
			var properties = ["AI", "NN", "UQ", "PK"]
			var tooltips = ["Auto Increment", "Not NULL", "Uniq", "Primary Key"]
			for i in properties.size():
				if col[properties[i]]:
					col_item.add_button(0, load("res://addons/gdsql/img/word_%s.png" % (properties[i] as String).to_lower()), 2, true, tooltips[i])
			
	
	var info = {
		"table_name": table_name,
		"file_name": file_name,
		"path": table_item.get_meta("path"),
		"columns": table_confs.get(table_name, [])
	}
	return info


func _on_button_clicked(item: TreeItem, column: int, id: int, _mouse_button_index: int) -> void:
	if column == 0:
		match id:
			0:
				send_to_editor_and_execute.emit(item.get_meta("table_name"), item.get_button_tooltip_text(column, id))
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
		if item and item.has_meta("type"):
			var popup_menu: PopupMenu
			match item.get_meta("type"):
				"database":
					popup_menu = popup_menu_database
				"Tables":
					popup_menu = popup_menu_tables
					popup_menu.set_item_disabled(0, !item.get_meta("persistent")) # Create Table...
					popup_menu.set_item_disabled(1, !item.get_meta("persistent")) # Create Table Like...
				"Views":
					popup_menu = popup_menu_veiws
				"Stored Procedures":
					popup_menu = popup_menu_stored_procedures
				"Functions":
					popup_menu = popup_menu_functions
				"table":
					popup_menu = popup_menu_table_item
					popup_menu.set_item_disabled(9, !item.get_meta("persistent")) # Create Table...
					popup_menu.set_item_disabled(10, !item.get_meta("persistent")) # Create Table Like...
					popup_menu.set_item_disabled(11, !item.get_meta("persistent")) # Alter Table...
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
				send_to_editor_and_execute.emit(item.get_meta("table_name"), "select * from %s.%s;" \
					% [item.get_meta("db_name"), item.get_meta("table_name")])
		"Create Table...":
			var item := get_selected()
			if item:
				new_table.emit(item.get_meta("db_name"), item.get_meta("path"))
		"Create Table Like...":
			pass
			
			
## Tables目录的create table like子目录的菜单
func _on_popup_menu_create_table_like_tables_index_pressed(index: int) -> void:
	printt("aaa", popup_menu_create_table_like_tables.get_item_text(index))

## Table Item的create table like子目录的菜单
func _on_popup_menu_create_table_like_table_item_index_pressed(index: int) -> void:
	printt("aaa", popup_menu_create_table_like_table_item.get_item_text(index))
	
## 数据库目录的右键菜单
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
				dialog.dialog_text = "Are you sure to drop this database `%s`? This will NOT delete the folder from your operation system." \
					% get_selected().get_meta("db_name")
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
			new_schema.emit()
		"Refresh All":
			refresh()

## 数据库”复制到“子菜单
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

## 数据库”发送到“子菜单
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

## Tables目录右键菜单
func _on_popup_menu_tables_index_pressed(index: int) -> void:
	match popup_menu_tables.get_item_text(index):
		"Create Table...":
			var item := get_selected()
			if item:
				new_table.emit(item.get_meta("db_name"), item.get_meta("path"))
		"Create Table Like...":
			pass
		"Refresh All":
			refresh()
			
func show_error_msg_dialog(content: String):
	var dialog := AcceptDialog.new()
	dialog.dialog_text = content
	add_child(dialog)
	dialog.popup_centered()
	dialog.close_requested.connect(func():
		dialog.queue_free()
	)
