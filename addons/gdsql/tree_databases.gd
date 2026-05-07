@tool
extends Tree

var mgr: GDSQL.WorkbenchManagerClass:
	get: return GDSQL.WorkbenchManager
	
@onready var popup_menu_database: PopupMenu = $PopupMenuDatabase
@onready var popup_menu_table_item: PopupMenu = $PopupMenuTableItem
@onready var popup_menu_tables: PopupMenu = $PopupMenuTables
@onready var popup_menu_veiws: PopupMenu = $PopupMenuVeiws
@onready var popup_menu_stored_procedures: PopupMenu = $PopupMenuStoredProcedures
@onready var popup_menu_functions: PopupMenu = $PopupMenuFunctions
@onready var popup_menu_empty: PopupMenu = $PopupMenuEmpty
@onready var popup_menu_column: PopupMenu = $PopupMenuColumn

@onready var popup_menu_copy_to: PopupMenu = $PopupMenuDatabase/PopupMenuCopyTo
@onready var popup_menu_send_to: PopupMenu = $PopupMenuDatabase/PopupMenuSendTo
@onready var popup_menu_password: PopupMenu = $PopupMenuDatabase/PopupMenuPassword

@onready var popup_menu_copy_to_of_table: PopupMenu = $PopupMenuTableItem/PopupMenuCopyTo
@onready var popup_menu_send_to_of_table: PopupMenu = $PopupMenuTableItem/PopupMenuSendTo
@onready var popup_menu_password_of_table = $PopupMenuTableItem/PopupMenuPassword

@onready var popup_menu_copy_to_of_column: PopupMenu = $PopupMenuColumn/PopupMenuCopyTo
@onready var popup_menu_send_to_of_column: PopupMenu = $PopupMenuColumn/PopupMenuSendTo

@onready var popup_menu_create_table_like_tables: PopupMenu = $PopupMenuTables/PopupMenuCreateTableLike
@onready var popup_menu_create_table_like_table_item: PopupMenu = $PopupMenuTableItem/PopupMenuCreateTableLike


var root: TreeItem

var database_items: Array[TreeItem] = []
var _default_database_path: String = ""
var _password_correct: Dictionary # 保存输入正确密码的表. {datapath: dek}

var disk_changed: ConfirmationDialog
var disk_changed_list: Tree

enum ITEM_BUTTON_INDEX {
	QUICK_SEARCH = 0,
	FOLDER = 1,
	COLUMN_PROPERTY = 2,
	ENCRYPT = 3,
}

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN or what == NOTIFICATION_VISIBILITY_CHANGED:
		if not is_visible_in_tree() or not disk_changed_list:
			return
		# 提示用户配置被外部工具修改了
		disk_changed_list.clear()
		disk_changed_list.columns = 2
		var r = disk_changed_list.create_item()
		disk_changed_list.hide_root = true
		for path: String in GDSQL.ConfManager._conf_modified_time:
			if not FileAccess.file_exists(path):
				var ti = disk_changed_list.create_item(r)
				ti.set_meta("path", path)
				ti.set_icon(0, get_theme_icon("FileDead", "EditorIcons"))
				ti.set_text(0, path.get_file())
				ti.set_text(1, path)
				ti.add_button(1, get_theme_icon("Clear", "EditorIcons"), 0, 
					false, tr("Clear cache"))
			elif FileAccess.get_modified_time(path) != GDSQL.ConfManager._conf_modified_time[path]:
				var ti = disk_changed_list.create_item(r)
				ti.set_meta("path", path)
				ti.set_icon(0, get_theme_icon("Edit", "EditorIcons"))
				ti.set_text(0, path.get_file())
				ti.set_text(1, path)
				ti.add_button(1, get_theme_icon("Reload", "EditorIcons"), 1, 
					false, tr("Clear cache"))
				ti.add_button(1, get_theme_icon("ExternalLink", "EditorIcons"), 2, 
					false, tr("Open in External Program"))
				ti.add_button(1, get_theme_icon("FileDialog", "EditorIcons"), 3, 
					false, tr("Show in File Manager"))
		if disk_changed_list.get_root().get_child_count() > 0:
			disk_changed.popup_centered_ratio(0.3)
			
func _clear():
	clear()
	database_items.clear()
	popup_menu_create_table_like_tables.clear()
	popup_menu_create_table_like_table_item.clear()
	
func refresh_databases():
	GDSQL.RootConfig.reload()
	mgr.databases = GDSQL.RootConfig.get_databases_info()
	for db_name in mgr.databases:
		for table_name in mgr.databases[db_name]["tables"]:
			if mgr.databases[db_name]["tables"][table_name]["valid_if_not_exist"]:
				GDSQL.ConfManager.mark_valid_if_not_exit(
					GDSQL.RootConfig.get_table_data_path(db_name, table_name))
					
func _get_drag_data(at_position: Vector2) -> Variant:
	var item = get_item_at_position(at_position)
	if not item or item.get_meta("type", "") != "table":
		return
	var texture_rect = TextureRect.new()
	texture_rect.texture = load("res://addons/gdsql/img/table.png")
	texture_rect.size = Vector2(36, 36)
	set_drag_preview(texture_rect)
	return make_drag_data(item)
	
func make_drag_data(item: TreeItem):
	var db_name = item.get_meta("db_name")
	var table_name = item.get_meta("table_name")
	var map = {
		"__table_item": true,
		"db_name": db_name,
		"table_name": table_name,
		"comment": mgr.databases[db_name]["tables"][table_name]["comment"],
		"columns": mgr.databases[db_name]["tables"][table_name]["columns"],
	}
	return map
	
func add_db_to_config(db_name: String, path: String, id: String) -> void:
	db_name = GDSQL.RootConfig.validate_name(db_name)
	var begin_time = Time.get_unix_time_from_system()
	var action = "CREATE DATABASE %s PATH %s;" % [db_name, path]
	var msgs = []
	
	if db_name == GDSQL.RootConfig.DEK or not (db_name.is_valid_ascii_identifier() or db_name.is_valid_unicode_identifier()):
		msgs.push_back(tr("Failed! Database name `%s` is invalid!") % db_name)
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	for a_db_name: String in mgr.databases:
		if a_db_name == db_name:
			msgs.push_back(tr("Failed! Database name `%s` has been occupied!") % db_name)
			mgr.add_log_history.emit("Err", begin_time, action, msgs)
			return mgr.create_accept_dialog(msgs)
			
		if mgr.databases[a_db_name]["data_path"] == path:
			msgs.push_back(tr("Failed! Database path `%s`(%s) already exist!") % [path, a_db_name])
			mgr.add_log_history.emit("Err", begin_time, action, msgs)
			return mgr.create_accept_dialog(msgs)
			
	GDSQL.RootConfig.set_database_data(db_name, path, "")
	GDSQL.RootConfig.save()
	msgs.push_back(tr("1 file: %s has been modified.") % GDSQL.RootConfig.path)
	
	var dir = DirAccess.open(GDSQL.RootConfig.get_base_dir())
	if dir == null:
		msgs.push_back(tr("Failed! Cannot open config root %s dir! Err: %s.") % 
			[GDSQL.RootConfig.get_base_dir(), DirAccess.get_open_error()])
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	var config_path = GDSQL.RootConfig.get_database_config_path(db_name)
	if not dir.dir_exists(config_path):
		var err = dir.make_dir_recursive(config_path)
		if err == OK:
			msgs.push_back(tr("Dir: %s has been made.") % config_path)
		else:
			msgs.push_back(tr("Failed! Cannot make dir %s ! Err: %s.") % [config_path, err])
			mgr.add_log_history.emit("Err", begin_time, action, msgs)
			return mgr.create_accept_dialog(msgs)
			
	mgr.sys_confirm_add_schema.emit(id)
	mgr.add_log_history.emit("OK", begin_time, action, msgs)
	
	refresh()
	
func add_table_to_config(db_name: String, table_name: String, comment: String, 
	password: String, valid_if_not_exist: bool, column_infos: Array, id: String = "") -> void:
	db_name = GDSQL.RootConfig.validate_name(db_name)
	table_name = GDSQL.RootConfig.validate_name(table_name)
	var begin_time = Time.get_unix_time_from_system()
	var action = "CREATE TABLE `%s`.`%s` (" % [db_name, table_name]
	var msgs = []
	var primarys = [] # 不代表支持多主键，只是为了反映用户本身的输入
	for i in column_infos:
		action += "\n    `%s` %s%s%s%s%s%s%s," % [ 
			i["Column Name"],
			type_string(i["Data Type"]),
			" NOT NULL" if i["NN"] else "",
			" AUTO_INCREMENT" if i["AI"] else "",
			" UNIQUE" if i["UQ"] else "",
			" INDEX" if i.Index else "",
			(" DEFAULT %s" % i["Default(Expression)"]) if i["Default(Expression)"] != "" else "",
			" COMMENT '%s'" % (i["Comment"] as String).c_escape() if i["Comment"] != "" else ""
		]
		if i["PK"]:
			primarys.push_back(i["Column Name"])
	action += "\n    PRIMARY KEY (%s)\n)" % ",".join(primarys.map(func(v): return "`%s`" % v))
	action += ";" if comment.is_empty() else " COMMENT '%s';" % comment.c_escape()
	
	# 检查是否有重复的字段
	var exist_col = {}
	for i in column_infos:
		if exist_col.has(i["Column Name"]):
			msgs.push_back(tr("Duplicate column [%s].") % i["Column Name"])
			mgr.add_log_history.emit("Err", begin_time, action, msgs)
			return mgr.create_accept_dialog(msgs)
			
		exist_col[i["Column Name"]] = true
		
	if not mgr.databases.has(db_name):
		msgs.push_back(tr("Failed! Database %s not exists!") % db_name)
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	var db_dek = GDSQL.RootConfig.get_database_dek64(db_name)
	if db_dek != "" and password != "":
		msgs.push_back(tr("Failed! Database %s is encrypted! Cannot set another password for this table!"))
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	var conf_dir = DirAccess.open(GDSQL.RootConfig.get_database_config_path(db_name))
	if conf_dir == null:
		msgs.push_back(tr("Failed! Cannot open database config dir %s! Err: %s.") \
			% [GDSQL.RootConfig.get_database_config_path(db_name), DirAccess.get_open_error()])
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	if conf_dir.file_exists(table_name + GDSQL.RootConfig.CONFIG_EXTENSION):
		msgs.push_back(tr("Failed! Table conf %s already exist!") % (table_name + GDSQL.RootConfig.CONFIG_EXTENSION))
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	var db_absolute_path = ProjectSettings.globalize_path(GDSQL.RootConfig.get_database_data_path(db_name))
	var table_data_path = ProjectSettings.globalize_path(GDSQL.RootConfig.get_table_data_path(db_name, table_name))
	if not DirAccess.dir_exists_absolute(db_absolute_path):
		var err = DirAccess.make_dir_recursive_absolute(db_absolute_path)
		if err == OK:
			msgs.push_back(tr("Dir: %s has been made.") % db_absolute_path)
		else:
			msgs.push_back(tr("Failed! Cannot make dir %s ! Err: %s.") % [db_absolute_path, err])
			mgr.add_log_history.emit("Err", begin_time, action, msgs)
			return mgr.create_accept_dialog(msgs)
	else:
		if FileAccess.file_exists(table_data_path):
			msgs.push_back(tr("Failed! Data file [%s] already exist!") % table_data_path)
			mgr.add_log_history.emit("Err", begin_time, action, msgs)
			return mgr.create_accept_dialog(msgs)
			
	# 不记录path、database等信息，是方便转移数据表时，直接剪切文件到对应的数据库目录即可（配置文件和数据文件分别到各自目录）
	var dek = "" if password == "" else GDSQL.CryptoUtil.generate_dek()
	var config_file = ConfigFile.new()
	var table_conf_path = GDSQL.RootConfig.get_table_config_path(db_name, table_name)
	config_file.set_value(table_name, "encrypted", "" if dek == "" else GDSQL.CryptoUtil.encrypt_dek(dek, password))
	config_file.set_value(table_name, "comment", comment)
	config_file.set_value(table_name, "valid_if_not_exist", valid_if_not_exist)
	config_file.set_value(table_name, "columns", column_infos)
	config_file.save(table_conf_path)
	msgs.push_back(tr("1 file: %s has been saved.") % table_conf_path)
	
	# 先设置成虚拟的文件，便于首次保存
	GDSQL.ConfManager.mark_valid_if_not_exit(table_data_path)
	GDSQL.ConfManager.get_conf(table_data_path, "") # load data
	if db_dek != "":
		GDSQL.ConfManager.save_conf_by_dek(table_data_path, db_dek)
	elif dek != "":
		GDSQL.ConfManager.save_conf_by_dek(table_data_path, dek)
		GDSQL.RootConfig.set_table_dek(db_name, table_name, dek)
		GDSQL.RootConfig.save()
		msgs.push_back(tr("1 file: %s has been modified.") % GDSQL.RootConfig.path)
	else:
		GDSQL.ConfManager.save(table_data_path)
	if not valid_if_not_exist:
		GDSQL.ConfManager.mark_invalid_if_not_exist(table_data_path)
	msgs.push_back(tr("1 file: %s has been saved.") % table_data_path)
	
	if id != "":
		mgr.sys_confirm_add_table.emit(id)
	mgr.add_log_history.emit("OK", begin_time, action, msgs)
	
	refresh()
	
func modify_db_to_config(old_db_name: String, new_db_name: String, _path: String, id: String) -> void:
	old_db_name = GDSQL.RootConfig.validate_name(old_db_name)
	new_db_name = GDSQL.RootConfig.validate_name(new_db_name)
	var begin_time = Time.get_unix_time_from_system()
	var action = "ALTER DATABASE `%s` RENAME `%s`;" % [old_db_name, new_db_name]
	var msgs = []
	
	if new_db_name == GDSQL.RootConfig.DEK or not (new_db_name.is_valid_ascii_identifier() or new_db_name.is_valid_unicode_identifier()):
		msgs.push_back(tr("Failed! Database name `%s` is invalid!") % new_db_name)
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	if old_db_name == new_db_name:
		msgs.push_back(tr("Nothing changed!"))
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	if not mgr.databases.has(old_db_name):
		msgs.push_back(tr("Database [%s] not exist!") % old_db_name)
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	if mgr.databases.has(new_db_name):
		msgs.push_back(tr("Database's name [%s] has been occupied!") % new_db_name)
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	var old_config_path = GDSQL.RootConfig.get_database_config_path(old_db_name)
	var new_config_path = GDSQL.RootConfig.get_database_config_path(new_db_name)
	var old_data = mgr.databases[old_db_name]
	GDSQL.RootConfig.erase_section(old_db_name)
	GDSQL.RootConfig.set_database_data(new_db_name, old_data["data_path"], old_data["encrypted"])
	GDSQL.RootConfig.save()
	msgs.push_back(tr("1 file: %s has been modified.") % GDSQL.RootConfig.path)
	
	var dir = DirAccess.open(GDSQL.RootConfig.get_base_dir())
	if dir == null:
		msgs.push_back(tr("Failed! Cannot open config root %s dir! Err: %s.") % 
			[GDSQL.RootConfig.get_base_dir(), DirAccess.get_open_error()])
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	if dir.dir_exists(old_config_path):
		var err = dir.rename(old_config_path, new_config_path)
		if err == OK:
			msgs.push_back(tr("1 file: %s has been renamed to %s.") % [old_config_path, new_config_path])
		else:
			msgs.push_back(tr("Failed! Cannot rename dir from %s to %s ! Err: %s.") % [old_config_path, new_config_path, err])
			mgr.add_log_history.emit("Err", begin_time, action, msgs)
			return mgr.create_accept_dialog(msgs)
	else:
		var err = dir.make_dir_recursive(new_config_path)
		if err == OK:
			msgs.push_back(tr("Dir: %s has been made.") % new_config_path)
		else:
			msgs.push_back(tr("Failed! Cannot make dir %s ! Err: %s.") % [new_config_path, err])
			mgr.add_log_history.emit("Err", begin_time, action, msgs)
			return mgr.create_accept_dialog(msgs)
			
	refresh()
	mgr.sys_confirm_alter_schema.emit(id)
	mgr.add_log_history.emit("OK", begin_time, action, msgs)
	
func modify_table_to_config(db_name: String, old_table_name: String, new_table_name, \
		comments: String, valid_if_not_exist: bool, column_infos: Array, id: String) -> void:
	db_name = GDSQL.RootConfig.validate_name(db_name)
	old_table_name = GDSQL.RootConfig.validate_name(old_table_name)
	new_table_name = GDSQL.RootConfig.validate_name(new_table_name)
	var begin_time = Time.get_unix_time_from_system()
	var action = "ALTER TABLE `%s`.`%s` to `%s`.`%s` (" % [db_name, old_table_name, db_name, new_table_name]
	var msgs = []
	var primarys = [] # 不代表支持多主键，只是为了反映用户本身的输入
	for i in column_infos:
		action += "\n    `%s` %s%s%s%s%s%s%s," % [ 
			i["Column Name"],
			type_string(i["Data Type"]),
			" NOT NULL" if i["NN"] else "",
			" AUTO_INCREMENT" if i["AI"] else "",
			" UNIQUE" if i["UQ"] else "",
			" INDEX" if i["Index"] else "",
			(" DEFAULT %s" % i["Default(Expression)"]) if i["Default(Expression)"] != "" else "",
			" COMMENT '%s'" % (i["Comment"] as String).c_escape() if i["Comment"] != "" else ""
		]
		if i["PK"]:
			primarys.push_back(i["Column Name"])
	action += "\n    PRIMARY KEY (%s)\n)" % ",".join(primarys.map(func(v): return "`%s`" % v))
	action += ";" if comments.is_empty() else " COMMENT '%s';" % comments.c_escape()
	
	if primarys.size() != 1:
		msgs.push_back(tr("Multiple primary key or none primary key is not supported!"))
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
	
	if not mgr.databases.has(db_name):
		msgs.push_back(tr("Failed! Database %s not exists!") % db_name)
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	var table_confs = mgr.databases[db_name]["tables"] as Dictionary
	# 没有定义的表怎么办？没影响。
	#if not table_confs.has(old_table_name):
		#var msg = "Failed! table [%s] defination not exist!" % old_table_name
		#mgr.add_log_history.emit("Err", begin_time, action, msg)
		#return mgr.create_accept_dialog(msg)
		
	if new_table_name != old_table_name and table_confs.has(new_table_name):
		msgs.push_back(tr("Failed! Table [%s] name has been occupied!") % new_table_name)
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	var old_table_data_path = GDSQL.RootConfig.get_table_data_path(db_name, old_table_name)
	var new_table_data_path = GDSQL.RootConfig.get_table_data_path(db_name, new_table_name)
	if not FileAccess.file_exists(old_table_data_path):
		var config_file = ConfigFile.new()
		var table_conf_path = GDSQL.RootConfig.get_table_config_path(db_name, new_table_name)
		config_file.set_value(new_table_name, "encrypted", table_confs[old_table_name]["encrypted"]) # 保留原密码
		config_file.set_value(new_table_name, "comment", comments)
		config_file.set_value(new_table_name, "valid_if_not_exist", valid_if_not_exist)
		config_file.set_value(new_table_name, "columns", column_infos)
		config_file.save(table_conf_path) # 如果新路径和旧路径一致，就会覆盖掉，也是我们所期待的
		msgs.push_back(tr("1 file: %s has been saved.") % table_conf_path)
		
		if old_table_data_path != new_table_data_path:
			var old_table_conf_path = GDSQL.RootConfig.get_table_config_path(db_name, old_table_name)
			var old_table_conf_path_abs = ProjectSettings.globalize_path(old_table_conf_path)
			if FileAccess.file_exists(old_table_conf_path_abs):
				OS.move_to_trash(old_table_conf_path_abs) # 删配置
				msgs.push_back(tr("1 file: %s has been moved to trash.") % old_table_conf_path_abs)
				
		refresh()
		mgr.sys_confirm_alter_table.emit(id)
		mgr.add_log_history.emit("OK", begin_time, action, msgs)
		return
		
	if new_table_data_path != old_table_data_path and FileAccess.file_exists(new_table_data_path):
		msgs.push_back(tr("Failed! File [%s] already exist!") % new_table_data_path)
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	# 检查是否有重复的字段
	var exist_col = {}
	for i in column_infos:
		if exist_col.has(i["Column Name"]):
			var msg = tr("Duplicate Column [%s].") % i["Column Name"]
			mgr.add_log_history.emit("Err", begin_time, action, msg)
			return mgr.create_accept_dialog(msg)
			
		exist_col[i["Column Name"]] = true
		
	# 注意，这里随便传了一个密码，因为实际操作中用户已经输入过密码了，__CONF_MANAGER后续会从缓存中获取，无需再次输入密码
	var old_table_data_file = GDSQL.ConfManager.get_conf(old_table_data_path, "")
	var old_values = old_table_data_file.get_all_section_values() # 数据表中的旧数据
	var warnings = []
	# 数据为空就没必要检查字段了
	if not old_values.is_empty():
		var old_columns = table_confs.get(old_table_name, {}).get("columns", [])
		var old_columns_map = {} # 转成map
		for i in old_columns:
			old_columns_map[i["Column Name"]] = i
			
		for i in column_infos:
			var col_name = i["Column Name"]
			
			if old_columns_map.has(col_name):
				# 检查字段类型发生变化
				if old_columns_map[col_name]["Data Type"] != i["Data Type"]:
					warnings.push_back(tr("Column [%s] data type changed from [%s] to [%s], datas will be converted!") % \
						[col_name, type_string(old_columns_map[col_name]["Data Type"]), type_string(i["Data Type"])])
					for j: Dictionary in old_values:
						j[col_name] = type_convert(j[col_name], i["Data Type"])
						# type_convert
						# https://github.com/godotengine/godot/pull/70080
				# 检查自增
				if not old_columns_map[col_name]["AI"] and i["AI"]:
					if not [TYPE_INT, TYPE_FLOAT].has(i["Data Type"]):
						msgs.push_back(tr("Column [%s] data type must be int or float to support auto increment!") % col_name)
						mgr.add_log_history.emit("Err", begin_time, action, msgs)
						return mgr.create_accept_dialog(msgs)
						
					for j: Dictionary in old_values:
						if not [TYPE_INT, TYPE_FLOAT].has(typeof(j[col_name])):
							msgs.push_back(
								tr("Old datas' field [%s] are not int or float, cannot support auto increment!") % col_name)
							mgr.add_log_history.emit("Err", begin_time, action, msgs)
							return mgr.create_accept_dialog(msgs)
				# 检查主键
				if i["PK"]:
					# 唯一
					var exist = {}
					for j: Dictionary in old_values:
						if exist.has(j[col_name]):
							msgs.push_back(tr("Old datas have duplicate value of primary key [%s]!") % col_name)
							mgr.add_log_history.emit("Err", begin_time, action, msgs)
							return mgr.create_accept_dialog(msgs)
							
						exist[j[col_name]] = true
						
				# 检查唯一
				if i["UQ"]:
					var exist = {}
					for j: Dictionary in old_values:
						if exist.has(j[col_name]):
							msgs.push_back(tr("Old datas have duplicate value of unique key [%s]!") % col_name)
							mgr.add_log_history.emit("Err", begin_time, action, msgs)
							return mgr.create_accept_dialog(msgs)
							
						exist[j[col_name]] = true
				# 检查非null
				if i["NN"]:
					for j: Dictionary in old_values:
						if j[col_name] == null:
							msgs.push_back(tr("Old datas have NULL value of not null key [%s]!") % col_name)
							mgr.add_log_history.emit("Err", begin_time, action, msgs)
							return mgr.create_accept_dialog(msgs)
							
	var apply = func() -> void:
		
		var new_table_data_file = old_table_data_file if old_table_data_path == new_table_data_path \
			else GDSQL.ConfManager.create_conf(new_table_data_path, "")
		new_table_data_file._clear()
		
		for i: Dictionary in old_values:
			var primary_value = str(i[primarys[0]])
			for c in column_infos:
				var col_name = c["Column Name"]
				var default_value = null
				if not (c["Default(Expression)"] as String).strip_edges().is_empty():
					default_value = GDSQL.GDSQLUtils.evaluate_command(null, c["Default(Expression)"])
				if default_value == null:
					default_value = GDSQL.DataTypeDef.DEFUALT_VALUES[c["Data Type"]]
				new_table_data_file.set_value(primary_value, col_name, i.get(col_name, default_value))
				
		GDSQL.ConfManager.save_conf_by_same_password_or_dek(new_table_data_path, old_table_data_path)
		msgs.push_back(tr("1 file: %s has been saved.") % new_table_data_path)
		if new_table_data_path != old_table_data_path:
			GDSQL.ConfManager.remove_conf(old_table_data_path)
			_password_correct.erase(old_table_data_path)
			
		var config_file = ConfigFile.new()
		var table_conf_path = GDSQL.RootConfig.get_table_config_path(db_name, new_table_name)
		config_file.set_value(new_table_name, "encrypted", table_confs[old_table_name]["encrypted"]) # 保留原密码
		config_file.set_value(new_table_name, "comment", comments)
		config_file.set_value(new_table_name, "valid_if_not_exist", valid_if_not_exist)
		config_file.set_value(new_table_name, "columns", column_infos)
		config_file.save(table_conf_path) # 如果新路径和旧路径一致，就会覆盖掉，也是我们所期待的
		msgs.push_back(tr("1 file: %s has been saved.") % table_conf_path)
		
		# 设置缓存
		new_table_data_file.set_indexed_props(column_infos.filter(func(v): return v.Index).map(func(v):
			return v["Column Name"]
		))
		
		if old_table_data_path != new_table_data_path:
			var old_table_conf_path = GDSQL.RootConfig.get_table_config_path(db_name, old_table_name)
			var old_table_conf_path_abs = ProjectSettings.globalize_path(old_table_conf_path)
			var old_table_data_path_abs = ProjectSettings.globalize_path(old_table_data_path)
			if FileAccess.file_exists(old_table_conf_path_abs):
				OS.move_to_trash(old_table_conf_path_abs) # 删配置
				msgs.push_back(tr("1 file: %s has been moved to trash.") % old_table_conf_path_abs)
			if FileAccess.file_exists(old_table_data_path_abs):
				OS.move_to_trash(old_table_data_path_abs) # 删数据
				msgs.push_back(tr("1 file: %s has been moved to trash.") % old_table_data_path_abs)
				
		refresh()
		mgr.sys_confirm_alter_table.emit(id)
		mgr.add_log_history.emit("OK", begin_time, action, msgs)
		
	if warnings.is_empty():
		apply.call()
	else:
		mgr.create_confirmation_dialog("\n".join(warnings), apply)
		
## set password for a non-enctyped database
func set_password_for_database(db_name: String, password: String) -> void:
	db_name = GDSQL.RootConfig.validate_name(db_name)
	var begin_time = Time.get_unix_time_from_system()
	var action = "ALTER DATABASE `%s` SET PASSWORD" % db_name
	var msgs = []
	
	if password == "":
		msgs.push_back(tr("Failed! Password is empty!"))
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	if not mgr.databases.has(db_name):
		msgs.push_back(tr("Failed! Database %s not exists!") % db_name)
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	for table_name in mgr.databases[db_name]["tables"]:
		if mgr.databases[db_name]["tables"][table_name]["encrypted"] != "":
			msgs.push_back(tr("Failed! Table %s.%s is already encrypted! Must clear its password first!") % [db_name, table_name])
			mgr.add_log_history.emit("Err", begin_time, action, msgs)
			return mgr.create_accept_dialog(msgs)
			
	var dek = GDSQL.CryptoUtil.generate_dek()
	var old_data = mgr.databases[db_name]
	GDSQL.RootConfig.erase_section(db_name)
	GDSQL.RootConfig.set_database_data(db_name, old_data["data_path"], GDSQL.CryptoUtil.encrypt_dek(dek, password))
	GDSQL.RootConfig.set_database_dek(db_name, dek)
	GDSQL.RootConfig.save()
	msgs.push_back(tr("1 file: %s has been modified.") % GDSQL.RootConfig.path)
	
	for table_name in mgr.databases[db_name]["tables"]:
		var table_data_path = GDSQL.RootConfig.get_table_data_path(db_name, table_name)
		var table_data_file_exist = FileAccess.file_exists(table_data_path)
		if table_data_file_exist:
			GDSQL.ConfManager.get_conf(table_data_path, "") # load data
			GDSQL.ConfManager.save_conf_by_dek(table_data_path, dek)
			msgs.push_back(tr("1 file: %s has been encrypted.") % table_data_path)
			
		# 清除该表数据的缓存，可以让用户使用该表时必须输入密码，以加深印象
		GDSQL.ConfManager.remove_conf(table_data_path)
		_password_correct.erase(table_data_path)
		
	_password_correct.erase(GDSQL.RootConfig.get_database_data_path(db_name))
	
	mgr.add_log_history.emit("OK", begin_time, action, msgs)
	refresh()
	
## clear password for an encrypted database
func clear_password_for_database(db_name: String) -> void:
	db_name = GDSQL.RootConfig.validate_name(db_name)
	var begin_time = Time.get_unix_time_from_system()
	var action = "ALTER DATABASE `%s` CLEAR PASSWORD" % db_name
	var msgs = []
	
	if not mgr.databases.has(db_name):
		msgs.push_back(tr("Failed! Database %s not exists!") % db_name)
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	if mgr.databases[db_name]["encrypted"] == "":
		msgs.push_back(tr("Failed! Database %s is not encrypted! No need to clear password.") % db_name)
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	var old_data = mgr.databases[db_name]
	GDSQL.RootConfig.erase_section(db_name)
	GDSQL.RootConfig.set_database_data(db_name, old_data["data_path"], "")
	GDSQL.RootConfig.set_database_dek(db_name, null)
	GDSQL.RootConfig.save()
	msgs.push_back(tr("1 file: %s has been modified.") % GDSQL.RootConfig.path)
	
	for table_name in mgr.databases[db_name]["tables"]:
		var table_data_path = GDSQL.RootConfig.get_table_data_path(db_name, table_name)
		var table_data_file_exist = FileAccess.file_exists(table_data_path)
		
		# 注意，这里随便传了一个密码，因为实际操作中用户已经输入过密码了，__CONF_MANAGER后续会从缓存中获取，无需再次输入密码
		if table_data_file_exist:
			GDSQL.ConfManager.get_conf(table_data_path, "") # load data 以防万一上面说的“实际操作。。。”并未发生
			GDSQL.ConfManager.save_conf_by_password(table_data_path, "")
			msgs.push_back(tr("1 file: %s has been decrypted.") % table_data_path)
			_password_correct.erase(table_data_path)
			
	_password_correct.erase(GDSQL.RootConfig.get_database_data_path(db_name))
	
	mgr.add_log_history.emit("OK", begin_time, action, msgs)
	refresh()
	
## change password for an enctyped table
func change_password_for_database(db_name: String, password: String) -> void:
	db_name = GDSQL.RootConfig.validate_name(db_name)
	var begin_time = Time.get_unix_time_from_system()
	var action = "ALTER DATABASE `%s` CHANGE PASSWORD" % db_name
	var msgs = []
	
	if password == "":
		msgs.push_back(tr("Failed! Password is empty!"))
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	if not mgr.databases.has(db_name):
		msgs.push_back(tr("Failed! Database %s not exists!") % db_name)
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	if mgr.databases[db_name]["encrypted"] == "":
		msgs.push_back(tr("Failed! Database %s is not encrypted!") % db_name)
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	var old_data = mgr.databases[db_name]
	# 修改密码不会导致dek变化，所以文件也不变化，变化的是dek的加密字符串，这样达到最大效率。
	var dek = GDSQL.RootConfig.get_database_dek64(db_name)
	if dek == "":
		msgs.push_back(tr("Failed! Dek of %s should not be empty!") % db_name)
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	GDSQL.RootConfig.erase_section(db_name)
	GDSQL.RootConfig.set_database_data(db_name, old_data["data_path"], GDSQL.CryptoUtil.encrypt_dek(dek, password))
	GDSQL.RootConfig.save()
	msgs.push_back(tr("1 file: %s has been modified.") % GDSQL.RootConfig.path)
	
	# 修改密码不会导致dek变化，所以文件也不变化，变化的是dek的加密字符串，这样达到最大效率。
	# 因此这里不会把数据文件重新加密。
	for table_name in mgr.databases[db_name]["tables"]:
		var table_data_path = GDSQL.RootConfig.get_table_data_path(db_name, table_name)
		GDSQL.ConfManager.remove_conf(table_data_path)
		_password_correct.erase(table_data_path)
		
	# 清除该数据库密码记录，可以让用户使用该数据库时必须输入密码，以加深印象
	_password_correct.erase(GDSQL.RootConfig.get_database_data_path(db_name))
	
	mgr.add_log_history.emit("OK", begin_time, action, msgs)
	refresh()
	
## set password for a non-enctyped table
func set_password(db_name: String, table_name: String, password: String) -> void:
	db_name = GDSQL.RootConfig.validate_name(db_name)
	table_name = GDSQL.RootConfig.validate_name(table_name)
	var begin_time = Time.get_unix_time_from_system()
	var action = "ALTER TABLE `%s`.`%s` SET PASSWORD" % [db_name, table_name]
	var msgs = []
	
	if password == "":
		msgs.push_back(tr("Failed! Password is empty!"))
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	if not mgr.databases.has(db_name):
		msgs.push_back(tr("Failed! Database %s not exists!") % db_name)
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	if mgr.databases[db_name]["encrypted"] != "":
		msgs.push_back(tr("Failed! Database %s is already encrypted!") % db_name)
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	if not mgr.databases[db_name]["tables"].has(table_name):
		msgs.push_back(tr("Failed! Table %s.%s not exists!") % [db_name, table_name])
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	if mgr.databases[db_name]["tables"][table_name]["encrypted"] != "":
		msgs.push_back(tr("Failed! Table %s.%s is already encrypted!") % [db_name, table_name])
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	var table_conf_path = GDSQL.RootConfig.get_table_config_path(db_name, table_name)
	if not FileAccess.file_exists(table_conf_path):
		msgs.push_back(tr("Failed! Table conf %s does not exist!") % table_conf_path)
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	var table_data_path = ProjectSettings.globalize_path(GDSQL.RootConfig.get_table_data_path(db_name, table_name))
	var table_data_file_exist = FileAccess.file_exists(table_data_path)
	#if not FileAccess.file_exists(table_data_path):
		#msgs.push_back("Failed! Data file [%s] dose not exist!" % table_data_path)
		#mgr.add_log_history.emit("Err", begin_time, action, msgs)
		#return mgr.create_accept_dialog(msgs)
		
	var dek = GDSQL.CryptoUtil.generate_dek()
	var config_file = ConfigFile.new()
	config_file.load(table_conf_path)
	config_file.set_value(table_name, "encrypted", GDSQL.CryptoUtil.encrypt_dek(dek, password))
	config_file.save(table_conf_path)
	msgs.push_back(tr("1 file: %s has been saved.") % table_conf_path)
	
	GDSQL.RootConfig.set_table_dek(db_name, table_name, dek)
	GDSQL.RootConfig.save()
	msgs.push_back(tr("1 file: %s has been modified.") % GDSQL.RootConfig.path)
	
	if table_data_file_exist:
		GDSQL.ConfManager.get_conf(table_data_path, "") # load data
		GDSQL.ConfManager.save_conf_by_dek(table_data_path, dek)
		msgs.push_back(tr("1 file: %s has been encrypted.") % table_data_path)
		
	# 清除该表数据的缓存，可以让用户使用该表时必须输入密码，以加深印象
	GDSQL.ConfManager.remove_conf(table_data_path)
	_password_correct.erase(table_data_path)
	
	mgr.add_log_history.emit("OK", begin_time, action, msgs)
	refresh()
	
## clear password for an encrypted table
func clear_password(db_name: String, table_name: String) -> void:
	db_name = GDSQL.RootConfig.validate_name(db_name)
	table_name = GDSQL.RootConfig.validate_name(table_name)
	var begin_time = Time.get_unix_time_from_system()
	var action = "ALTER TABLE `%s`.`%s` CLEAR PASSWORD" % [db_name, table_name]
	var msgs = []
	
	if not mgr.databases.has(db_name):
		msgs.push_back(tr("Failed! Database %s not exists!") % db_name)
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	if not mgr.databases[db_name]["tables"].has(table_name):
		msgs.push_back(tr("Failed! Table %s.%s not exists!") % [db_name, table_name])
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	if mgr.databases[db_name]["tables"][table_name]["encrypted"] == "":
		msgs.push_back(tr("Failed! Table %s.%s is not encrypted! No need to clear password.") % [db_name, table_name])
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	var table_conf_path = GDSQL.RootConfig.get_table_config_path(db_name, table_name)
	if not FileAccess.file_exists(table_conf_path):
		msgs.push_back(tr("Failed! Table conf %s does not exist!") % table_conf_path)
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	var table_data_path = ProjectSettings.globalize_path(GDSQL.RootConfig.get_table_data_path(db_name, table_name))
	var table_data_file_exist = FileAccess.file_exists(table_data_path)
	#if not FileAccess.file_exists(table_data_path):
		#msgs.push_back("Failed! Data file [%s] dose not exist!" % table_data_path)
		#mgr.add_log_history.emit("Err", begin_time, action, msgs)
		#return mgr.create_accept_dialog(msgs)
		
	var dek = GDSQL.RootConfig.get_table_dek64(db_name, table_name)
	if dek == "":
		msgs.push_back(tr("Failed! Dek of %s.%s should not be empty!") % [db_name, table_name])
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	var config_file = ConfigFile.new()
	config_file.load(table_conf_path)
	config_file.set_value(table_name, "encrypted", "")
	config_file.save(table_conf_path)
	msgs.push_back(tr("1 file: %s has been saved.") % table_conf_path)
	
	GDSQL.RootConfig.set_table_dek(db_name, table_name, null)
	GDSQL.RootConfig.save()
	msgs.push_back(tr("1 file: %s has been modified.") % GDSQL.RootConfig.path)
	
	# 注意，这里随便传了一个密码，因为实际操作中用户已经输入过密码了，__CONF_MANAGER后续会从缓存中获取，无需再次输入密码
	if table_data_file_exist:
		GDSQL.ConfManager.get_conf(table_data_path, "") # load data 以防万一上面说的“实际操作。。。”并未发生
		GDSQL.ConfManager.save_conf_by_password(table_data_path, "")
		msgs.push_back(tr("1 file: %s has been decrypted.") % table_data_path)
		
		_password_correct.erase(table_data_path)
		
	mgr.add_log_history.emit("OK", begin_time, action, msgs)
	refresh()
	
## change password for an enctyped table
func change_password(db_name: String, table_name: String, password: String) -> void:
	db_name = GDSQL.RootConfig.validate_name(db_name)
	table_name = GDSQL.RootConfig.validate_name(table_name)
	var begin_time = Time.get_unix_time_from_system()
	var action = "ALTER TABLE `%s`.`%s` CHANGE PASSWORD" % [db_name, table_name]
	var msgs = []
	
	if password == "":
		msgs.push_back(tr("Failed! Password is empty!"))
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	if not mgr.databases.has(db_name):
		msgs.push_back(tr("Failed! Database %s not exists!") % db_name)
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	if not mgr.databases[db_name]["tables"].has(table_name):
		msgs.push_back(tr("Failed! Table %s.%s not exists!") % [db_name, table_name])
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	if mgr.databases[db_name]["tables"][table_name]["encrypted"] == "":
		msgs.push_back(tr("Failed! Table %s.%s is not encrypted!") % [db_name, table_name])
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	var table_conf_path = GDSQL.RootConfig.get_table_config_path(db_name, table_name)
	if not FileAccess.file_exists(table_conf_path):
		msgs.push_back(tr("Failed! Table conf %s does not exist!") % table_conf_path)
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	var table_data_path = ProjectSettings.globalize_path(GDSQL.RootConfig.get_table_data_path(db_name, table_name))
	#var table_data_file_exist = FileAccess.file_exists(table_data_path)
	#if not FileAccess.file_exists(table_data_path):
		#msgs.push_back("Failed! Data file [%s] dose not exist!" % table_data_path)
		#mgr.add_log_history.emit("Err", begin_time, action, msgs)
		#return mgr.create_accept_dialog(msgs)
		
	var dek = GDSQL.RootConfig.get_table_dek64(db_name, table_name)
	if dek == "":
		msgs.push_back(tr("Failed! Dek of %s.%s should not be empty!") % [db_name, table_name])
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	var config_file = ConfigFile.new()
	config_file.load(table_conf_path)
	config_file.set_value(table_name, "encrypted", GDSQL.CryptoUtil.encrypt_dek(dek, password))
	config_file.save(table_conf_path)
	msgs.push_back(tr("1 file: %s has been saved.") % table_conf_path)
	
	# 修改密码不会导致dek变化，所以文件也不变化，变化的是dek的加密字符串，这样达到最大效率。
	# 因此这里不会把数据文件重新加密。
	# 清除该表数据的缓存，可以让用户使用该表时必须输入密码，以加深印象
	GDSQL.ConfManager.remove_conf(table_data_path)
	_password_correct.erase(table_data_path)
	
	mgr.add_log_history.emit("OK", begin_time, action, msgs)
	refresh()
	
func drop_db_from_config(db_name: String) -> void:
	db_name = GDSQL.RootConfig.validate_name(db_name)
	var begin_time = Time.get_unix_time_from_system()
	var action = "Drop Schema %s;" % db_name
	
	if not mgr.databases.has(db_name):
		var content = tr("Database: %s not exist!") % db_name
		mgr.add_log_history.emit("Err", begin_time, action, content)
		return mgr.create_accept_dialog(content)
		
	if _default_database_path == GDSQL.RootConfig.get_database_data_path(db_name):
		_default_database_path = ""
		
	var dek = GDSQL.RootConfig.get_database_dek64(db_name)
	if dek != "":
		# In case user want to revert but don't know the dek.
		var tmp_file_path = "user://%s.%s.%s.dek" % [db_name, 
			Time.get_datetime_string_from_system(false, true).to_snake_case().replace(":", "_").validate_filename()]
		var file = FileAccess.open(tmp_file_path, FileAccess.WRITE)
		file.store_string(dek)
		file.flush()
		file.close()
		OS.move_to_trash(ProjectSettings.globalize_path(tmp_file_path))
		
	GDSQL.RootConfig.set_database_dek(db_name, null)
	GDSQL.RootConfig.erase_database(db_name)
	GDSQL.RootConfig.save()
	var msg = tr("1 file: %s has been modified") % GDSQL.RootConfig.path
	mgr.add_log_history.emit("OK", begin_time, action, msg)
	
	refresh()
	# TODO notify mapper graph
	
func drop_table_from_config(db_name: String, table_name: String) -> void:
	db_name = GDSQL.RootConfig.validate_name(db_name)
	table_name = GDSQL.RootConfig.validate_name(table_name)
	var begin_time = Time.get_unix_time_from_system()
	var action = "Drop table `%s`.`%s`;" % [db_name, table_name]
	var msgs = []
	
	if not mgr.databases.has(db_name):
		var content = tr("Database: %s not exist!") % db_name
		mgr.add_log_history.emit("Err", begin_time, action, content)
		return mgr.create_accept_dialog(content)
		
	if not mgr.databases[db_name]["tables"].has(table_name):
		var content = tr("Table: `%s`.`%s` not exist!") % [db_name, table_name]
		mgr.add_log_history.emit("Err", begin_time, action, content)
		return mgr.create_accept_dialog(content)
		
	# remove config file
	var table_conf_path = GDSQL.RootConfig.get_table_config_path(db_name, table_name)
	var conf_path = ProjectSettings.globalize_path(table_conf_path)
	if FileAccess.file_exists(table_conf_path):
		OS.move_to_trash(conf_path)
		msgs.push_back(tr("1 file: %s has been moved to trash.") % conf_path)
	else:
		msgs.push_back(tr("1 file: %s could not be found when attempting to move to trash.") % conf_path)
	GDSQL.ConfManager.remove_conf(table_conf_path)
	
	# remove data file
	var data_path = ProjectSettings.globalize_path(GDSQL.RootConfig.get_table_data_path(db_name, table_name))
	if FileAccess.file_exists(data_path):
		OS.move_to_trash(data_path)
		msgs.push_back(tr("1 file: %s has been moved to trash.") % data_path)
	else:
		msgs.push_back(tr("1 file: %s could not be found when attempting to move to trash.") % data_path)
		
	var dek = GDSQL.RootConfig.get_table_dek64(db_name, table_name)
	if dek != "":
		# In case user want to revert but don't know the dek.
		var tmp_file_path = "user://%s.%s.%s.dek" % [db_name, table_name, 
			Time.get_datetime_string_from_system(false, true).to_snake_case().replace(":", "_").validate_filename()]
		var file = FileAccess.open(tmp_file_path, FileAccess.WRITE)
		file.store_string(dek)
		file.flush()
		file.close()
		OS.move_to_trash(ProjectSettings.globalize_path(tmp_file_path))
		
		GDSQL.RootConfig.set_table_dek(db_name, table_name, null)
		GDSQL.RootConfig.save()
		msgs.push_back(tr("1 file: %s has been modified") % GDSQL.RootConfig.path)
		
	GDSQL.ConfManager.remove_conf(data_path)
	_password_correct.erase(data_path)
	
	mgr.add_log_history.emit("OK", begin_time, action, msgs)
	
	refresh()
	mgr.sys_confirm_drop_table.emit(db_name, table_name)
	
func truncate_table_from_config(db_name: String, table_name: String) -> void:
	db_name = GDSQL.RootConfig.validate_name(db_name)
	table_name = GDSQL.RootConfig.validate_name(table_name)
	var begin_time = Time.get_unix_time_from_system()
	var action = "Truncate table `%s`.`%s`;" % [db_name, table_name]
	var msgs = []
	
	if not mgr.databases.has(db_name):
		var content = tr("Database: %s not exist!") % db_name
		mgr.add_log_history.emit("Err", begin_time, action, content)
		return mgr.create_accept_dialog(content)
		
	if not mgr.databases[db_name]["tables"].has(table_name):
		var content = tr("Table: `%s`.`%s` not exist!") % [db_name, table_name]
		mgr.add_log_history.emit("Err", begin_time, action, content)
		return mgr.create_accept_dialog(content)
		
	# clear data file
	var data_path = ProjectSettings.globalize_path(GDSQL.RootConfig.get_table_data_path(db_name, table_name))
	if FileAccess.file_exists(data_path):
		OS.move_to_trash(data_path) # users can get their old data file in trash can
		msgs.push_back(tr("1 file: %s has been moved to trash.") % data_path)
	else:
		msgs.push_back(tr("1 file: %s could not be found when attempting to move to trash.") % data_path)
		
	# create empty file
	var data_file = ConfigFile.new()
	data_file.save(data_path)
	GDSQL.ConfManager.get_conf(data_path, "")._clear()
	
	var dek = GDSQL.RootConfig.get_database_dek64(db_name)
	if dek == "":
		dek = GDSQL.RootConfig.get_table_dek64(db_name, table_name)
	if dek != "":
		GDSQL.ConfManager.save_conf_by_dek(data_path, dek)
	msgs.push_back(tr("1 file: %s has been overwritten with an empty file.") % data_path)
	
	mgr.add_log_history.emit("OK", begin_time, action, msgs)
	
	refresh()
	
func _ready():
	if mgr == null or not mgr.run_in_plugin(self):
		return
		
	set_translation_domain("GDSQL")
	if not mgr.user_confirm_add_schema.is_connected(add_db_to_config):
		mgr.user_confirm_add_schema.connect(add_db_to_config, CONNECT_DEFERRED)
	if not mgr.user_confirm_add_table.is_connected(add_table_to_config):
		mgr.user_confirm_add_table.connect(add_table_to_config, CONNECT_DEFERRED)
	if not mgr.user_confirm_alter_schema.is_connected(modify_db_to_config):
		mgr.user_confirm_alter_schema.connect(modify_db_to_config, CONNECT_DEFERRED)
	if not mgr.user_confirm_alter_table.is_connected(modify_table_to_config):
		mgr.user_confirm_alter_table.connect(modify_table_to_config, CONNECT_DEFERRED)
	if not mgr.request_user_enter_password.is_connected(deal_password_before_table_cmd_2):
		mgr.request_user_enter_password.connect(deal_password_before_table_cmd_2, CONNECT_DEFERRED)
	if not mgr.need_user_enter_password.is_connected(need_password):
		mgr.need_user_enter_password.connect(need_password) # 不能用CONNECT_DEFERRED
	if not mgr.request_drop_table.is_connected(drop_table_from_config):
		mgr.request_drop_table.connect(drop_table_from_config, CONNECT_DEFERRED)
	if not mgr.request_create_table.is_connected(add_table_to_config):
		mgr.request_create_table.connect(add_table_to_config, CONNECT_DEFERRED)
		
	popup_menu_database.set_item_submenu_node(2, popup_menu_copy_to)
	popup_menu_database.set_item_submenu_node(3, popup_menu_send_to)
	popup_menu_database.set_item_submenu_node(8, popup_menu_password)
	popup_menu_tables.set_item_submenu_node(1, popup_menu_create_table_like_tables)
	popup_menu_table_item.set_item_submenu_node(3, popup_menu_copy_to_of_table)
	popup_menu_table_item.set_item_submenu_node(7, popup_menu_send_to_of_table)
	popup_menu_table_item.set_item_submenu_node(10, popup_menu_create_table_like_table_item)
	popup_menu_table_item.set_item_submenu_node(12, popup_menu_password_of_table)
	popup_menu_column.set_item_submenu_node(2, popup_menu_copy_to_of_column)
	popup_menu_column.set_item_submenu_node(3, popup_menu_send_to_of_column)
	refresh()
	
	# 配置变化检测
	disk_changed = ConfirmationDialog.new()
	var vbc = VBoxContainer.new()
	disk_changed.add_child(vbc)
	
	var dl = Label.new()
	dl.text = tr("The following files are newer on disk.\nWhat action should be taken?")
	vbc.add_child(dl)
	
	disk_changed_list = Tree.new()
	vbc.add_child(disk_changed_list)
	disk_changed_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	disk_changed_list.button_clicked.connect(_on_disk_changed_list_button_clicked)
	disk_changed.confirmed.connect(_reload_modified_scenes)
	disk_changed.ok_button_text = tr("Reload")
	add_child(disk_changed)
	
func _on_disk_changed_list_button_clicked(item: TreeItem, _column: int, id: int, _mouse_button_index: int):
	match id:
		0, 1:
			GDSQL.ConfManager.remove_conf(item.get_meta("path"))
			_password_correct.erase(item.get_meta("path"))
			refresh()
		2:
			var path = ProjectSettings.globalize_path(item.get_meta("path"))
			OS.shell_open(path)
		3:
			var path = ProjectSettings.globalize_path(item.get_meta("path"))
			OS.shell_show_in_file_manager(path, true)
			
func _reload_modified_scenes():
	for i in disk_changed_list.get_root().get_child_count():
		var path = disk_changed_list.get_root().get_child(i).get_meta("path")
		GDSQL.ConfManager.remove_conf(path)
		_password_correct.erase(path)
	refresh()
	
func _exit_tree():
	if mgr == null or not mgr.run_in_plugin(self):
		return
		
	_clear()
	if mgr.user_confirm_add_schema.is_connected(add_db_to_config):
		mgr.user_confirm_add_schema.disconnect(add_db_to_config)
	if mgr.user_confirm_add_table.is_connected(add_table_to_config):
		mgr.user_confirm_add_table.disconnect(add_table_to_config)
	if mgr.user_confirm_alter_schema.is_connected(modify_db_to_config):
		mgr.user_confirm_alter_schema.disconnect(modify_db_to_config)
	if mgr.user_confirm_alter_table.is_connected(modify_table_to_config):
		mgr.user_confirm_alter_table.disconnect(modify_table_to_config)
	if mgr.request_user_enter_password.is_connected(deal_password_before_table_cmd_2):
		mgr.request_user_enter_password.disconnect(deal_password_before_table_cmd_2)
	if mgr.need_user_enter_password.is_connected(need_password):
		mgr.need_user_enter_password.disconnect(need_password)
	if mgr.request_drop_table.is_connected(drop_table_from_config):
		mgr.request_drop_table.disconnect(drop_table_from_config)
	if mgr.request_create_table.is_connected(add_table_to_config):
		mgr.request_create_table.disconnect(add_table_to_config)
		
	mgr = null
	
func refresh() -> void:
	_clear()
	refresh_databases()
	root = create_item()
	var collapsed = false
	for db_name in mgr.databases:
		var data = mgr.databases[db_name]
		var db := add_database(db_name, data)
		db.collapsed = collapsed if _default_database_path.is_empty() else _default_database_path != data["data_path"]
		database_items.push_back(db)
		collapsed = true # 在没默认数据库的情况下，除了第一个数据库不折叠，其他都折叠
		
		for table_name in data["tables"]:
			add_table(db, table_name)
			
	# create table like 子菜单重新生成
	var id = 0
	for db_name in mgr.databases:
		var data = mgr.databases[db_name]
		if !data["tables"].is_empty():
			popup_menu_create_table_like_tables.add_separator("SCHEMA：%s" % db_name, id)
			popup_menu_create_table_like_table_item.add_separator("SCHEMA：%s" % db_name, id)
		for t in data["tables"]:
			id += 1
			popup_menu_create_table_like_tables.add_item(t, id)
			var idx_1 = popup_menu_create_table_like_tables.get_item_index(id)
			popup_menu_create_table_like_tables.set_item_metadata(idx_1, {
				"db_name": db_name,
				"table_name": t
			})
			
			popup_menu_create_table_like_table_item.add_item(t, id)
			var idx_2 = popup_menu_create_table_like_table_item.get_item_index(id)
			popup_menu_create_table_like_table_item.set_item_metadata(idx_2, {
				"db_name": db_name,
				"table_name": t
			})
	
func _get_specific_extension_files(path: String, extension: String) -> Array[String]:
	var ret: Array[String] = []
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			# 子目录
			if dir.current_is_dir():
				# print("Found directory: " + file_name)
				pass # 不支持发现子目录里的数据，用户可自行把子目录创建为新的数据库即可
			# 文件
			else:
				if file_name.get_extension().to_lower() == extension:
					ret.push_back(file_name)
					
			file_name = dir.get_next()
		dir.list_dir_end()
	else:
		# 注意：git不能提交空目录，可能是因为这个导致clone下来的代码没有空目录
		# 这种情况下，请自己手动创建个空目录即可
		var msg = "Can not open the path: %s." % path
		EditorInterface.get_editor_toaster().push_toast(msg, EditorToaster.SEVERITY_WARNING)
		push_warning(msg)
		
	return ret

func add_database(db_name: String, data: Dictionary) -> TreeItem:
	var data_path = data["data_path"]
	var database_item = create_item(root)
	database_item.set_auto_translate_mode(0, Node.AUTO_TRANSLATE_MODE_DISABLED)
	database_item.set_text(0, db_name)
	database_item.set_icon(0, load("res://addons/gdsql/img/icon_db.png"))
	database_item.set_icon_max_width(0, 20)
	database_item.set_tooltip_text(0, data_path)
	database_item.set_meta("db_name", db_name)
	database_item.set_meta("data_path", data_path)
	database_item.set_meta("type", "database")
	if data["encrypted"] != "":
		var texture
		var tooltip
		if _password_correct.has(data_path):
			texture = load("res://addons/gdsql/img/unlock.png")
			tooltip = tr("This database is encrypted, and you've entered the correct password.")
		else:
			texture = load("res://addons/gdsql/img/lock.png") 
			tooltip = tr("This database is encrypted. Please enter your password to proceed.")
		database_item.add_button(0, texture, ITEM_BUTTON_INDEX.ENCRYPT, false, tooltip)
	database_item.add_button(0, load("res://addons/gdsql/img/folder.png"), 
		ITEM_BUTTON_INDEX.FOLDER, false, tr("Show in File Manager"))
	if data_path == _default_database_path:
		database_item.set_custom_bg_color(0, Color.BLUE_VIOLET)
		
	var arr := ["Tables", "Views", "Stored Procedures", "Functions"]
	for i in arr.size():
		var item = create_item(database_item)
		item.set_auto_translate_mode(0, Node.AUTO_TRANSLATE_MODE_ALWAYS)
		item.set_text(0, tr(arr[i]))
		item.set_icon(0, load("res://addons/gdsql/img/windows.png"))
		item.set_icon_max_width(0, 16)
		item.set_meta("type", arr[i])
		item.set_meta("db_name", db_name)
		item.set_meta("data_path", data_path)
		if i > 0:
			item.set_collapsed_recursive(true)
			
	return database_item
	
func add_table(db: TreeItem, table_name: String):
	var table_item = create_item(db.get_child(0)) # child 0 是 Tables。其他是Views、Stored Procedures等等
	var file_name = table_name + GDSQL.RootConfig.DATA_EXTENSION
	var db_name = db.get_meta("db_name")
	var data_path = db.get_meta("data_path").path_join(file_name)
	table_item.set_text(0, table_name)
	table_item.set_auto_translate_mode(0, Node.AUTO_TRANSLATE_MODE_DISABLED)
	table_item.set_icon(0, load("res://addons/gdsql/img/table.png"))
	table_item.set_icon_max_width(0, 20)
	table_item.set_tooltip_text(0, file_name)
	if mgr.databases[db_name]["tables"][table_name]["encrypted"] != "":
		var texture
		var tooltip
		if GDSQL.ConfManager.has_conf(data_path) and _password_correct.has(data_path):
			texture = load("res://addons/gdsql/img/unlock.png")
			tooltip = tr("This table is encrypted and you have entered the right password.")
		else:
			texture = load("res://addons/gdsql/img/lock.png") 
			tooltip = tr("This table's data file is encrypted. Enter password before using it.")
		table_item.add_button(0, texture, ITEM_BUTTON_INDEX.ENCRYPT, false, tooltip)
	table_item.add_button(0, load("res://addons/gdsql/img/quick_search.png"), 
		ITEM_BUTTON_INDEX.QUICK_SEARCH, false, "select * from %s.%s;" % [db_name, table_name])
	table_item.set_meta("db_name", db_name)
	table_item.set_meta("table_name", table_name)
	table_item.set_meta("data_path", data_path)
	table_item.set_meta("type", "table")
	table_item.collapsed = true
	
	# TODO 让column可以多选
	# column的子tree
	var table_columns = mgr.databases[db_name]["tables"][table_name]["columns"]
	for col in table_columns:
		var col_item = create_item(table_item)
		var texts = [col["Column Name"]]
		texts.push_back(type_string(col["Data Type"]))
		col_item.set_auto_translate_mode(0, Node.AUTO_TRANSLATE_MODE_DISABLED)
		col_item.set_text(0, ": ".join(texts))
		col_item.set_tooltip_text(0, "Comment: %s\nDefault(Expression): %s" % \
			[col["Comment"], col["Default(Expression)"]])
		col_item.set_icon(0, load("res://addons/gdsql/img/dot.png"))
		col_item.set_meta("db_name", db_name)
		col_item.set_meta("table_name", table_name)
		col_item.set_meta("column_name", col["Column Name"])
		col_item.set_meta("type", "column")
		var properties = ["AI", "NN", "UQ", "PK"]
		var tooltips = ["Auto Increment", "Not NULL", "Uniq", "Primary Key"]
		for i in properties.size():
			if col.get(properties[i], false):
				col_item.add_button(0, load("res://addons/gdsql/img/word_%s.png" \
				% (properties[i] as String).to_lower()), ITEM_BUTTON_INDEX.COLUMN_PROPERTY
				, true, tooltips[i])
		if col.get("Index", false):
			col_item.add_button(0, load("res://addons/gdsql/img/word_in.png"), 
				ITEM_BUTTON_INDEX.COLUMN_PROPERTY, true, tr("Indexed"))
				
func _on_button_clicked(item: TreeItem, column: int, id: int, _mouse_button_index: int) -> void:
	if column == 0:
		match id:
			# Select Rows
			ITEM_BUTTON_INDEX.QUICK_SEARCH:
				var exe_select = func():
					mgr.send_to_editor_and_execute.emit(item.get_meta("table_name"), {
						"cmd": "select",
						"db_name": item.get_meta("db_name"),
						"table_name": item.get_meta("table_name"),
						"fields": "*"
					})
				deal_password_before_table_cmd(item, "", exe_select)
			# Show in File Manager
			ITEM_BUTTON_INDEX.FOLDER:
				var path = ProjectSettings.globalize_path(item.get_meta("data_path"))
				OS.shell_show_in_file_manager(path, true)
			ITEM_BUTTON_INDEX.COLUMN_PROPERTY:
				pass
			ITEM_BUTTON_INDEX.ENCRYPT:
				var item_is_table: bool = item.get_meta("type") == "table"
				var table_name = item.get_meta("table_name") if item_is_table else ""
				var data_path = item.get_meta("data_path")
				deal_password_before_table_cmd_3(item, item.get_meta("db_name"), table_name, 
					data_path, "", Callable(), Callable(), true)
					
func _on_item_activated(item: TreeItem = null) -> void:
	if item == null:
		item = get_item_at_position(get_local_mouse_position())
	if item:
		var need_collapsed = true
		var is_db_item = false
		for db_item in database_items:
			if db_item == item:
				is_db_item = true
				_default_database_path = db_item.get_meta("data_path")
				if db_item.get_custom_bg_color(0) != Color.BLUE_VIOLET:
					db_item.set_custom_bg_color(0, Color.BLUE_VIOLET)
					need_collapsed = false # 双击数据库，优先改背景颜色，改了背景颜色就不折叠，而且直接展开（保持展开）
					db_item.collapsed = false
					
		if is_db_item:
			for db_item in database_items:
				if db_item != item:
					db_item.clear_custom_bg_color(0)
				
		if need_collapsed:
			item.collapsed = !item.collapsed
			
func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var item := get_item_at_position(get_local_mouse_position())
		if item and item.has_meta("type"):
			var popup_menu: PopupMenu
			match item.get_meta("type"):
				"database":
					popup_menu = popup_menu_database
				"Tables":
					popup_menu = popup_menu_tables
				"Views":
					popup_menu = popup_menu_veiws
				"Stored Procedures":
					popup_menu = popup_menu_stored_procedures
				"Functions":
					popup_menu = popup_menu_functions
				"table":
					popup_menu = popup_menu_table_item
				"column":
					popup_menu = popup_menu_column
					
#			printt(DisplayServer.mouse_get_position(), get_viewport().get_mouse_position(), get_window().get_mouse_position())
			popup_menu.position = DisplayServer.mouse_get_position() # 为什么要用这个方法获取鼠标位置？不知道……在插件中该方法是正确的
			popup_menu.popup()
			
func _on_popup_menu_table_item_index_pressed(index: int) -> void:
	match popup_menu_table_item.get_item_text(index):
		"Select Rows":
			var item := get_selected()
			if item:
				var exe_select = func():
					mgr.send_to_editor_and_execute.emit(item.get_meta("table_name"), {
						"cmd": "select",
						"db_name": item.get_meta("db_name"),
						"table_name": item.get_meta("table_name"),
						"fields": "*"
					})
				deal_password_before_table_cmd(item, "", exe_select)
		"Table Inspector":
			var item := get_selected()
			if item:
				mgr.open_table_inspector_tab.emit(item.get_meta("db_name"), item.get_meta("table_name"))
		"Table Data Export Wizard":
			var item := get_selected()
			if item:
				var db_name = item.get_meta("db_name")
				var table_name = item.get_meta("table_name")
				var open_tab = func():
					mgr.open_table_data_export_tab.emit(db_name, table_name)
				deal_password_before_table_cmd(item, "", open_tab)
		"Table Data Import Wizard":
			var item := get_selected()
			if item:
				var db_name = item.get_meta("db_name")
				var table_name = item.get_meta("table_name")
				var open_tab = func():
					mgr.open_table_data_import_tab.emit(db_name, table_name)
				deal_password_before_table_cmd(item, "", open_tab)
		"Create Table...":
			var item := get_selected()
			if item:
				mgr.open_add_table_tab.emit(item.get_meta("db_name"))
		"Alter Table...":
			var item := get_selected()
			if item:
				var db_name = item.get_meta("db_name")
				var table_name = item.get_meta("table_name")
				var open_tab = func():
					mgr.open_alter_table_tab.emit(db_name, table_name)
				deal_password_before_table_cmd(item, "", open_tab)
		"Drop Table...":
			var item := get_selected()
			if item:
				var db_name = item.get_meta("db_name")
				var table_name = item.get_meta("table_name")
				var open_dialog = func():
					mgr.create_confirmation_dialog(
						tr("Are you sure to Drop table `%s`.`%s`? Config file and data file of this table will be moved to trash.") % \
						[db_name, table_name], drop_table_from_config.bind(db_name, table_name))
				deal_password_before_table_cmd(item, "", open_dialog)
		"Truncate Table...":
			var item := get_selected()
			if item:
				var db_name = item.get_meta("db_name")
				var table_name = item.get_meta("table_name")
				var open_dialog = func():
					mgr.create_confirmation_dialog(
						tr("Are you sure to Truncate table `%s`.`%s`?") % \
						[db_name, table_name], truncate_table_from_config.bind(db_name, table_name))
				deal_password_before_table_cmd(item, "", open_dialog)
		"Show in File Manager":
			var item := get_selected()
			if item:
				var path = ProjectSettings.globalize_path(item.get_meta("data_path"))
				OS.shell_show_in_file_manager(path, true)
		"Open in External Program":
			var item := get_selected()
			if item:
				var path = ProjectSettings.globalize_path(item.get_meta("data_path"))
				OS.shell_open(path)
		"Generate Mapper...":
			var item := get_selected()
			if item:
				mgr.open_mapper_graph_tab.emit(make_drag_data(item))
		"Refresh All":
			refresh()
			
func need_password(db_name: String, table_name: String, try_password: String, result: Array = []) -> bool:
	table_name = table_name.get_basename()
	for db_item in root.get_children():
		if db_item.get_meta("db_name") == db_name or \
		db_item.get_meta("data_path") == db_name or \
		db_item.get_meta("data_path") == db_name + "/":
			for collection in db_item.get_children():
				if collection.get_meta("type") == "Tables":
					for table_item in collection.get_children():
						if table_item.get_meta("table_name") == table_name or \
						table_item.get_meta("data_path").get_file() == table_name:
							var ret = _need_password(table_item, try_password)
							result.push_back(ret)
							return ret
	result.push_back(true) # TODO FIXME 没找到db和table? 基于tree的，好像不太好，如果以后支持表筛选的话不就找不到了
	return true
	
func _need_password(table_item: TreeItem, try_password: String) -> bool:
	var db_name = table_item.get_meta("db_name")
	var table_name = table_item.get_meta("table_name")
	var table_path = table_item.get_meta("data_path")
	
	var dek_info = ""
	var path = ""
	var is_db_locked = mgr.databases[db_name]["encrypted"] != ""
	if mgr.databases[db_name]["tables"][table_name]["encrypted"] != "":
		if GDSQL.ConfManager.has_conf(table_path) and _password_correct.has(table_path):
			return false
		dek_info = mgr.databases[db_name]["tables"][table_name]["encrypted"]
		path = table_path
	elif is_db_locked:
		var db_path = GDSQL.RootConfig.get_database_data_path(db_name)
		if _password_correct.has(db_path):
			return false
		dek_info = mgr.databases[db_name]["encrypted"]
		path = db_path
	else:
		return false
		
	if try_password != "":
		var recovered_dek = GDSQL.CryptoUtil.decrypt_dek(dek_info, try_password)
		if recovered_dek == "":
			return true # Wrong password
		# 在内存中load一次表，后续再通过__CONF_MANAGER获取表就不需要密码了
		if not is_db_locked:
			GDSQL.ConfManager.get_conf(table_path, recovered_dek)
		_password_correct[path] = recovered_dek
		return false
	return true
	
func deal_password_before_table_cmd_2(db_name: String, table_name: String, try_password: String, pass_callback: Callable, fail_callabck: Callable = Callable()):
	if not db_name.contains("/"):
		db_name = GDSQL.RootConfig.validate_name(db_name)
	table_name = GDSQL.RootConfig.validate_name(table_name)
	table_name = table_name.get_basename()
	var find_db = false
	var find_table = false
	var possible = []
	for db_item in root.get_children():
		if db_item.get_meta("db_name") == db_name or \
		db_item.get_meta("data_path") == db_name or \
		db_item.get_meta("data_path") == db_name + "/":
			find_db = true
			possible.clear()
			for collection in db_item.get_children():
				if collection.get_meta("type") == "Tables":
					for table_item in collection.get_children():
						if table_item.get_meta("table_name") == table_name or \
						table_item.get_meta("data_path").get_file() == table_name:
							deal_password_before_table_cmd(table_item, try_password, pass_callback, fail_callabck)
							return
						elif table_item.get_meta("table_name").similarity(table_name) >= 0.60:
							possible.push_back(table_item.get_meta("table_name"))
						elif table_item.get_meta("data_path").get_file().similarity(table_name) >= 0.60:
							possible.push_back(table_item.get_meta("data_path"))
							
		elif db_item.get_meta("db_name").similarity(db_name) >= 0.60:
			possible.push_back(db_item.get_meta("db_name"))
		elif db_item.get_meta("data_path").similarity(db_name) >= 0.60:
			possible.push_back(db_item.get_meta("data_path"))
			
	if fail_callabck and fail_callabck.is_valid():
		fail_callabck.call()
		
	if not find_db:
		if possible.is_empty():
			mgr.create_accept_dialog(tr("Not find database `%s`!") % db_name)
		else:
			mgr.create_accept_dialog(tr("Not find database `%s`! Possible database:\n%s?") % [db_name, "\n,".join(possible)])
	elif not find_table:
		if possible.is_empty():
			mgr.create_accept_dialog(tr("Not find table `%s`!") % table_name)
		else:
			mgr.create_accept_dialog(tr("Not find table `%s`! Possible table:\n%s?") % [table_name, "\n,".join(possible)])
			
func deal_password_before_table_cmd(item: TreeItem, try_password: String, pass_callback: Callable, fail_callback: Callable = Callable()):
	var item_is_table: bool = item.get_meta("type") == "table"
	var db_name = item.get_meta("db_name")
	var data_path = item.get_meta("data_path")
	var table_name = item.get_meta("table_name") if item_is_table else ""
	deal_password_before_table_cmd_3(item, db_name, table_name, data_path, try_password, pass_callback, fail_callback)
	
func _switch_item_lock_status(item: TreeItem, lock: bool = true):
	var index = item.get_button_by_id(0, ITEM_BUTTON_INDEX.ENCRYPT)
	if index < 0:
		return
	var tooltip = ""
	var item_is_table: bool = item.get_meta("type") == "table"
	var db_name = item.get_meta("db_name")
	var table_name = item.get_meta("table_name") if item_is_table else ""
	if item_is_table:
		if lock:
			tooltip = tr("This table: %s.%s is encrypted. Please input password of this table.") % [db_name, table_name]
		else:
			tooltip = tr("This table: %s.%s is encrypted and you have entered the right password.") % [db_name, table_name]
	else:
		if lock:
			tooltip = tr("This database: %s is encrypted. Please input password of this databse.") % db_name
		else:
			tooltip = tr("This database: %s is encrypted and you have entered the right password.") % db_name
	var texture = load("res://addons/gdsql/img/lock.png") if lock else load("res://addons/gdsql/img/unlock.png")
	item.set_button(0, index, texture)
	item.set_button_tooltip_text(0, index, tooltip)
	
	if lock:
		if item_is_table:
			_password_correct.erase(GDSQL.RootConfig.get_table_data_path(db_name, table_name))
		else:
			for a_table_name in mgr.databases[db_name]["tables"]:
				var table_data_path = GDSQL.RootConfig.get_table_data_path(db_name, a_table_name)
				GDSQL.ConfManager.remove_conf(table_data_path)
				_password_correct.erase(table_data_path)
			_password_correct.erase(GDSQL.RootConfig.get_database_data_path(db_name))
			
func deal_password_before_table_cmd_3(item: TreeItem, db_name: String, table_name: String, 
data_path: String, try_password: String, pass_callback: Callable, fail_callback: Callable = Callable(),
lock_if_already_passed: bool = false):
	var password_dict_obj = GDSQL.DictionaryObject.new({tr("Password"): ""}, 
		{tr("Password"): {"hint": PROPERTY_HINT_PASSWORD}})
		
	var dek_info = ""
	var msg
	var item_is_table: bool = item.get_meta("type") == "table"
	var is_db_locked = mgr.databases[db_name]["encrypted"] != ""
	if item_is_table and mgr.databases[db_name]["tables"][table_name]["encrypted"] != "":
		if GDSQL.ConfManager.has_conf(data_path) and _password_correct.has(data_path):
			if pass_callback.is_valid():
				pass_callback.call()
			if lock_if_already_passed:
				_switch_item_lock_status(item, true)
			return
		dek_info = mgr.databases[db_name]["tables"][table_name]["encrypted"]
		msg = tr("This table: %s.%s is encrypted. Please input password of this table.") % [db_name, table_name]
	elif is_db_locked:
		var db_path = data_path
		if db_path.ends_with(GDSQL.RootConfig.DATA_EXTENSION):
			db_path = db_path.get_base_dir()
		if _password_correct.has(db_path):
			if pass_callback.is_valid():
				pass_callback.call()
			if lock_if_already_passed:
				_switch_item_lock_status(item.get_parent().get_parent() if item_is_table else item, true)
			return
		dek_info = mgr.databases[db_name]["encrypted"]
		msg = tr("This database: %s is encrypted. Please input password of this databse.") % db_name
	else:
		if pass_callback.is_valid():
			pass_callback.call()
		return
		
	if try_password != "":
		var recovered_dek = GDSQL.CryptoUtil.decrypt_dek(dek_info, try_password)
		if recovered_dek == "":
			msg = tr("Your password is incorrect! Please enter again!")
		else:
			# 在内存中load一次表，后续再通过__CONF_MANAGER获取表就不需要密码了
			if data_path.ends_with(GDSQL.RootConfig.DATA_EXTENSION):
				var conf = GDSQL.ConfManager.get_conf(data_path, recovered_dek)
				if conf == null:
					return
					
				if is_db_locked:
					_password_correct[data_path.get_base_dir()] = recovered_dek
				else:
					_password_correct[data_path] = recovered_dek
			else:
				_password_correct[data_path] = recovered_dek
				
			if item_is_table:
				if is_db_locked:
					_switch_item_lock_status(item.get_parent().get_parent(), false)
				else:
					_switch_item_lock_status(item, false)
			else:
				_switch_item_lock_status(item, false)
			if pass_callback.is_valid():
				pass_callback.call()
			return
			
	var arr: Array[Array] = [
		[msg],
		[password_dict_obj],
	]
	var confirmed = func():
		var recovered_dek = GDSQL.CryptoUtil.decrypt_dek(dek_info, password_dict_obj._get(tr("Password")))
		if recovered_dek != "":
			# 在内存中load一次表，后续再通过__CONF_MANAGER获取表就不需要密码了
			if data_path.ends_with(GDSQL.RootConfig.DATA_EXTENSION):
				var conf = GDSQL.ConfManager.get_conf(data_path, recovered_dek)
				if conf == null:
					return [true, false]
					
				if is_db_locked:
					_password_correct[data_path.get_base_dir()] = recovered_dek
				else:
					_password_correct[data_path] = recovered_dek
			else:
				_password_correct[data_path] = recovered_dek
				
			return [false, true] # false表示让对话框关闭，true表示密码正确
		mgr.create_accept_dialog(tr("Incorrect password!"))
		return [true, false] # true表示让对话框存在，false表示密码错误
		
	var defered = func(clicked_confirm: bool, validation):
		if clicked_confirm:
			if validation is bool and validation == true:
				# 更新锁的图标为打开的样式
				if item_is_table:
					if is_db_locked:
						_switch_item_lock_status(item.get_parent().get_parent(), false)
					else:
						_switch_item_lock_status(item, false)
				else:
					_switch_item_lock_status(item, false)
				# 执行用户传入的函数
				if pass_callback.is_valid():
					pass_callback.call()
				return
		if fail_callback and fail_callback.is_valid():
			fail_callback.call()
			
	mgr.create_custom_dialog(arr, confirmed, Callable(), defered)
	
## Tables目录的create table like子目录的菜单
func _on_popup_menu_create_table_like_tables_index_pressed(index: int) -> void:
	var item = get_selected()
	if item:
		var db_name = item.get_meta("db_name")
		var meta_data = popup_menu_create_table_like_tables.get_item_metadata(index)
		var like_db_name = meta_data["db_name"]
		var like_table_name = meta_data["table_name"]
		deal_password_before_table_cmd_3(item.get_parent(), db_name, "", 
			item.get_meta("data_path"), "",
			mgr.open_add_table_tab.emit.bind(db_name, like_db_name, like_table_name))
			
## Table Item的create table like子目录的菜单
func _on_popup_menu_create_table_like_table_item_index_pressed(index: int) -> void:
	var item = get_selected()
	if item:
		var db_name = item.get_meta("db_name")
		var meta_data = popup_menu_create_table_like_table_item.get_item_metadata(index)
		var like_db_name = meta_data["db_name"]
		var like_table_name = meta_data["table_name"]
		deal_password_before_table_cmd_3(item.get_parent().get_parent(), db_name, "",
			item.get_meta("data_path"), "",
			mgr.open_add_table_tab.emit.bind(db_name, like_db_name, like_table_name))
			
## 数据库目录的右键菜单
func _on_popup_menu_database_index_pressed(index: int) -> void:
	match popup_menu_database.get_item_text(index):
		"Set as Default Schema [Double Click]":
			_on_item_activated(get_selected())
		"Create Schema...":
			mgr.open_add_schema_tab.emit()
		"Alter Schema...":
			var item := get_selected()
			if item:
				deal_password_before_table_cmd(item, "", 
					mgr.open_alter_schema_tab.emit.bind(item.get_meta("db_name"), item.get_meta("data_path")))
		"Drop Schema...":
			var item := get_selected()
			if item:
				var db_name = item.get_meta("db_name")
				var open_dialog = func():
					mgr.create_confirmation_dialog(
						tr("Are you sure you want to drop the database `%s`? For safety purposes, this operation will Not delete the corresponding folder on your operating system. You may delete it manually if needed.")
							% db_name, drop_db_from_config.bind(db_name))
				deal_password_before_table_cmd(item, "", open_dialog)
		"Refresh All":
			refresh()
		_:
			push_error("not support this %s" % popup_menu_database.get_item_text(index))
			
## 在空白位置弹出右键菜单
func _on_empty_clicked(_position: Vector2, mouse_button_index: int) -> void:
	# 右键
	if mouse_button_index == 2:
		popup_menu_empty.position = DisplayServer.mouse_get_position() # 为什么要用这个方法获取鼠标位置？不知道……在插件中该方法是正确的
		popup_menu_empty.popup()
		
## 树的空白位置的右键菜单
func _on_popup_menu_empty_index_pressed(index: int) -> void:
	match popup_menu_empty.get_item_text(index):
		"Create Schema...":
			mgr.open_add_schema_tab.emit()
		"Refresh All":
			refresh()
			
## 数据库“复制到”子菜单
func _on_popup_menu_copy_to_index_pressed(index: int) -> void:
	match popup_menu_copy_to.get_item_text(index):
		"Name":
			var item := get_selected()
			if item:
				DisplayServer.clipboard_set(item.get_meta("db_name"))
		"Config Path":
			var item := get_selected()
			if item:
				DisplayServer.clipboard_set(GDSQL.RootConfig.get_database_config_path(item.get_meta("db_name")))
		"Data Path":
			var item := get_selected()
			if item:
				DisplayServer.clipboard_set(item.get_meta("data_path"))
		"Create Statement":
			var item := get_selected()
			if item:
				var statement = "CREATE DATABASE %s PATH %s;" % [item.get_meta("db_name"), item.get_meta("path")]
				DisplayServer.clipboard_set(statement)
				
## 数据库“发送到”子菜单
func _on_popup_menu_send_to_index_pressed(index: int) -> void:
	match popup_menu_send_to.get_item_text(index):
		"Name":
			var item := get_selected()
			if item:
				mgr.send_to_editor.emit(item.get_meta("db_name"))
		"Path":
			var item := get_selected()
			if item:
				mgr.send_to_editor.emit(item.get_meta("data_path"))
		"Create Statement":
			var item := get_selected()
			if item:
				var statement = "CREATE DATABASE %s PATH %s;" % [item.get_meta("db_name"), item.get_meta("path")]
				mgr.send_to_editor.emit(statement)
				
## Tables目录右键菜单
func _on_popup_menu_tables_index_pressed(index: int) -> void:
	match popup_menu_tables.get_item_text(index):
		"Create Table...":
			var item := get_selected()
			if item:
				mgr.open_add_table_tab.emit(item.get_meta("db_name"))
		"Create Table Like...":
			pass # 子menu实现，所以留空
		"Refresh All":
			refresh()
			
func _on_popup_menu_copy_to_of_table_item_index_pressed(index):
	match popup_menu_copy_to_of_table.get_item_text(index):
		"Name (Short)":
			var item := get_selected()
			if item:
				DisplayServer.clipboard_set(item.get_meta("table_name"))
		"Name (long)":
			var item := get_selected()
			if item:
				var db_name = item.get_meta("db_name")
				var table_name = item.get_meta("table_name")
				DisplayServer.clipboard_set("`%s`.`%s`" % [db_name, table_name])
		"Select All Statement":
			var item := get_selected()
			if item:
				var db_name = item.get_meta("db_name")
				var table_name = item.get_meta("table_name")
				var table_columns = GDSQL.RootConfig.get_table_columns(db_name, table_name)
				var column_names = []
				for i in table_columns:
					column_names.push_back(i["Column Name"])
				var cmd = """
var dao = GDSQL.BaseDao.new()
var ret = dao.use_db("%s")\\
	.set_password("")\\
	.select("%s", true)\\
	.from("%s")\\
	.query()
""" % [db_name, ",".join(column_names), table_name]
				DisplayServer.clipboard_set(cmd)
		"Insert Statement":
			var item := get_selected()
			if item:
				var db_name = item.get_meta("db_name")
				var table_name = item.get_meta("table_name")
				var cmd = """
var dao = GDSQL.BaseDao.new()
var ret = dao.use_db("%s")\\
	.set_password("")\\
	.insert_into("%s")\\
	.values(<data: Dictionary>)\\
	.query()
""" % [db_name, table_name]
				DisplayServer.clipboard_set(cmd)
		"Update Statement":
			var item := get_selected()
			if item:
				var db_name = item.get_meta("db_name")
				var table_name = item.get_meta("table_name")
				var cmd = """
var dao = GDSQL.BaseDao.new()
var ret = dao.use_db("%s")\\
	.set_password("")\\
	.update("%s")\\
	.sets(<data: Dictionary>)\\
	.where(<cond: String>)\\
	.query()
""" % [db_name, table_name]
				DisplayServer.clipboard_set(cmd)
		"Delete Statement":
			var item := get_selected()
			if item:
				var db_name = item.get_meta("db_name")
				var table_name = item.get_meta("table_name")
				var cmd = """
var dao = GDSQL.BaseDao.new()
var ret = dao.use_db("%s")\\
	.set_password("")\\
	.delete_from("%s")\\
	.where(<cond: String>)\\
	.query()
""" % [db_name, table_name]
				DisplayServer.clipboard_set(cmd)
		"Config Path":
			var item := get_selected()
			if item:
				var db_name = item.get_meta("db_name")
				var table_name = item.get_meta("table_name")
				var config_path = GDSQL.RootConfig.get_table_config_path(db_name, table_name)
				DisplayServer.clipboard_set(config_path)
		"Data Path":
			var item := get_selected()
			if item:
				DisplayServer.clipboard_set(item.get_meta("data_path"))
		"Create Statement":
			var item := get_selected()
			if item:
				var statement = "TODO"
				DisplayServer.clipboard_set(statement)
				
func _on_popup_menu_password_index_pressed(index):
	match popup_menu_password_of_table.get_item_text(index):
		"Set Password":
			var item := get_selected()
			if item == null:
				return
				
			var db_name = item.get_meta("db_name")
			var table_name = item.get_meta("table_name")
			
			var password_dict_obj_1 = GDSQL.DictionaryObject.new({tr("Password"): ""}, 
				{tr("Password"): {"hint": PROPERTY_HINT_PASSWORD}})
			var password_dict_obj_2 = GDSQL.DictionaryObject.new({tr("Password"): ""}, 
				{tr("Password"): {"hint": PROPERTY_HINT_PASSWORD, "hint_string": tr("Enter same password agian.")}})
				
			var arr: Array[Array] = [
				[tr("Set password for this table:")],
				[password_dict_obj_1],
				[password_dict_obj_2],
			]
			var confirmed = func():
				if password_dict_obj_1._get(tr("Password")) != password_dict_obj_2._get(tr("Password")):
					mgr.create_accept_dialog(tr("Passwords are different!"))
					return [true, false]
				return [false, true]
				
			var defered = func(clicked_confirm: bool, validation):
				if clicked_confirm:
					if validation is bool and validation == true:
						# 安全起见还是通过检查是否需要用户输入密码再执行后续方法
						deal_password_before_table_cmd(item, "", 
							set_password.bind(db_name, table_name, password_dict_obj_1._get(tr("Password"))))
							
			mgr.create_custom_dialog(arr, confirmed, Callable(), defered)
			
		"Clear Password":
			var item := get_selected()
			if item == null:
				return
				
			var db_name = item.get_meta("db_name")
			var table_name = item.get_meta("table_name")
			
			var password_dict_obj = GDSQL.DictionaryObject.new({tr("Password"): ""}, 
				{tr("Password"): {"hint": PROPERTY_HINT_PASSWORD}})
			var arr: Array[Array] = [
				[tr("Are you sure to clear password for this table?")],
				[tr("Please enter password to apply.")],
				[password_dict_obj],
			]
			var confirmed = func():
				var dek_info = mgr.databases[db_name]["tables"][table_name]["encrypted"]
				var recovered_dek = GDSQL.CryptoUtil.decrypt_dek(dek_info, password_dict_obj._get(tr("Password")))
				if recovered_dek == "":
					mgr.create_accept_dialog(tr("Incorrect password!"))
					return [true, false]
				return [false, true]
				
			var defered = func(clicked_confirm: bool, validation):
				if clicked_confirm:
					if validation is bool and validation == true:
						clear_password(db_name, table_name)
						
			var callback = func():
				mgr.create_custom_dialog(arr, confirmed, Callable(), defered)
				
			deal_password_before_table_cmd(item, "", callback)
			
		"Change Password":
			var item := get_selected()
			if item == null:
				return
				
			var db_name = item.get_meta("db_name")
			var table_name = item.get_meta("table_name")
			
			var password_dict_obj = GDSQL.DictionaryObject.new({tr("oldPassword"): ""}, 
				{tr("oldPassword"): {"hint": PROPERTY_HINT_PASSWORD}})
			var password_dict_obj_1 = GDSQL.DictionaryObject.new({tr("newPassword"): ""}, 
				{tr("newPassword"): {"hint": PROPERTY_HINT_PASSWORD}})
			var password_dict_obj_2 = GDSQL.DictionaryObject.new({tr("newPassword"): ""}, 
				{tr("newPassword"): {"hint": PROPERTY_HINT_PASSWORD, "hint_string": "Enter new password again."}})
			var arr: Array[Array] = [
				[tr("Are you sure to change password for this table?")],
				[password_dict_obj],
				[password_dict_obj_1],
				[password_dict_obj_2],
			]
			var confirmed = func():
				if password_dict_obj_1._get(tr("newPassword")) != password_dict_obj_2._get(tr("newPassword")):
					mgr.create_accept_dialog(tr("The second password entered is not the same as the first one!"))
					return [true, false]
				if password_dict_obj_1._get(tr("newPassword")) == "":
					mgr.create_accept_dialog(tr("New password is empty!"))
					return [true, false]
				var dek_info = mgr.databases[db_name]["tables"][table_name]["encrypted"]
				var recovered_dek = GDSQL.CryptoUtil.decrypt_dek(dek_info, password_dict_obj._get(tr("oldPassword")))
				if recovered_dek == "":
					mgr.create_accept_dialog(tr("Incorrect password!"))
					return [true, false]
				return [false, true]
				
			var defered = func(clicked_confirm: bool, validation):
				if clicked_confirm:
					if validation is bool and validation == true:
						change_password(db_name, table_name, password_dict_obj_1._get(tr("newPassword")))
						
			var callback = func():
				mgr.create_custom_dialog(arr, confirmed, Callable(), defered)
				
			deal_password_before_table_cmd(item, "", callback)
			
## 密码修改相关操作
func _on_popup_menu_password_about_to_popup():
	var item := get_selected()
	if item:
		var db_name = item.get_meta("db_name")
		var table_name = item.get_meta("table_name")
		if mgr.databases[db_name]["tables"][table_name]["encrypted"] == "":
			popup_menu_password_of_table.set_item_disabled(0, false)
			popup_menu_password_of_table.set_item_disabled(1, true)
			popup_menu_password_of_table.set_item_disabled(2, true)
		else:
			popup_menu_password_of_table.set_item_disabled(0, true)
			popup_menu_password_of_table.set_item_disabled(1, false)
			popup_menu_password_of_table.set_item_disabled(2, false)
			
func _on_popup_menu_password_database_index_pressed(index: int) -> void:
	match popup_menu_password_of_table.get_item_text(index):
		"Set Password":
			var item := get_selected()
			if item == null:
				return
				
			var db_name = item.get_meta("db_name")
			
			var password_dict_obj_1 = GDSQL.DictionaryObject.new({tr("Password"): ""}, 
				{tr("Password"): {"hint": PROPERTY_HINT_PASSWORD}})
			var password_dict_obj_2 = GDSQL.DictionaryObject.new({tr("Password"): ""}, 
				{tr("Password"): {"hint": PROPERTY_HINT_PASSWORD, "hint_string": tr("Enter same password agian.")}})
				
			var arr: Array[Array] = [
				[tr("Set password for this database:")],
				[password_dict_obj_1],
				[password_dict_obj_2],
			]
			var confirmed = func():
				if password_dict_obj_1._get(tr("Password")) != password_dict_obj_2._get(tr("Password")):
					mgr.create_accept_dialog(tr("Passwords are different!"))
					return [true, false]
				return [false, true]
				
			var defered = func(clicked_confirm: bool, validation):
				if clicked_confirm:
					if validation is bool and validation == true:
						# 安全起见还是通过检查是否需要用户输入密码再执行后续方法
						deal_password_before_table_cmd(item, "", 
							set_password_for_database.bind(db_name, password_dict_obj_1._get(tr("Password"))))
							
			mgr.create_custom_dialog(arr, confirmed, Callable(), defered)
			
		"Clear Password":
			var item := get_selected()
			if item == null:
				return
				
			var db_name = item.get_meta("db_name")
			
			var password_dict_obj = GDSQL.DictionaryObject.new({tr("Password"): ""}, 
				{tr("Password"): {"hint": PROPERTY_HINT_PASSWORD}})
			var arr: Array[Array] = [
				[tr("Are you sure to clear password for this database?")],
				[tr("Please enter password to apply.")],
				[password_dict_obj],
			]
			var confirmed = func():
				var dek_info = mgr.databases[db_name]["encrypted"]
				var recovered_dek = GDSQL.CryptoUtil.decrypt_dek(dek_info, password_dict_obj._get(tr("Password")))
				if recovered_dek == "":
					mgr.create_accept_dialog(tr("Incorrect password!"))
					return [true, false]
				return [false, true]
				
			var defered = func(clicked_confirm: bool, validation):
				if clicked_confirm:
					if validation is bool and validation == true:
						clear_password_for_database(db_name)
						
			var callback = func():
				mgr.create_custom_dialog(arr, confirmed, Callable(), defered)
				
			deal_password_before_table_cmd(item, "", callback)
			
		"Change Password":
			var item := get_selected()
			if item == null:
				return
				
			var db_name = item.get_meta("db_name")
			
			var password_dict_obj = GDSQL.DictionaryObject.new({tr("oldPassword"): ""}, 
				{tr("oldPassword"): {"hint": PROPERTY_HINT_PASSWORD}})
			var password_dict_obj_1 = GDSQL.DictionaryObject.new({tr("newPassword"): ""}, 
				{tr("newPassword"): {"hint": PROPERTY_HINT_PASSWORD}})
			var password_dict_obj_2 = GDSQL.DictionaryObject.new({tr("newPassword"): ""}, 
				{tr("newPassword"): {"hint": PROPERTY_HINT_PASSWORD, "hint_string": tr("Enter new password again.")}})
			var arr: Array[Array] = [
				[tr("Are you sure you want to change this database's password?")],
				[password_dict_obj],
				[password_dict_obj_1],
				[password_dict_obj_2],
			]
			var confirmed = func():
				if password_dict_obj_1._get(tr("newPassword")) != password_dict_obj_2._get(tr("newPassword")):
					mgr.create_accept_dialog(tr("The second password entered is not the same as the first one!"))
					return [true, false]
				if password_dict_obj_1._get(tr("newPassword")) == "":
					mgr.create_accept_dialog(tr("New password is empty!"))
					return [true, false]
				var dek_info = mgr.databases[db_name]["encrypted"]
				var recovered_dek = GDSQL.CryptoUtil.decrypt_dek(dek_info, password_dict_obj._get(tr("oldPassword")))
				if recovered_dek == "":
					mgr.create_accept_dialog(tr("Incorrect password!"))
					return [true, false]
				return [false, true]
				
			var defered = func(clicked_confirm: bool, validation):
				if clicked_confirm:
					if validation is bool and validation == true:
						change_password_for_database(db_name, password_dict_obj_1._get(tr("newPassword")))
						
			var callback = func():
				mgr.create_custom_dialog(arr, confirmed, Callable(), defered)
				
			deal_password_before_table_cmd(item, "", callback)
			
func _on_popup_menu_password_database_about_to_popup() -> void:
	var item := get_selected()
	if item:
		var db_name = item.get_meta("db_name")
		if mgr.databases[db_name]["encrypted"] == "":
			popup_menu_password.set_item_disabled(0, false)
			popup_menu_password.set_item_disabled(1, true)
			popup_menu_password.set_item_disabled(2, true)
		else:
			popup_menu_password.set_item_disabled(0, true)
			popup_menu_password.set_item_disabled(1, false)
			popup_menu_password.set_item_disabled(2, false)
