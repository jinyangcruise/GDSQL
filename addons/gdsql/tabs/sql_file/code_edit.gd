@tool
extends CodeEdit

@export var button_run_edit: Button

var in_run_edit = false
var in_run_edit_shortcut_feedback = false

func _can_drop_data(_position, data):
	# { "type": "files", "files": ["res://src/dao/t_hero.gdmappergraph"], "from": @Tree@6840:<Tree#603409380691> }
	if data is Dictionary:
		if data.has("type") and data.has("files") and data.get("type") == "files":
			for i in data.get("files"):
				if i is String:
					if i.ends_with(".gdsqltext") or i.ends_with(".gdsqlgraph") or i.ends_with(".gdmappergraph"):
						return true
	return false
	
func _drop_data(_position, data):
	for i in data.get("files"):
		if i is String:
			if i.ends_with(".gdsqltext"):
				GDSQL.WorkbenchManager.open_sql_text_file_tab.emit(i)
			elif i.ends_with(".gdsqlgraph"):
				GDSQL.WorkbenchManager.open_sql_graph_file_tab.emit(i)
			elif i.ends_with(".gdmappergraph"):
				GDSQL.WorkbenchManager.open_mapper_graph_file_tab.emit(i)
				
func _gui_input(event: InputEvent) -> void:
	if in_run_edit_shortcut_feedback:
		if event is InputEventKey:
			accept_event()
		return
	if button_run_edit.shortcut.matches_event(event):
		in_run_edit = true
		if event.is_released():
			_button_run_edit_pressed()
		accept_event()
		return
	elif in_run_edit:
		in_run_edit = false
		_button_run_edit_pressed()
		accept_event()
		return
		
func _button_run_edit_pressed():
	button_run_edit.pressed.emit()
	var normal_sb = button_run_edit.get_theme_stylebox("normal")
	var hover_pressed_sb = button_run_edit.get_theme_stylebox("hover_pressed")
	button_run_edit.add_theme_stylebox_override("normal", hover_pressed_sb)
	in_run_edit_shortcut_feedback = true
	await get_tree().create_timer(ProjectSettings.get_setting("gui/timers/button_shortcut_feedback_highlight_time", 0.2)).timeout
	in_run_edit_shortcut_feedback = false
	if button_run_edit:
		button_run_edit.add_theme_stylebox_override("normal", normal_sb)
