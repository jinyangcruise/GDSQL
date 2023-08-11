@tool
extends TabContainer

signal add_new_schema(db_name: String, path: String, save: bool, id: String)
signal alter_old_schema(old_db_name, new_db_name: String, path: String, save: bool, id: String)
signal add_new_table(db_name: String, db_path: String, table_name: String, id: String)

@onready var new_tab_button: Control = $"➕"

var _tab_index = 1

var _tab_activate_time: float = 0

func _ready() -> void:
	_on_tab_clicked(0)


func _on_tab_clicked(tab: int) -> void:
	# 点击了“新建SQL页面”（加号），增加一个编辑页面，并激活
	if get_child(tab) == new_tab_button:
		var sql_file = preload("res://addons/gdsql/tabs/sql_graph.tscn").instantiate()
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
	new_schema.button_apply_pressed.connect(func(db_name, path, save, id):
		add_new_schema.emit(db_name, path, save, id)
	)
	add_child(new_schema)
	move_child(new_tab_button, get_child_count() - 1)
	current_tab = get_child_count() - 2
	set_tab_title(current_tab, "new_schema")
		
func add_tab_alter_schema(db_name, path, save) -> void:
	var alter_schema = preload("res://addons/gdsql/tabs/alter_schema.tscn").instantiate()
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
	
func add_tab_new_table(db_name, db_path) -> void:
	var new_table = preload("res://addons/gdsql/tabs/new_table.tscn").instantiate()
	new_table.schema = db_name
	new_table.schema_path = db_path
	new_table.button_apply_pressed.connect(func(schema, schema_path, table_name, columns, id):
		add_new_table.emit(schema, schema_path, table_name, columns, id))
	#new_table.button_apply_pressed.connect(func(db_name, path, save, id):
		#add_new_schema.emit(db_name, path, save, id)
	#)
	add_child(new_table)
	move_child(new_tab_button, get_child_count() - 1)
	current_tab = get_child_count() - 2
	set_tab_title(current_tab, "new_table")
	
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
	# 当前打开的页签是一个编辑器，则直接发送，否则创建一个
	if get_tab_control(current_tab).get_meta("type") == "sql_graph":
		if force_new:
			var code_edit_1 = get_tab_control(current_tab).code_edit as CodeEdit
			# 空的可以直接用，非空的还是需要创建新的；如果是文件，即使是空的，也要开新的
			if not code_edit_1.text.is_empty() or get_tab_control(current_tab).get_meta("is_file"):
				_on_tab_clicked(get_tab_count()-1)
	else :
		_on_tab_clicked(get_tab_count()-1)
		
	var code_edit = get_tab_control(current_tab).code_edit as CodeEdit
	code_edit.text += content
	
	if not file_path.is_empty():
		var sp = file_path.rsplit("/", true, 1)
		var file_name = sp[sp.size()-1]
		var page = get_current_tab_control()
		page.set_meta("is_file", true)
		page.set_meta("file_name", file_name)
		page.set_meta("file_path", file_path)
		set_tab_title(current_tab, file_name)
	
func receive_content_and_execute(title: String, content: String):
	# 因为要执行，所以直接创建新页面
	_on_tab_clicked(get_tab_count()-1)
	
	set_tab_title(current_tab, title)
	
	var code_edit = get_tab_control(current_tab).code_edit as CodeEdit
	code_edit.text = content
