@tool
extends ScrollContainer

var mgr: GDSQLWorkbenchManagerClass = Engine.get_singleton("GDSQLWorkbenchManager")

@onready var line_edit_file_path = $VBoxContainer/HBoxContainer/LineEditFilePath
@onready var button_file_path_resource = $VBoxContainer/HBoxContainer/ButtonFilePathResource
@onready var button_file_path_user_data = $VBoxContainer/HBoxContainer/ButtonFilePathUserData
@onready var button_file_path_file_system = $VBoxContainer/HBoxContainer/ButtonFilePathFileSystem
@onready var table_sample = $VBoxContainer/TableSample
@onready var check_box_use_existing_table = $VBoxContainer/HBoxContainer2/CheckBoxUseExistingTable
@onready var option_button_tables = $VBoxContainer/HBoxContainer2/OptionButtonTables
@onready var check_box_create_new_table = $VBoxContainer/HBoxContainer3/CheckBoxCreateNewTable
@onready var option_button_dbs = $VBoxContainer/HBoxContainer3/OptionButtonDbs
@onready var line_edit_table_name = $VBoxContainer/HBoxContainer3/LineEditTableName
@onready var check_box_truncate_table = $VBoxContainer/CheckBoxTruncateTable
@onready var check_box_drop_table = $VBoxContainer/CheckBoxDropTable
@onready var margin_container_use_existing_table = $VBoxContainer/MarginContainerUseExistingTable
@onready var margin_container_create_new_table = $VBoxContainer/MarginContainerCreateNewTable
@onready var grid_container_columns_using_existing_table = $VBoxContainer/MarginContainerUseExistingTable/PanelContainer/GridContainerColumnsUsingExistingTable
@onready var grid_container_columns_create_new_table = $VBoxContainer/MarginContainerCreateNewTable/PanelContainer/GridContainerColumnsCreateNewTable
@onready var check_box_select_all_1 = $VBoxContainer/MarginContainerUseExistingTable/PanelContainer/GridContainerColumnsUsingExistingTable/CheckBoxSelectAll1
@onready var check_box_select_all_2 = $VBoxContainer/MarginContainerCreateNewTable/PanelContainer/GridContainerColumnsCreateNewTable/CheckBoxSelectAll2
@onready var label_data_samples = $VBoxContainer/LabelDataSamples

const DATA_EXTENSION = ".gsql"
const CONF_EXTENSION = ".cfg"
const MAX_INT = 9223372036854775807

var _columns = []

func _ready():
	if mgr == null or not mgr.run_in_plugin(self):
		return
	option_button_tables.clear()
	option_button_dbs.clear()
	for a_db_name in mgr.databases:
		for a_table_name in mgr.databases[a_db_name]["tables"]:
			option_button_tables.add_item(a_db_name + "." + a_table_name)
		option_button_dbs.add_item(a_db_name)

func _exit_tree():
	if mgr == null or not mgr.run_in_plugin(self):
		return
	option_button_tables.clear()
	option_button_dbs.clear()
	clear_columns()
	mgr = null
	
func select_table(db_name, table_name):
	for i in option_button_tables.item_count:
		if option_button_tables.get_item_text(i) == db_name + "." + table_name:
			option_button_tables.select(i)
			_on_option_button_tables_item_selected(i)
			
## 选中某个表时触发
func _on_option_button_tables_item_selected(_index):
	check_box_use_existing_table.button_pressed = true
	_on_check_box_use_existing_table_toggled(true)
	refresh_dest_column()
	
func refresh_dest_column():
	var table = option_button_tables.get_item_text(option_button_tables.selected).split(".")
	var db_name = table[0]
	var table_name = table[1]
	# 更新Dest Column下拉菜单
	var obs = get_tree().get_nodes_in_group("dest_option_buttons")
	for option: OptionButton in obs:
		option.selected = -1
		option.clear()
		var pos = -1
		var potential_pos = -1
		for i in mgr.databases[db_name]["tables"][table_name]["columns"]:
			pos += 1
			option.add_item(i["Column Name"])
			var option_pos = option.get_index()
			var source_column_name = (option.get_parent().get_child(option_pos-1) as Label).text
			if i["Column Name"].to_lower().to_camel_case() == source_column_name.to_lower().to_camel_case():
				potential_pos = pos
		option.selected = potential_pos
		
func reset_columns():
	clear_columns()
	check_box_select_all_1.button_pressed = true
	check_box_select_all_2.button_pressed = true
	var button_group = ButtonGroup.new()
	# 设置主键的按钮组点击后，设置一下主键
	button_group.pressed.connect(func(button: BaseButton):
		var sibling_cb = button.get_parent().get_child(button.get_index() - 3)
		var cbs = get_tree().get_nodes_in_group("check_box_1")
		for cb in cbs:
			if cb == sibling_cb:
				cb.set_meta("PK", true)
			else:
				cb.set_meta("PK", false)
	)
	for i in _columns:
		# using existing table
		var cb = CheckBox.new()
		cb.button_pressed = true
		grid_container_columns_using_existing_table.add_child(cb)
		cb.add_to_group("check_box_0")
		cb.set_meta("col", i)
		
		var label = Label.new()
		label.text = i
		grid_container_columns_using_existing_table.add_child(label)
		
		var opb = OptionButton.new()
		opb.add_to_group("dest_option_buttons")
		grid_container_columns_using_existing_table.add_child(opb)
		
		# create new table
		var cb1 = CheckBox.new()
		cb1.button_pressed = true
		grid_container_columns_create_new_table.add_child(cb1)
		cb1.add_to_group("check_box_1")
		cb1.set_meta("col", i)
		cb1.set_meta("dataType", 0)
		cb1.set_meta("PK", false)
		
		var label1 = Label.new()
		label1.text = i
		grid_container_columns_create_new_table.add_child(label1)
		
		var opb1 = OptionButton.new()# data type
		var id = 0
		for j in DataTypeDef.DATA_TYPE_NAMES.size():
			opb1.add_item(DataTypeDef.DATA_TYPE_NAMES[j], id)
			opb1.set_item_metadata(opb1.get_item_index(id), j)
			id += 1
			
		var i_pos = _columns.find(i)
		grid_container_columns_create_new_table.add_child(opb1)
		opb1.item_selected.connect(func(index):
			var sibling_cb = opb1.get_parent().get_child(opb1.get_index() - 2)
			sibling_cb.set_meta("dataType", opb1.get_item_metadata(index))
		)
		opb1.selected = typeof(table_sample.datas[0][i_pos])
		opb1.item_selected.emit(opb1.selected)
		
		var cb2 = CheckBox.new() # primary key
		grid_container_columns_create_new_table.add_child(cb2)
		cb2.button_group = button_group
		if i_pos == 0:
			cb2.button_pressed = true
		
	refresh_dest_column()
	
## 全选按钮切换
func _on_check_box_select_all_toggled(toggled_on, type):
	var cbs = get_tree().get_nodes_in_group("check_box_%s" % type)
	for i: CheckBox in cbs:
		i.button_pressed = toggled_on
		
## 导入文件选择
func _on_button_file_path_pressed(access):
	var editor_file_dialog = EditorFileDialog.new()
	editor_file_dialog.filters = PackedStringArray(["*.cfg", "*.csv", "*.json"])
	editor_file_dialog.access = access
	editor_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	editor_file_dialog.file_selected.connect(func(path: String):
		line_edit_file_path.text = path
		label_data_samples.show()
		table_sample.show()
		var ret
		match path.get_extension().to_lower():
			"cfg":
				ret = read_cfg(path, 4)
			"csv":
				ret = read_csv(path, 4)
			"json":
				ret = read_json(path, 4)
			_:
				mgr.create_accept_dialog("Do not support this file! Valid file extension: .cfg, .csv, .json")
				return
				
		table_sample.columns = ret[0]
		table_sample.datas = ret[1]
		_columns = ret[0]
		reset_columns()
	)
	add_child(editor_file_dialog)
	editor_file_dialog.popup_centered_ratio(0.5)
	editor_file_dialog.close_requested.connect(func():
		editor_file_dialog.queue_free()
	)
	
func clear_columns():
	while grid_container_columns_using_existing_table.get_child_count() > 3:
		var node = grid_container_columns_using_existing_table.get_child(
			grid_container_columns_using_existing_table.get_child_count() - 1)
		grid_container_columns_using_existing_table.remove_child(node)
		node.queue_free()
	while grid_container_columns_create_new_table.get_child_count() > 4:
		var node = grid_container_columns_create_new_table.get_child(
			grid_container_columns_create_new_table.get_child_count() - 1)
		grid_container_columns_create_new_table.remove_child(node)
		node.queue_free()
	
func read_cfg(path, limit = 4) -> Array:
	var conf = ConfigFile.new()
	conf.load(path)
	var sections = conf.get_sections()
	if sections.is_empty():
		mgr.create_accept_dialog("File is empty or not a valid .cfg file!")
		return []
		
	var datas = []
	var keys = conf.get_section_keys(sections[0])
	for i in sections.size():
		if i >= limit:
			break
		var data = []
		for key in keys:
			data.push_back(conf.get_value(sections[i], key))
		datas.push_back(data)
		
	return [keys, datas]
	
func read_csv(path, limit = 4) -> Array:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		mgr.create_accept_dialog("Cannot open this file! Err code:%s" % FileAccess.get_open_error())
		return []
		
	var i = 0
	var head
	var datas = []
	var delim = ","
	while file.get_position() < file.get_length() and i <= limit:
		if i == 0:
			head = Array(file.get_csv_line(delim))
		else:
			datas.push_back(Array(file.get_csv_line(delim)))
		i += 1
	if head == null or datas.is_empty():
		mgr.create_accept_dialog("File is empty or not a valid .csv file!")
		return []
		
	return [head, datas]
	
func read_json(path, limit = 4) -> Array:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		mgr.create_accept_dialog("Cannot open this file! Err code:%s" % FileAccess.get_open_error())
		return []
		
	var content = file.get_as_text()
	var json = JSON.parse_string(content)
	if json is Dictionary:
		json = (json as Dictionary).values()
	if json == null or not json is Array or (json as Array).size() < 1 or not json[0] is Dictionary:
		mgr.create_accept_dialog("File is empty or not a valid .json file!")
		return []
		
	json = json as Array
	var keys = (json[0] as Dictionary).keys()
	var datas = []
	for i in json.size():
		if i >= limit:
			break
		var data = []
		for key in keys:
			data.push_back(json[i][key])
		datas.push_back(data)
		
	return [keys, datas]

func _on_button_cancel_pressed():
	queue_free()


func _on_check_box_use_existing_table_toggled(toggled_on):
	margin_container_use_existing_table.visible = toggled_on
	margin_container_create_new_table.visible = !toggled_on
	check_box_truncate_table.visible = toggled_on
	check_box_drop_table.visible = !toggled_on


func _on_check_box_create_new_table_toggled(toggled_on):
	margin_container_use_existing_table.visible = !toggled_on
	margin_container_create_new_table.visible = toggled_on
	check_box_truncate_table.visible = !toggled_on
	check_box_drop_table.visible = toggled_on


func _on_button_apply_pressed() -> void:
	var cbs = get_tree().get_nodes_in_group("check_box_%s" % \
		("0" if check_box_use_existing_table.button_pressed else "1"))
	var checked = []
	for i: CheckBox in cbs:
		if i.button_pressed:
			checked.push_back(i)
	if checked.is_empty():
		return mgr.create_accept_dialog("Must import at least one column!")
		
	if line_edit_file_path.text == "":
		return mgr.create_accept_dialog("Must enter an import file path!")
		
	if check_box_create_new_table.button_pressed and line_edit_table_name.text == "":
		return mgr.create_accept_dialog("Must enter a table name")
		
	var db_name
	var table_name
	# 导入到新建表中
	if check_box_create_new_table.button_pressed:
		var column_infos = []
		var has_pk = false
		for cb: CheckBox in checked:
			if cb.get_meta("PK"):
				has_pk = true
			var data = {
				"Column Name": cb.get_meta("col"),
				"Data Type": cb.get_meta("dataType"),
				"PK": cb.get_meta("PK"),
				"AI": false,
				"Comment": "",
				"Default(Expression)": "",
				"Hint": PROPERTY_HINT_NONE,
				"Hint String": "",
				"NN": false,
				"UQ": false
			}
			column_infos.push_back(data)
			
		if not has_pk:
			mgr.create_accept_dialog("Must import primary key!")
			return
		db_name = option_button_dbs.get_item_text(option_button_dbs.selected)
		table_name = line_edit_table_name.text
		if check_box_drop_table.button_pressed and mgr.databases[db_name]["tables"].has(table_name):
			mgr.request_user_enter_password.emit(db_name, table_name, "", func():
				mgr.request_drop_table.emit(db_name, table_name)
			)
			
		if not check_box_drop_table.button_pressed and mgr.databases[db_name]["tables"].has(table_name):
			mgr.create_accept_dialog("Table exist! Please select `Using existing table` or check `Drop table if exist`.")
			return
			
		# 请求新建表
		mgr.request_create_table.emit(db_name, table_name, "", "", column_infos)
	# 导入到存量表中
	elif check_box_use_existing_table.button_pressed:
		var table = option_button_tables.get_item_text(option_button_tables.selected).split(".")
		db_name = table[0]
		table_name = table[1]
		
	# 不管是新建的表，还是存量表，逻辑一致
	mgr.request_user_enter_password.emit(db_name, table_name, "", func():
		var db_path = mgr.databases[db_name]["data_path"]
		var table_path = table_name + DATA_EXTENSION
		var begin_time_1 = Time.get_unix_time_from_system()
		var action
		if check_box_truncate_table.button_pressed:
			var dao1 = BaseDao.new()
			var ret = dao1.use_db(db_path).delete_from(table_path).query()
			action = "Delete from %s.%s" % [db_name, table_name]
			if ret == null:
				mgr.add_log_history.emit("Err", begin_time_1, action, "somthing wrong")
				return
				
			if not ret.ok():
				mgr.add_log_history.emit("Err", begin_time_1, action, ret.get_err())
				return
				
			mgr.add_log_history.emit("OK", begin_time_1, action, "%d row(s) affected" % ret.get_affected_rows())
			
		action = "Table data import to %s.%s" % [db_name, table_name]
		var file_ret
		var path = line_edit_file_path.text
		match path.get_extension().to_lower():
			"cfg":
				file_ret = read_cfg(path, MAX_INT)
			"csv":
				file_ret = read_csv(path, MAX_INT)
			"json":
				file_ret = read_json(path, MAX_INT)
			_:
				mgr.create_accept_dialog("Do not support this file! Valid file extension: .cfg, .csv, .json")
				return
		var columns = file_ret[0] as Array
		var datas = file_ret[1] as Array
		var col_indexes = []
		for cb: CheckBox in checked:
			col_indexes.push_back(columns.find(cb.get_meta("col")))
		var dao: BaseDao
		# 中间发生任何错误会中断。但是没发生错误的数据会保存进去。
		var err = OK
		var total_affected_rows = 0
		for data in datas:
			var begin_time_2 = Time.get_unix_time_from_system()
			var value = {}
			for i in col_indexes:
				value[columns[i]] = data[i]
			dao = BaseDao.new()
			var ret = dao.auto_commit(false).use_db(db_path).insert_into(table_path).values(value).query()
			if ret == null:
				err = "something wrong"
				mgr.add_log_history.emit("Err", begin_time_2, dao.get_query_cmd(), err)
				break
				
			if not ret.ok():
				err = ret.get_err()
				mgr.add_log_history.emit("Err", begin_time_2, dao.get_query_cmd(), err)
				break
				
			total_affected_rows += ret.get_affected_rows()
			mgr.add_log_history.emit("OK", begin_time_2, dao.get_query_cmd(), "%d row(s) affected." % ret.get_affected_rows())
		# 最后再统一提交
		dao.commit()
		if err is int and err == OK:
			mgr.add_log_history.emit("OK", begin_time_1, action, "Finished! Total %d row(s) affected." % total_affected_rows)
		else:
			mgr.add_log_history.emit("Err", begin_time_1, action, "Err occur! Total %d row(s) affected." % total_affected_rows)
	)
	
