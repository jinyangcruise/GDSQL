@tool
extends VBoxContainer

## id: 发出信号的是谁
#signal button_apply_pressed(old_db_name: String, new_db_name: String, path: String, save: bool, id: String)

var mgr: GDSQLWorkbenchManagerClass = Engine.get_singleton("GDSQLWorkbenchManager")

var old_db_name: String = ""

var db_name: String:
	set(val):
		db_name = val
		if line_edit_name:
			line_edit_name.text = val
			
var path: String:
	set(val):
		path = val
		if line_edit_path:
			line_edit_path.text = val

@onready var line_edit_name: LineEdit = $HBoxContainer/LineEditName
@onready var line_edit_path: LineEdit = $HBoxContainer2/LineEditPath

func _ready() -> void:
	if db_name:
		db_name = db_name
	if path:
		path = path

func _on_button_apply_pressed() -> void:
	var _db_name = line_edit_name.text.strip_edges()
	var _path = line_edit_path.text.strip_edges()
	if _db_name.is_empty() or _path.is_empty():
		mgr.create_accept_dialog("name and path must be set!")
		return
		
	mgr.user_confirm_alter_schema.emit(old_db_name, _db_name, _path, name)
	#button_apply_pressed.emit(old_db_name, _db_name, _path, check_box.button_pressed, name)
	#queue_free() 已改为让TabContainer接收到成功添加的信号后删除该页签

func _on_button_cancel_pressed() -> void:
	mgr = null
	queue_free()
