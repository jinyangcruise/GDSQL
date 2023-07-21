@tool
extends Tree

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

func _ready():
	refresh()
	
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
#						add_table(db, file_name.substr(0, file_name.length() - 5), file_name)
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
	
func add_table(db: TreeItem, table_name: String, tooltip: String = "") -> TreeItem:
	var table_item = create_item(db.get_child(0))
	table_item.set_text(0, table_name)
	table_item.set_icon(0, preload("res://addons/gdsql/img/table.png"))
	table_item.set_icon_max_width(0, 20)
	table_item.add_button(0, preload("res://addons/gdsql/img/quick_search.png"), 0, false, "select * from %s limit 0, 1000" % table_name)
	table_item.set_tooltip_text(0, tooltip)
	return table_item


func _on_button_clicked(item: TreeItem, column: int, id: int, mouse_button_index: int) -> void:
	if column == 0 and id == 0:
		printt(item.get_button_tooltip_text(column, id))


func refresh() -> void:
	clear()
	await get_tree().create_timer(0.1).timeout
	root = create_item()
	for data in databases:
		var db := add_database("数据库：%s" % data["name"])
		db.set_tooltip_text(0, data["path"])
		var table_files = _get_gsql_file(data["path"])
		for file_name in table_files:
			add_table(db, file_name.replace(".gsql", "").replace(".cfg", ""), file_name)
