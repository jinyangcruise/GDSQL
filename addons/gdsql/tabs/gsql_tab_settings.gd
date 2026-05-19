@tool
extends VBoxContainer

@onready var line_edit_root_config: LineEdit = %LineEditRootConfig
@onready var line_edit_suppl_config: LineEdit = %LineEditSupplConfig
@onready var option_game_db_name: OptionButton = %OptionButtonGameDbName
@onready var status_label: Label = %StatusLabel

const SETTINGS_PATH = "res://gdsql/settings.cfg"

var _default_values = {
	"root_config_path": "res://gdsql/define/config.cfg",
	"supplementary_config_path": "user://gdsql/define/runtime_config.cfg",
	"game_conf_db_name": "",
}


func _ready() -> void:
	_load_settings()


func _load_settings() -> void:
	var settings := ConfigFile.new()
	var err = settings.load(SETTINGS_PATH)
	if err != OK:
		line_edit_root_config.text = _default_values["root_config_path"]
		line_edit_suppl_config.text = _default_values["supplementary_config_path"]
	else:
		line_edit_root_config.text = settings.get_value("config", "root_config_path", _default_values["root_config_path"])
		line_edit_suppl_config.text = settings.get_value("config", "supplementary_config_path", _default_values["supplementary_config_path"])
	
	# Populate game conf db name dropdown
	_populate_db_dropdown()
	
	var saved_db_name = _default_values["game_conf_db_name"]
	if err == OK:
		saved_db_name = settings.get_value("config", "game_conf_db_name", _default_values["game_conf_db_name"])
	
	# Select the saved value in dropdown
	for i in option_game_db_name.item_count:
		if option_game_db_name.get_item_text(i) == saved_db_name:
			option_game_db_name.select(i)
			break


func _populate_db_dropdown() -> void:
	option_game_db_name.clear()
	option_game_db_name.add_item("")  # Empty option
	
	var mgr = GDSQL.WorkbenchManager
	if mgr and mgr.databases:
		for db_name: String in mgr.databases:
			option_game_db_name.add_item(db_name)


func _on_select_root_config_path(access: int) -> void:
	var editor_file_dialog = EditorFileDialog.new()
	editor_file_dialog.access = access
	editor_file_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	editor_file_dialog.add_filter("*.cfg", "Config File")
	editor_file_dialog.file_selected.connect(func(path: String):
		line_edit_root_config.text = path
	, CONNECT_DEFERRED)
	add_child(editor_file_dialog)
	editor_file_dialog.popup_centered_ratio(0.5)
	editor_file_dialog.close_requested.connect(func():
		editor_file_dialog.queue_free()
	, CONNECT_DEFERRED)


func _on_select_supplementary_config_path(access: int) -> void:
	var editor_file_dialog = EditorFileDialog.new()
	editor_file_dialog.access = access
	editor_file_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	editor_file_dialog.add_filter("*.cfg", "Config File")
	editor_file_dialog.file_selected.connect(func(path: String):
		line_edit_suppl_config.text = path
	, CONNECT_DEFERRED)
	add_child(editor_file_dialog)
	editor_file_dialog.popup_centered_ratio(0.5)
	editor_file_dialog.close_requested.connect(func():
		editor_file_dialog.queue_free()
	, CONNECT_DEFERRED)


func _on_install_config_path(target_node_name: String) -> void:
	var target = get_node("%" + target_node_name) as LineEdit
	if target:
		var base_path = "install://"
		var current = target.text.strip_edges()
		# If the field already has an install:// path with subdirectory, preserve the subdirectory
		if current.begins_with("install://") and current.length() > len("install://"):
			target.text = current
		else:
			target.text = "install://"
		target.grab_focus()


func _on_button_save_pressed() -> void:
	var root_config_path = line_edit_root_config.text.strip_edges()
	var suppl_config_path = line_edit_suppl_config.text.strip_edges()
	
	if root_config_path.is_empty():
		root_config_path = _default_values["root_config_path"]
		line_edit_root_config.text = root_config_path
		
	if suppl_config_path.is_empty():
		suppl_config_path = _default_values["supplementary_config_path"]
		line_edit_suppl_config.text = suppl_config_path
	
	var game_db_name = ""
	if option_game_db_name.selected > 0:
		game_db_name = option_game_db_name.get_item_text(option_game_db_name.selected)
	
	var settings := ConfigFile.new()
	
	if FileAccess.file_exists(SETTINGS_PATH):
		settings.load(SETTINGS_PATH)
	
	settings.set_value("config", "root_config_path", root_config_path)
	settings.set_value("config", "supplementary_config_path", suppl_config_path)
	settings.set_value("config", "game_conf_db_name", game_db_name)
	
	var err = settings.save(SETTINGS_PATH)
	if err == OK:
		_show_status("Settings saved successfully.", Color(0.4, 0.8, 0.4))
	else:
		_show_status("Failed to save settings! Error: %d" % err, Color(0.9, 0.3, 0.3))


func _show_status(text: String, color: Color) -> void:
	status_label.text = text
	status_label.add_theme_color_override("font_color", color)
	await get_tree().create_timer(3.0).timeout
	if status_label:
		status_label.text = ""
