@tool
extends ScrollContainer

var mgr: GDSQLWorkbenchManagerClass = Engine.get_singleton("GDSQLWorkbenchManager")

@onready var grid_container_columns = $VBoxContainer/MarginContainer/PanelContainer/GridContainerColumns
@onready var line_edit_file_path = $VBoxContainer/HBoxContainer3/LineEditFilePath
@onready var margin_container_csv_options = $VBoxContainer/MarginContainerCSVOptions
@onready var option_button_field_seperator = $VBoxContainer/MarginContainerCSVOptions/PanelContainer2/VBoxContainer/GridContainer/OptionButtonFieldSeperator
@onready var option_button_line_seperator = $VBoxContainer/MarginContainerCSVOptions/PanelContainer2/VBoxContainer/GridContainer/OptionButtonLineSeperator
@onready var line_edit_enclose_strings_in = $VBoxContainer/MarginContainerCSVOptions/PanelContainer2/VBoxContainer/GridContainer/LineEditEncloseStringsIn
@onready var check_box_gsql = $VBoxContainer/HFlowContainer/CheckBoxGSQL
@onready var check_box_csv = $VBoxContainer/HFlowContainer/CheckBoxCSV
@onready var check_box_json = $VBoxContainer/HFlowContainer/CheckBoxJSON
@onready var check_box_open_folder_when_finished = $VBoxContainer/CheckBoxOpenFolderWhenFinished
@onready var table_data_samples = $VBoxContainer/TableDataSamples

const DATA_EXTENSION = ".gsql"

var _columns
var _datas
var _button_group = ButtonGroup.new()

func _ready():
	_button_group.allow_unpress = true

func load_data(columns, datas):
	_columns = columns
	_datas = datas
	
	table_data_samples.columns = columns.map(func(v): return v["field_as"])
	table_data_samples.datas = datas.slice(0, 4)
	
	while grid_container_columns.get_child_count() > 4:
		var cb = grid_container_columns.get_child(grid_container_columns.get_child_count() - 1)
		grid_container_columns.remove_child(cb)
		cb.queue_free()
		
	if columns.size() < 1:
		return
		
	var index = 0
	for i in columns:
		var check_box = CheckBox.new()
		check_box.button_pressed = true
		check_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		check_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		check_box.add_to_group("check_box")
		grid_container_columns.add_child(check_box)
		var label = Label.new()
		label.text = i["field_as"]
		check_box.set_meta("col", index)
		grid_container_columns.add_child(label)
		var label_comment = Label.new()
		label_comment.text = i["Comment"] if i.has("Comment") else (i["select_name"] if i.has("select_name") else "")
		grid_container_columns.add_child(label_comment)
		var check_box_2 = CheckBox.new()
		check_box_2.set_meta("col", index)
		check_box_2.button_group = _button_group
		check_box_2.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		check_box_2.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid_container_columns.add_child(check_box_2)
		index += 1

func _exit_tree():
	mgr = null

## 全选按钮切换
func _on_check_box_select_all_toggled(toggled_on):
	var cbs = get_tree().get_nodes_in_group("check_box")
	for i: CheckBox in cbs:
		i.button_pressed = toggled_on

## 导出文件选择
func _on_button_file_path_pressed(access):
	var editor_file_dialog = EditorFileDialog.new()
	editor_file_dialog.filters = PackedStringArray(["*.cfg", "*.csv", "*.json"])
	editor_file_dialog.access = access
	editor_file_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	editor_file_dialog.file_selected.connect(func(path: String):
		if path.to_lower().ends_with(".cfg"):
			check_box_gsql.button_pressed = true
		elif path.to_lower().ends_with(".csv"):
			check_box_csv.button_pressed = true
		elif path.to_lower().ends_with(".json"):
			check_box_json.button_pressed = true
		line_edit_file_path.text = path
	, CONNECT_DEFERRED)
	add_child(editor_file_dialog)
	editor_file_dialog.popup_centered_ratio(0.5)
	editor_file_dialog.close_requested.connect(func():
		editor_file_dialog.queue_free()
	, CONNECT_DEFERRED)
	
	
## 导出GSQL
func _on_check_box_gsql_toggled(toggled_on):
	if toggled_on:
		if line_edit_file_path.text != "":
			line_edit_file_path.text = (line_edit_file_path.text as String).get_basename() + ".cfg"

## 导出csv
func _on_check_box_csv_toggled(toggled_on):
	if toggled_on:
		if line_edit_file_path.text != "":
			line_edit_file_path.text = (line_edit_file_path.text as String).get_basename() + ".csv"
	#margin_container_csv_options.visible = toggled_on

## 导出json
func _on_check_box_json_toggled(toggled_on):
	if toggled_on:
		if line_edit_file_path.text != "":
			line_edit_file_path.text = (line_edit_file_path.text as String).get_basename() + ".json"


func _on_button_cancel_pressed():
	queue_free()


func _on_button_apply_pressed() -> void:
	var cbs = get_tree().get_nodes_in_group("check_box")
	var checked = []
	for i: CheckBox in cbs:
		if i.button_pressed:
			checked.push_back(i.get_meta("col"))
	if checked.is_empty():
		return mgr.create_accept_dialog("Must export at least one column!")
		
	if line_edit_file_path.text == "":
		return mgr.create_accept_dialog("Must enter an export file path!")
		
	var begin_time = Time.get_unix_time_from_system()
	var err
	if check_box_gsql.button_pressed:
		err = export_cfg(checked)
	elif check_box_csv.button_pressed:
		err = export_csv(checked)
	elif check_box_json.button_pressed:
		err = export_json(checked)
	else:
		mgr.create_accept_dialog("Do not select an export type!")
		return
		
	if err == OK:
		mgr.add_log_history.emit("OK", begin_time, "Export table data of Select", 
			"1 file: %s was exported!" % line_edit_file_path.text)
		if check_box_open_folder_when_finished.button_pressed:
			OS.shell_show_in_file_manager(GDSQLUtils.globalize_path(line_edit_file_path.text), true)
	else:
		mgr.add_log_history.emit("Err", begin_time, "Export table data of Select", "Err occur, code: %s." % err)
	
func export_cfg(checked):
	var primary_index = -1
	var cb = _button_group.get_pressed_button()
	if cb:
		primary_index = cb.get_meta("col")
	var config = ConfigFile.new()
	for i in _datas.size():
		for j in checked:
			var section = str(_datas[i][primary_index]) if primary_index > 0 else str(i+1)
			config.set_value(section, _columns[j]["field_as"], _datas[i][j])
	var err = config.save(line_edit_file_path.text)
	return err
	
func export_csv(checked):
	var columns = []
	for i in checked:
		columns.push_back(_columns[i]["field_as"])
	var csv = FileAccess.open(line_edit_file_path.text, FileAccess.WRITE)
	if csv == null:
		return FileAccess.get_open_error()
	#var delim = option_button_field_seperator.get_item_text(option_button_field_seperator.selected)
	var delim = ","
	csv.store_buffer([0xEF, 0xBB, 0xBF]) # 带BOM
	csv.store_csv_line(PackedStringArray(columns), delim)
	for i in _datas.size():
		var arr: PackedStringArray = []
		for j in checked:
			arr.push_back(var_to_str(_datas[i][j]))
		csv.store_csv_line(arr, delim)
	return OK
	
func export_json(checked):
	var map = []
	for i in _datas.size():
		var data = {}
		for j in checked:
			data[_columns[j]["field_as"]] = var_to_str(_datas[i][j])
		map.push_back(data)
	var json_string = JSON.stringify(map, "\t", false)
	var json_file = FileAccess.open(line_edit_file_path.text, FileAccess.WRITE)
	if json_file == null:
		return FileAccess.get_open_error()
	json_file.store_string(json_string)
	return OK
