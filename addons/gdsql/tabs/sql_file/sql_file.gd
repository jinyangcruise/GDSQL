@tool
extends VSplitContainer

signal request_open_file(path: String)
signal change_tab_title(page: Control, title: String)

@onready var _code_edit: CodeEdit = $VBoxContainer/CodeEdit
@onready var button_commit: Button = $VBoxContainer/HFlowContainer/ButtonCommit
@onready var button_rollback: Button = $VBoxContainer/HFlowContainer/ButtonRollback
@onready var button_auto_commit: Button = $VBoxContainer/HFlowContainer/ButtonAutoCommit


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
