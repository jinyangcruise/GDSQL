@tool
extends TabContainer

signal add_new_schema(db_name: String, path: String, save: bool, id: String)
signal alter_old_schema(old_db_name, new_db_name: String, path: String, save: bool, id: String)

@onready var new_tab_button: Control = $"➕"

var _tab_index = 1

func _ready() -> void:
	pass


func _on_tab_clicked(tab: int) -> void:
	# 点击了“新建SQL页面”（加号），增加一个编辑页面，并激活
	if get_child(tab) == new_tab_button:
		var sql_file = preload("res://addons/gdsql/sql_file.tscn").instantiate()
		add_child(sql_file)
		move_child(new_tab_button, get_child_count() - 1)
		current_tab = get_child_count() - 2
		set_tab_title(current_tab, "SQL File %d" % _tab_index)
		_tab_index += 1
		
func add_tab_new_schema() -> void:
	var new_schema = preload("res://addons/gdsql/new_schema.tscn").instantiate()
	new_schema.button_apply_pressed.connect(func(db_name, path, save, id):
		add_new_schema.emit(db_name, path, save, id)
	)
	add_child(new_schema)
	move_child(new_tab_button, get_child_count() - 1)
	current_tab = get_child_count() - 2
	set_tab_title(current_tab, "new_schema")
		
func add_tab_alter_schema(db_name, path, save) -> void:
	var alter_schema = preload("res://addons/gdsql/alter_schema.tscn").instantiate()
	alter_schema.old_db_name = db_name
	alter_schema.db_name = db_name
	alter_schema.path = path
	alter_schema.save = save
	alter_schema.button_apply_pressed.connect(func(a_old_db_name, a_new_db_name, a_path, a_save, id):
		alter_old_schema.emit(a_old_db_name, a_new_db_name, a_path, a_save, id)
	)
	add_child(alter_schema)
	move_child(new_tab_button, get_child_count() - 1)
	current_tab = get_child_count() - 2
	set_tab_title(current_tab, "alter_schema")
	
func _on_tab_button_pressed(tab: int) -> void:
	remove_child(get_tab_control(tab))
	# TODO 有内容的时候要提示保存或者二次确认
	
func close_content_window(content_id: String):
	var child = get_node(content_id)
	if child:
		child.queue_free()

## 切换标签的时候，把激活的标签上加一个关闭按钮，没激活的标签取消关闭按钮防止误触
func _on_tab_changed(tab: int) -> void:
	if get_tab_control(tab) != new_tab_button:
		set_tab_button_icon(tab, preload("res://addons/gdsql/img/xmark.png"))
		
		for i in get_tab_count():
			if i != tab:
				set_tab_button_icon(i, null)
				
func receive_content(content: String):
	# 当前打开的页签是一个编辑器，则直接发送，否则创建一个
	if not get_tab_title(current_tab).begins_with("SQL File"):
		_on_tab_clicked(current_tab)
		
	var code_edit = get_tab_control(current_tab).code_edit as CodeEdit
	code_edit.text += content
