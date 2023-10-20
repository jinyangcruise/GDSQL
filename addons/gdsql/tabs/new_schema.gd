@tool
extends VBoxContainer

## id: 发出信号的是谁
#signal button_apply_pressed(db_name: String, path: String, save: bool, id: String)

var mgr: GDSQLWorkbenchManagerClass = Engine.get_singleton("GDSQLWorkbenchManager")

@onready var line_edit_name: LineEdit = $HBoxContainer/LineEditName
@onready var line_edit_path: LineEdit = $HBoxContainer2/LineEditPath

@onready var h_box_container_2: HBoxContainer = $HBoxContainer2


func _on_button_pressed(access) -> void:
	var editor_file_dialog = EditorFileDialog.new()
	editor_file_dialog.access = access
	editor_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
	editor_file_dialog.dir_selected.connect(func(dir: String):
		if not dir.ends_with("/"):
			dir += "/"
		line_edit_path.text = dir
	, CONNECT_DEFERRED)
	h_box_container_2.add_child(editor_file_dialog)
	editor_file_dialog.popup_centered_ratio(0.5)
	editor_file_dialog.close_requested.connect(func():
		editor_file_dialog.queue_free()
	, CONNECT_DEFERRED)


func _on_button_apply_pressed() -> void:
	var db_name = line_edit_name.text.strip_edges()
	var path = line_edit_path.text.strip_edges()
	if db_name.is_empty() or path.is_empty():
		mgr.create_accept_dialog("name and path must be set!")
		return
		
	mgr.user_confirm_add_schema.emit(db_name, path, name)
	#queue_free() 已改为让TabContainer接收到成功添加的信号后删除该页签

func _on_button_cancel_pressed() -> void:
	mgr = null
	queue_free()
