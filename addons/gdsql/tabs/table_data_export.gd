@tool
extends ScrollContainer

var mgr: GDSQLWorkbenchManagerClass = Engine.get_singleton("GDSQLWorkbenchManager")

@onready var option_button_tables: OptionButton = $VBoxContainer/HBoxContainer/OptionButtonTables
@onready var grid_container_columns = $VBoxContainer/MarginContainer/PanelContainer/GridContainerColumns
@onready var line_edit_offset = $VBoxContainer/HBoxContainer2/HBoxContainer/LineEditOffset
@onready var line_edit_count = $VBoxContainer/HBoxContainer2/HBoxContainer/LineEditCount
@onready var line_edit_file_path = $VBoxContainer/HBoxContainer3/LineEditFilePath
@onready var margin_container_csv_options = $VBoxContainer/MarginContainerCSVOptions
@onready var option_button_field_seperator = $VBoxContainer/MarginContainerCSVOptions/PanelContainer2/VBoxContainer/GridContainer/OptionButtonFieldSeperator
@onready var option_button_line_seperator = $VBoxContainer/MarginContainerCSVOptions/PanelContainer2/VBoxContainer/GridContainer/OptionButtonLineSeperator
@onready var line_edit_enclose_strings_in = $VBoxContainer/MarginContainerCSVOptions/PanelContainer2/VBoxContainer/GridContainer/LineEditEncloseStringsIn
@onready var check_box_gsql = $VBoxContainer/HFlowContainer/CheckBoxGSQL
@onready var check_box_csv = $VBoxContainer/HFlowContainer/CheckBoxCSV
@onready var check_box_json = $VBoxContainer/HFlowContainer/CheckBoxJSON
@onready var check_box_open_folder_when_finished = $VBoxContainer/CheckBoxOpenFolderWhenFinished

const DATA_EXTENSION = ".gsql"

func _ready():
	for a_db_name in mgr.databases:
		for a_table_name in mgr.databases[a_db_name]["tables"]:
			option_button_tables.add_item(a_db_name + "." + a_table_name)
			
func _exit_tree():
	option_button_tables.clear()
	mgr = null
	
func select_table(db_name, table_name):
	for i in option_button_tables.item_count:
		if option_button_tables.get_item_text(i) == db_name + "." + table_name:
			option_button_tables.select(i)
			_on_option_button_tables_item_selected(i)

## 选中某个表时触发
func _on_option_button_tables_item_selected(index):
	while grid_container_columns.get_child_count() > 3:
		var cb = grid_container_columns.get_child(grid_container_columns.get_child_count() - 1)
		grid_container_columns.remove_child(cb)
		cb.queue_free()
		
	if index < 0:
		return
	var table = option_button_tables.get_item_text(index).split(".")
	var db_name = table[0]
	var table_name = table[1]
	for i in mgr.databases[db_name]["tables"][table_name]["columns"]:
		var check_box = CheckBox.new()
		check_box.button_pressed = true
		check_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		check_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		check_box.add_to_group("check_box")
		grid_container_columns.add_child(check_box)
		var label = Label.new()
		label.text = i["Column Name"]
		check_box.set_meta("col", i["Column Name"])
		grid_container_columns.add_child(label)
		var label_comment = Label.new()
		label_comment.text = i["Comment"]
		grid_container_columns.add_child(label_comment)

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
	)
	add_child(editor_file_dialog)
	editor_file_dialog.popup_centered_ratio(0.5)
	editor_file_dialog.close_requested.connect(func():
		editor_file_dialog.queue_free()
	)
	
	
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
		
	var table = option_button_tables.get_item_text(option_button_tables.selected).split(".")
	var db_name = table[0]
	var table_name = table[1]
	mgr.request_user_enter_password.emit(db_name, table_name, func():
		var begin_time = Time.get_unix_time_from_system()
		var dao = BaseDao.new()
		var ret = dao.use_db(mgr.databases[db_name]["data_path"])\
			.select(",".join(checked), true).from(table_name + DATA_EXTENSION).query()
		if ret == null:
			mgr.add_log_history.emit("Err", begin_time, "Export table data of %s.%s" % [db_name, table_name], "something wrong")
			return
			
		var err
		if check_box_gsql.button_pressed:
			err = export_cfg(ret.get_raw_data())
		elif check_box_csv.button_pressed:
			err = export_csv(ret.get_raw_data())
		elif check_box_json.button_pressed:
			err = export_json(ret.get_raw_data())
		else:
			mgr.create_accept_dialog("Do not select an export type!")
			return
			
		if err == OK:
			mgr.add_log_history.emit("OK", begin_time, "Export table data of %s.%s" % [db_name, table_name], 
				"1 file: %s was exported!" % line_edit_file_path.text)
			if check_box_open_folder_when_finished.button_pressed:
				OS.shell_show_in_file_manager(ProjectSettings.globalize_path(line_edit_file_path.text), true)
		else:
			mgr.add_log_history.emit("Err", begin_time, "Export table data of %s.%s" % [db_name, table_name], "Err occur, code: %s." % err)
	)
	
func export_cfg(datas):
	var columns = datas[0] as Array
	var primary_index
	for i in columns.size():
		if columns[i]["PK"]:
			primary_index = i
			break
	var config = ConfigFile.new()
	for i in datas.size():
		if i > 0:
			var section = str(datas[i][primary_index])
			for j in columns.size():
				config.set_value(section, columns[j]["Column Name"], datas[i][j])
	var err = config.save(line_edit_file_path.text)
	return err
	
func export_csv(datas):
	var columns = (datas[0] as Array).map(func(v): return v["Column Name"])
	var csv = FileAccess.open(line_edit_file_path.text, FileAccess.WRITE)
	if csv == null:
		return FileAccess.get_open_error()
	#var delim = option_button_field_seperator.get_item_text(option_button_field_seperator.selected)
	var delim = ","
	csv.store_csv_line(PackedStringArray(columns), delim)
	for i in datas.size():
		if i > 0:
			csv.store_csv_line(PackedStringArray(datas[i]), delim)
	return OK
	
func export_json(datas):
	var columns = datas[0] as Array
	var primary_index
	for i in columns.size():
		if columns[i]["PK"]:
			primary_index = i
			break
	var map = []
	for i in datas.size():
		if i > 0:
			var section = str(datas[i][primary_index])
			var data = {}
			for j in columns.size():
				data[columns[j]["Column Name"]] = datas[i][j]
			map.push_back(data)
	var json_string = JSON.stringify(map, "\t", false)
	var json_file = FileAccess.open(line_edit_file_path.text, FileAccess.WRITE)
	if json_file == null:
		return FileAccess.get_open_error()
	json_file.store_string(json_string)
	return OK
