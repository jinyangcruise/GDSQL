@tool
extends VSplitContainer

signal request_open_file(path: String)
signal change_tab_title(page: Control, title: String)

@onready var _code_edit: CodeEdit = %CodeEdit
@onready var button_commit: Button = %ButtonCommit
@onready var button_rollback: Button = %ButtonRollback
@onready var button_auto_commit: Button = %ButtonAutoCommit
@onready var results_tab: TabContainer = %ResultsTab


var code_edit: CodeEdit:
	get:
		return _code_edit
		
func _ready() -> void:
	button_commit.disabled = button_auto_commit.button_pressed
	button_rollback.disabled = button_auto_commit.button_pressed
	
func _on_button_auto_commit_toggled(button_pressed: bool) -> void:
	button_commit.disabled = button_pressed
	button_rollback.disabled = button_pressed
	
func _on_button_open_pressed() -> void:
	var editor_file_dialog = EditorFileDialog.new()
	editor_file_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	editor_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	editor_file_dialog.add_filter("*.gdsqltext", "GDSQL Text File")
	editor_file_dialog.file_selected.connect(func(path: String):
		request_open_file.emit(path)
	, CONNECT_DEFERRED)
	add_child(editor_file_dialog)
	editor_file_dialog.popup_centered_ratio(0.7)
	editor_file_dialog.close_requested.connect(func():
		editor_file_dialog.queue_free()
	, CONNECT_DEFERRED)
	
func _on_button_save_pressed() -> void:
	# 本身就是一个已经保存的文件，就直接保存
	if get_meta("is_file"):
		var config = GDSQL.ImprovedConfigFile.new()
		config.set_value("data", "content", code_edit.text)
		config.save(get_meta("file_path"))
		change_tab_title.emit(self, get_meta("file_name").get_basename())
		if GDSQL.GDSQLUtils.localize_path(get_meta("file_path")).begins_with("res://"):
			EditorInterface.get_resource_filesystem().update_file(GDSQL.GDSQLUtils.localize_path(get_meta("file_path")))
		return
		
	_on_button_save_as_pressed()
	
func _on_button_save_as_pressed():
	var editor_file_dialog = EditorFileDialog.new()
	editor_file_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM
	editor_file_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	editor_file_dialog.add_filter("*.gdsqltext", "GDSQL Text File")
	editor_file_dialog.file_selected.connect(func(path: String):
		var config = GDSQL.ImprovedConfigFile.new()
		config.set_value("data", "content", code_edit.text)
		config.save(path)
		var file_name = path.get_file()
		change_tab_title.emit(self, file_name.get_basename())
		set_meta("type", "sql_file")
		set_meta("is_file", true)
		set_meta("file_name", file_name)
		set_meta("file_path", path)
		if GDSQL.GDSQLUtils.localize_path(get_meta("file_path")).begins_with("res://"):
			EditorInterface.get_resource_filesystem().update_file(GDSQL.GDSQLUtils.localize_path(get_meta("file_path")))
	)
	add_child(editor_file_dialog)
	editor_file_dialog.popup_centered_ratio(0.7)
	editor_file_dialog.close_requested.connect(editor_file_dialog.queue_free)
	
func _on_code_edit_text_changed() -> void:
	if get_meta("is_file"):
		change_tab_title.emit(self, get_meta("file_name").get_basename() + "*")
		
func load_sql_file(path: String):
	var config = GDSQL.ImprovedConfigFile.new()
	config.load(path)
	var content = config.get_value("data", "content", "")
	code_edit.text = content
	
	set_meta("type", "sql_file")
	set_meta("is_file", true)
	set_meta("file_path", path)
	set_meta("file_name", path.get_file())
	
func _on_button_run_edit_pressed() -> void:
	# TODO 已知sql语句是用分号来进行划分的，在一行中，如果出现 -- （两个减号 + 空格）或 # 或 /*  */，
	# 则表示注释内容。
	# 我们的目标是：找到光标所在行的单个sql语句。这个sql语句可能跨行了，在光标所在行的上方或下方，都有可能。
	# 另外，光标所在行还有可能存在多个sql语句，那么就要考虑光标的column是处于哪个sql语句了。此外，还要
	# 把注释部分去掉。
	var sql = code_edit.get_line(code_edit.get_caret_line(0))
	printt("sql:", sql)
