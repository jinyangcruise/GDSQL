@tool
extends Tree

@onready var popup_menu_table_item: PopupMenu = $PopupMenuTableItem


var root: TreeItem

var databases: Array[Dictionary] = [
	{
		"path": "user://",
		"name": "用户",
	},{
		"path": "res://src/config/",
		"name": "配置文件",
	}
]

var database_items: Array[TreeItem] = []

func _ready():
	refresh()
	
func refresh() -> void:
	database_items.clear()
	clear()
	await get_tree().create_timer(0.1).timeout
	root = create_item()
	var collapsed = false
	for data in databases:
		var db := add_database("数据库：%s" % data["name"])
		db.collapsed = collapsed
		db.set_tooltip_text(0, data["path"])
		db.set_metadata(0, data["path"])
		database_items.push_back(db)
		collapsed = true # 除了第一个数据库不折叠，其他都折叠
		var table_files = _get_gsql_file(data["path"])
		for file_name in table_files:
			add_table(db, file_name, file_name)
	
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

func add_database(db_name: String) -> TreeItem:
	var database_item = create_item(root)
	database_item.set_text(0, db_name)
	database_item.set_icon(0, preload("res://addons/gdsql/img/icon_db.png"))
	database_item.set_icon_max_width(0, 20)
	database_item.add_button(0, preload("res://addons/gdsql/img/folder.png"), 1, false, "打开目录")
	
	
	var arr := ["Tables", "Views", "Stored Procedures", "Functions"]
	var tooltips := ["数据表", "视图", "存储过程", "函数"]
	for i in arr.size():
		var item = create_item(database_item)
		item.set_text(0, arr[i])
		item.set_icon(0, preload("res://addons/gdsql/img/windows.png"))
		item.set_icon_max_width(0, 16)
		item.set_tooltip_text(0, tooltips[i])
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
	table_item.set_metadata(0, db.get_metadata(0) + file_name)
	table_item.add_button(0, preload("res://addons/gdsql/img/quick_search.png"), 0, false, "select * from %s limit 0, 1000" % table_name)
#	table_item.add_button(0, preload("res://addons/gdsql/img/arrow-up-right-from-square.png"), 1, false, "在文件管理器中显示")
	return table_item


func _on_button_clicked(item: TreeItem, column: int, id: int, mouse_button_index: int) -> void:
	if column == 0:
		match id:
			0:
				printt(item.get_button_tooltip_text(column, id))
			1:
				var path = ProjectSettings.globalize_path(item.get_metadata(0))
				OS.shell_show_in_file_manager(path, true)


func _on_item_activated() -> void:
	var item := get_item_at_position(get_local_mouse_position())
	if item:
		var need_collapsed = true
		var is_db_item = false
		for db_item in database_items:
			if db_item == item:
				is_db_item = true
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
#			printt(DisplayServer.mouse_get_position(), get_viewport().get_mouse_position(), get_window().get_mouse_position())
			popup_menu_table_item.position = DisplayServer.mouse_get_position() # 为什么要用这个方法获取鼠标位置？不知道……在插件中该方法是正确的
			popup_menu_table_item.popup()
