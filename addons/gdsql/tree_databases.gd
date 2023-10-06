@tool
extends Tree

var mgr: GDSQLWorkbenchManagerClass = Engine.get_singleton("GDSQLWorkbenchManager")

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

@onready var popup_menu_copy_to_of_table: PopupMenu = $PopupMenuTableItem/PopupMenuCopyTo
@onready var popup_menu_send_to_of_table: PopupMenu = $PopupMenuTableItem/PopupMenuSendTo
@onready var popup_menu_password = $PopupMenuTableItem/PopupMenuPassword

@onready var popup_menu_copy_to_of_column: PopupMenu = $PopupMenuColumn/PopupMenuCopyTo
@onready var popup_menu_send_to_of_column: PopupMenu = $PopupMenuColumn/PopupMenuSendTo

@onready var popup_menu_create_table_like_tables: PopupMenu = $PopupMenuTables/PopupMenuCreateTableLike
@onready var popup_menu_create_table_like_table_item: PopupMenu = $PopupMenuTableItem/PopupMenuCreateTableLike


var root: TreeItem

var databases: Dictionary

var database_items: Array[TreeItem] = []
var _default_database_path: String = ""
var _config_file: ImprovedConfigFile
var __CONF_MANAGER: ConfManagerClass # 管理表数据

const CONFIG_ROOT = "res://addons/gdsql/config/"
const ROOT_CONFIG = "res://addons/gdsql/config/config.cfg"
const CONFIG_EXTENSION = ".cfg"
const DATA_EXTENSION = ".gsql"

enum ITEM_BUTTON_INDEX {
	QUICK_SEARCH = 0,
	FOLDER = 1,
	COLUMN_PROPERTY = 2,
	ENCRYPT = 3,
}

func _clear():
	clear()
	database_items.clear()
	popup_menu_create_table_like_tables.clear()
	popup_menu_create_table_like_table_item.clear()
	
func load_config():
	_config_file = ImprovedConfigFile.new()
	_config_file.load(ROOT_CONFIG)
	
func refresh_databases():
	_config_file.clear()
	_config_file.load(ROOT_CONFIG)
	databases = {}
	for db_name in _config_file.get_sections():
		var config_path = _config_file.get_value(db_name, "config_path")
		databases[db_name] = {
			"data_path": _config_file.get_value(db_name, "data_path"),
			"config_path": config_path,
			"tables": {}
		}
		
		var table_confs = _get_specific_extension_files(config_path, CONFIG_EXTENSION.substr(1))
		for file_name in table_confs:
			var table_conf = ImprovedConfigFile.new()
			table_conf.load(config_path + file_name)
			var table_name = file_name.get_basename()
			databases[db_name]["tables"][table_name] = table_conf.get_section_values(table_name)
			
	mgr.databases = databases
	
	
func add_db_to_config(db_name: String, path: String, id: String) -> void:
	var begin_time = Time.get_unix_time_from_system()
	var action = "CREATE DATABASE %s PATH %s;" % [db_name, path]
	var msgs = []
	
	for a_db_name in databases:
		if a_db_name.to_lower() == db_name.to_lower():
			msgs.push_back("Failed! Database name `%s` has been occupied!" % db_name)
			mgr.add_log_history.emit("Err", begin_time, action, msgs)
			return mgr.create_accept_dialog(msgs)
			
		if databases[a_db_name]["data_path"] == path:
			msgs.push_back("Failed! Database path `%s`(%s) already exist!" % [path, a_db_name])
			mgr.add_log_history.emit("Err", begin_time, action, msgs)
			return mgr.create_accept_dialog(msgs)
			
	var config_path = CONFIG_ROOT + db_name.to_lower().to_snake_case() + "/"
	_config_file.set_value(db_name, "data_path", path)
	_config_file.set_value(db_name, "config_path", config_path)
	_config_file.save(ROOT_CONFIG)
	msgs.push_back("1 file: %s has been modified." % ROOT_CONFIG)
	
	var dir = DirAccess.open(CONFIG_ROOT)
	if dir == null:
		msgs.push_back("Failed! Cannot open config root %s dir! Err: %s." % [CONFIG_ROOT, DirAccess.get_open_error()])
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	if not dir.dir_exists(config_path):
		var err = dir.make_dir_recursive(config_path)
		if err == OK:
			msgs.push_back("dir: %s has been made." % config_path)
		else:
			msgs.push_back("Failed! Cannot make dir %s ! Err: %s." % [config_path, err])
			mgr.add_log_history.emit("Err", begin_time, action, msgs)
			return mgr.create_accept_dialog(msgs)
		
	mgr.sys_confirm_add_schema.emit(id)
	mgr.add_log_history.emit("OK", begin_time, action, msgs)
	
	refresh()
	
	
func add_table_to_config(db_name: String, table_name: String, comment: String, 
	password: String, column_infos: Array, id: String = "") -> void:
	var begin_time = Time.get_unix_time_from_system()
	var action = "CREATE TABLE `%s`.`%s` (" % [db_name, table_name]
	var msgs = []
	var primarys = [] # 不代表支持多主键，只是为了反映用户本身的输入
	for i in column_infos:
		action += "\n    `%s` %s%s%s%s%s%s," % [ 
			i["Column Name"],
			DataTypeDef.DATA_TYPE_NAMES[i["Data Type"]],
			" NOT NULL" if i["NN"] else "",
			" AUTO_INCREMENT" if i["AI"] else "",
			" UNIQUE" if i["UQ"] else "",
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
			msgs.push_back("duplicate field [%s]." % i["Column Name"])
			mgr.add_log_history.emit("Err", begin_time, action, msgs)
			return mgr.create_accept_dialog(msgs)
			
		exist_col[i["Column Name"]] = true
		
	if not databases.has(db_name):
		var msg = "Failed! Database %s not exists!" % db_name
		mgr.add_log_history.emit("Err", begin_time, action, msg)
		return mgr.create_accept_dialog(msg)
		
	var conf_dir = DirAccess.open(databases[db_name]["config_path"])
	if conf_dir == null:
		msgs.push_back("Failed! Cannot open database config dir %s! Err: %s." \
			% [databases[db_name]["config_path"], DirAccess.get_open_error()])
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	if conf_dir.file_exists(table_name + CONFIG_EXTENSION):
		msgs.push_back("Failed! Table conf %s already exist!" % (table_name + CONFIG_EXTENSION))
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	var db_absolute_path = ProjectSettings.globalize_path(databases[db_name]["data_path"])
	var table_data_path = db_absolute_path + table_name + DATA_EXTENSION
	if not DirAccess.dir_exists_absolute(db_absolute_path):
		var err = DirAccess.make_dir_recursive_absolute(db_absolute_path)
		if err == OK:
			msgs.push_back("Dir: %s has been made." % db_absolute_path)
		else:
			msgs.push_back("Failed! Cannot make dir %s ! Err: %s." % [db_absolute_path, err])
			mgr.add_log_history.emit("Err", begin_time, action, msgs)
			return mgr.create_accept_dialog(msgs)
	else:
		if FileAccess.file_exists(table_data_path):
			msgs.push_back("Failed! Data file [%s] already exist!" % table_data_path)
			mgr.add_log_history.emit("Err", begin_time, action, msgs)
			return mgr.create_accept_dialog(msgs)
			
	# 不记录path、database等信息，是方便转移数据表时，直接剪切文件到对应的数据库目录即可（配置文件和数据文件分别到各自目录）
	var config_file = ConfigFile.new()
	var table_conf_path = databases[db_name]["config_path"] + table_name + CONFIG_EXTENSION
	config_file.set_value(table_name, "encrypted", "" if password.is_empty() else password.md5_text())
	config_file.set_value(table_name, "comment", comment)
	config_file.set_value(table_name, "columns", column_infos)
	config_file.save(table_conf_path)
	msgs.push_back("1 file: %s has been saved." % table_conf_path)
	
	# 这里不通过__CONF_MANAGER，可以让用户使用该表时输入一次密码加深记忆，防止用户加入了很多数据后才发现密码错误
	var data_file = ConfigFile.new()
	data_file.save(table_data_path) if password.is_empty() \
		else data_file.save_encrypted_pass(table_data_path, password)
	msgs.push_back("1 file: %s has been saved." % table_data_path)
	
	if id != "":
		mgr.sys_confirm_add_table.emit(id)
	mgr.add_log_history.emit("OK", begin_time, action, msgs)
	
	refresh()
	
func modify_db_to_config(old_db_name: String, new_db_name: String, _path: String, id: String) -> void:
	var begin_time = Time.get_unix_time_from_system()
	var action = "ALTER DATABASE `%s` RENAME `%s`;" % [old_db_name, new_db_name]
	var msgs = []
	
	if old_db_name == new_db_name:
		msgs.push_back("nothing changed!")
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	if not databases.has(old_db_name):
		msgs.push_back("database [%s] not exist!" % old_db_name)
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	if databases.has(new_db_name):
		msgs.push_back("database's name [%s] has been occupied!" % new_db_name)
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	var old_config_path = CONFIG_ROOT + old_db_name.to_lower().to_snake_case() + "/"
	var new_config_path = CONFIG_ROOT + new_db_name.to_lower().to_snake_case() + "/"
	var old_data = databases[old_db_name]
	_config_file.erase_section(old_db_name)
	_config_file.set_value(new_db_name, "data_path", old_data["data_path"])
	_config_file.set_value(new_db_name, "config_path", new_config_path)
	_config_file.save(ROOT_CONFIG)
	msgs.push_back("1 file: %s has been modified." % ROOT_CONFIG)
	
	var dir = DirAccess.open(CONFIG_ROOT)
	if dir == null:
		msgs.push_back("Failed! Cannot open config root %s dir! Err: %s." % [CONFIG_ROOT, DirAccess.get_open_error()])
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	if dir.dir_exists(old_config_path):
		var err = dir.rename(old_config_path, new_config_path)
		if err == OK:
			msgs.push_back("1 file: %s has been renamed to %s." % [old_config_path, new_config_path])
		else:
			msgs.push_back("Failed! Cannot rename dir from %s to %s ! Err: %s." % [old_config_path, new_config_path, err])
			mgr.add_log_history.emit("Err", begin_time, action, msgs)
			return mgr.create_accept_dialog(msgs)
	else:
		var err = dir.make_dir_recursive(new_config_path)
		if err == OK:
			msgs.push_back("Dir: %s has been made" % new_config_path)
		else:
			msgs.push_back("Failed! Cannot make dir %s ! Err: %s." % [new_config_path, err])
			mgr.add_log_history.emit("Err", begin_time, action, msgs)
			return mgr.create_accept_dialog(msgs)
			
	mgr.sys_confirm_alter_schema.emit(id)
	mgr.add_log_history.emit("OK", begin_time, action, msgs)
	
	refresh()
	
func modify_table_to_config(db_name: String, old_table_name: String, new_table_name, \
		comments: String, column_infos: Array, id: String) -> void:
		
	var begin_time = Time.get_unix_time_from_system()
	var action = "ALTER TABLE `%s`.`%s` to `%s`.`%s` (" % [db_name, old_table_name, db_name, new_table_name]
	var msgs = []
	var primarys = [] # 不代表支持多主键，只是为了反映用户本身的输入
	for i in column_infos:
		action += "\n    `%s` %s%s%s%s%s%s," % [ 
			i["Column Name"],
			DataTypeDef.DATA_TYPE_NAMES[i["Data Type"]],
			" NOT NULL" if i["NN"] else "",
			" AUTO_INCREMENT" if i["AI"] else "",
			" UNIQUE" if i["UQ"] else "",
			(" DEFAULT %s" % i["Default(Expression)"]) if i["Default(Expression)"] != "" else "",
			" COMMENT '%s'" % (i["Comment"] as String).c_escape() if i["Comment"] != "" else ""
		]
		if i["PK"]:
			primarys.push_back(i["Column Name"])
	action += "\n    PRIMARY KEY (%s)\n)" % ",".join(primarys.map(func(v): return "`%s`" % v))
	action += ";" if comments.is_empty() else " COMMENT '%s';" % comments.c_escape()
	
	if primarys.size() != 1:
		msgs.push_back("Multiple primary key or none primary key is not supported!")
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
	
	if not databases.has(db_name):
		msgs.push_back("Failed! Database %s not exists!" % db_name)
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	var table_confs = databases[db_name]["tables"] as Dictionary
	# 没有定义的表怎么办？没影响。
	#if not table_confs.has(old_table_name):
		#var msg = "Failed! table [%s] defination not exist!" % old_table_name
		#mgr.add_log_history.emit("Err", begin_time, action, msg)
		#return mgr.create_accept_dialog(msg)
		
	if new_table_name != old_table_name and table_confs.has(new_table_name):
		msgs.push_back("Failed! Table [%s] name has been occupied!" % new_table_name)
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	var db_path = databases[db_name]["data_path"]
	var old_table_data_path = db_path + old_table_name + DATA_EXTENSION
	var new_table_data_path = db_path + new_table_name + DATA_EXTENSION
	if not FileAccess.file_exists(old_table_data_path):
		msgs.push_back("Failed! File [%s] not exist!" % old_table_data_path)
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	if new_table_data_path != old_table_data_path and FileAccess.file_exists(new_table_data_path):
		msgs.push_back("Failed! File [%s] already exist!" % new_table_data_path)
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	# 检查是否有重复的字段
	var exist_col = {}
	for i in column_infos:
		if exist_col.has(i["Column Name"]):
			var msg = "Duplicate field [%s]" % i["Column Name"]
			mgr.add_log_history.emit("Err", begin_time, action, msg)
			return mgr.create_accept_dialog(msg)
			
		exist_col[i["Column Name"]] = true
		
	# 注意，这里随便传了一个密码，因为实际操作中用户已经输入过密码了，__CONF_MANAGER后续会从缓存中获取，无需再次输入密码
	var old_table_data_file = __CONF_MANAGER.get_conf(old_table_data_path, "")
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
					warnings.push_back("Field [%s] data type changed from [%s] to [%s], datas will be converted!" % \
						[col_name, DataTypeDef.DATA_TYPE_NAMES[old_columns_map[col_name]["Data Type"]], 
						DataTypeDef.DATA_TYPE_NAMES[i["Data Type"]]])
					for j: Dictionary in old_values:
						j[col_name] = type_convert(j[col_name], i["Data Type"])
						# type_convert
						# https://github.com/godotengine/godot/pull/70080
				# 检查自增
				if not old_columns_map[col_name]["AI"] and i["AI"]:
					if not [TYPE_INT, TYPE_FLOAT].has(i["Data Type"]):
						msgs.push_back("Field [%s] data type must be int or float to support auto increment!" % col_name)
						mgr.add_log_history.emit("Err", begin_time, action, msgs)
						return mgr.create_accept_dialog(msgs)
						
					for j: Dictionary in old_values:
						if not [TYPE_INT, TYPE_FLOAT].has(typeof(j[col_name])):
							msgs.push_back(
								"Old datas' field [%s] are not int or float, cannot support auto increment!" % col_name)
							mgr.add_log_history.emit("Err", begin_time, action, msgs)
							return mgr.create_accept_dialog(msgs)
				# 检查主键
				if i["PK"]:
					# 唯一
					var exist = {}
					for j: Dictionary in old_values:
						if exist.has(j[col_name]):
							msgs.push_back("Old datas have duplicate value of primary key [%s]!" % col_name)
							mgr.add_log_history.emit("Err", begin_time, action, msgs)
							return mgr.create_accept_dialog(msgs)
							
						exist[j[col_name]] = true
						
				# 检查唯一
				if i["UQ"]:
					var exist = {}
					for j: Dictionary in old_values:
						if exist.has(j[col_name]):
							msgs.push_back("Old datas have duplicate value of unique key [%s]!" % col_name)
							mgr.add_log_history.emit("Err", begin_time, action, msgs)
							return mgr.create_accept_dialog(msgs)
							
						exist[j[col_name]] = true
				# 检查非null
				if i["NN"]:
					for j: Dictionary in old_values:
						if j[col_name] == null:
							msgs.push_back("Old datas have NULL value of not null key [%s]!" % col_name)
							mgr.add_log_history.emit("Err", begin_time, action, msgs)
							return mgr.create_accept_dialog(msgs)
							
	var apply = func() -> void:
			
		var new_table_data_file = old_table_data_file if old_table_data_path == new_table_data_path \
			else __CONF_MANAGER.create_conf(new_table_data_path, "")
		new_table_data_file.clear()
		
		for i: Dictionary in old_values:
			var primary_value = str(i[primarys[0]])
			for c in column_infos:
				var col_name = c["Column Name"]
				var default_value = null
				if not (c["Default(Expression)"] as String).strip_edges().is_empty():
					default_value = mgr.evaluate_command(null, c["Default(Expression)"])
				new_table_data_file.set_value(primary_value, col_name, i.get(col_name, default_value))
				
		__CONF_MANAGER.save_conf_by_same_password(new_table_data_path, old_table_data_path)
		msgs.push_back("1 file: %s has been saved." % new_table_data_path)
		if new_table_data_path != old_table_data_path:
			__CONF_MANAGER.remove_conf(old_table_data_path)
		
		var config_file = ConfigFile.new()
		var table_conf_path = databases[db_name]["config_path"] + new_table_name + CONFIG_EXTENSION
		config_file.set_value(new_table_name, "encrypted", table_confs[old_table_name]["encrypted"]) # 保留原密码
		config_file.set_value(new_table_name, "comment", comments)
		config_file.set_value(new_table_name, "columns", column_infos)
		config_file.save(table_conf_path) # 如果新路径和旧路径一致，就会覆盖掉，也是我们所期待的
		msgs.push_back("1 file: %s has been saved." % table_conf_path)
		
		if old_table_data_path != new_table_data_path:
			var old_table_conf_path = databases[db_name]["config_path"] + old_table_name + CONFIG_EXTENSION
			var old_table_conf_path_abs = ProjectSettings.globalize_path(old_table_conf_path)
			var old_table_data_path_abs = ProjectSettings.globalize_path(old_table_data_path)
			if FileAccess.file_exists(old_table_conf_path_abs):
				OS.move_to_trash(old_table_conf_path_abs) # 删配置
				msgs.push_back("1 file: %s has been moved to trash." % old_table_conf_path_abs)
			if FileAccess.file_exists(old_table_data_path_abs):
				OS.move_to_trash(old_table_data_path_abs) # 删数据
				msgs.push_back("1 file: %s has been moved to trash." % old_table_data_path_abs)
			
		mgr.sys_confirm_alter_table.emit(id)
		mgr.add_log_history.emit("OK", begin_time, action, msgs)
		
		refresh()
		
	if warnings.is_empty():
		apply.call()
	else:
		mgr.create_confirmation_dialog("\n".join(warnings), apply)
		
		
## set password for a non-enctyped table
func set_password(db_name: String, table_name: String, password: String) -> void:
	var begin_time = Time.get_unix_time_from_system()
	var action = "ALTER TABLE `%s`.`%s` SET PASSWORD" % [db_name, table_name]
	var msgs = []
	
	if password == "":
		msgs.push_back("Failed! Password is empty!")
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	if not databases.has(db_name):
		msgs.push_back("Failed! Database %s not exists!" % db_name)
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	if not databases[db_name]["tables"].has(table_name):
		msgs.push_back("Failed! Table %s.%s not exists!" % [db_name, table_name])
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	if databases[db_name]["tables"][table_name]["encrypted"] != "":
		msgs.push_back("Failed! Table %s.%s is encrypted already!" % [db_name, table_name])
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	var table_conf_path = databases[db_name]["config_path"] + table_name + CONFIG_EXTENSION
	if not FileAccess.file_exists(table_conf_path):
		msgs.push_back("Failed! Table conf %s does not exist!" % table_conf_path)
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	var db_absolute_path = ProjectSettings.globalize_path(databases[db_name]["data_path"])
	var table_data_path = db_absolute_path + table_name + DATA_EXTENSION
	if not FileAccess.file_exists(table_data_path):
		msgs.push_back("Failed! Data file [%s] dose not exist!" % table_data_path)
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	var config_file = ConfigFile.new()
	config_file.load(table_conf_path)
	config_file.set_value(table_name, "encrypted", password.md5_text())
	config_file.save(table_conf_path)
	msgs.push_back("1 file: %s has been saved." % table_conf_path)
	
	__CONF_MANAGER.get_conf(table_data_path, "") # load data
	__CONF_MANAGER.save_conf_by_password(table_data_path, password)
	msgs.push_back("1 file: %s has been encrypted." % table_data_path)
	
	# 清除该表数据的缓存，可以让用户使用该表时必须输入密码，以加深印象
	__CONF_MANAGER.remove_conf(table_data_path)
	
	mgr.add_log_history.emit("OK", begin_time, action, msgs)
	refresh()
	
## clear password for an encrypted table
func clear_password(db_name: String, table_name: String) -> void:
	var begin_time = Time.get_unix_time_from_system()
	var action = "ALTER TABLE `%s`.`%s` CLEAR PASSWORD" % [db_name, table_name]
	var msgs = []
	
	if not databases.has(db_name):
		msgs.push_back("Failed! Database %s not exists!" % db_name)
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	if not databases[db_name]["tables"].has(table_name):
		msgs.push_back("Failed! Table %s.%s not exists!" % [db_name, table_name])
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	if databases[db_name]["tables"][table_name]["encrypted"] == "":
		msgs.push_back("Failed! Table %s.%s is not encrypted! No need to clear password." % [db_name, table_name])
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	var table_conf_path = databases[db_name]["config_path"] + table_name + CONFIG_EXTENSION
	if not FileAccess.file_exists(table_conf_path):
		msgs.push_back("Failed! Table conf %s does not exist!" % table_conf_path)
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	var db_absolute_path = ProjectSettings.globalize_path(databases[db_name]["data_path"])
	var table_data_path = db_absolute_path + table_name + DATA_EXTENSION
	if not FileAccess.file_exists(table_data_path):
		msgs.push_back("Failed! Data file [%s] dose not exist!" % table_data_path)
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	var config_file = ConfigFile.new()
	config_file.load(table_conf_path)
	config_file.set_value(table_name, "encrypted", "")
	config_file.save(table_conf_path)
	msgs.push_back("1 file: %s has been saved." % table_conf_path)
	
	# 注意，这里随便传了一个密码，因为实际操作中用户已经输入过密码了，__CONF_MANAGER后续会从缓存中获取，无需再次输入密码
	__CONF_MANAGER.get_conf(table_data_path, "") # load data 以防万一上面说的“实际操作。。。”并未发生
	__CONF_MANAGER.save_conf_by_password(table_data_path, "")
	msgs.push_back("1 file: %s has been decrypt." % table_data_path)
	
	mgr.add_log_history.emit("OK", begin_time, action, msgs)
	refresh()
	
	
## change password for an enctyped table
func change_password(db_name: String, table_name: String, password: String) -> void:
	var begin_time = Time.get_unix_time_from_system()
	var action = "ALTER TABLE `%s`.`%s` SET PASSWORD" % [db_name, table_name]
	var msgs = []
	
	if password == "":
		msgs.push_back("Failed! Password is empty!")
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	if not databases.has(db_name):
		msgs.push_back("Failed! Database %s not exists!" % db_name)
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	if not databases[db_name]["tables"].has(table_name):
		msgs.push_back("Failed! Table %s.%s not exists!" % [db_name, table_name])
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	if databases[db_name]["tables"][table_name]["encrypted"] == "":
		msgs.push_back("Failed! Table %s.%s is not encrypted!" % [db_name, table_name])
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	var table_conf_path = databases[db_name]["config_path"] + table_name + CONFIG_EXTENSION
	if not FileAccess.file_exists(table_conf_path):
		msgs.push_back("Failed! Table conf %s does not exist!" % table_conf_path)
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	var db_absolute_path = ProjectSettings.globalize_path(databases[db_name]["data_path"])
	var table_data_path = db_absolute_path + table_name + DATA_EXTENSION
	if not FileAccess.file_exists(table_data_path):
		msgs.push_back("Failed! Data file [%s] dose not exist!" % table_data_path)
		mgr.add_log_history.emit("Err", begin_time, action, msgs)
		return mgr.create_accept_dialog(msgs)
		
	var config_file = ConfigFile.new()
	config_file.load(table_conf_path)
	config_file.set_value(table_name, "encrypted", password.md5_text())
	config_file.save(table_conf_path)
	msgs.push_back("1 file: %s has been saved." % table_conf_path)
	
	# 注意，这里随便传了一个密码，因为实际操作中用户已经输入过密码了，__CONF_MANAGER后续会从缓存中获取，无需再次输入密码
	__CONF_MANAGER.get_conf(table_data_path, "") # load data 以防万一上面说的“实际操作。。。”并未发生
	__CONF_MANAGER.save_conf_by_password(table_data_path, password)
	msgs.push_back("1 file: %s has been encrypted." % table_data_path)
	
	# 清除该表数据的缓存，可以让用户使用该表时必须输入密码，以加深印象
	__CONF_MANAGER.remove_conf(table_data_path)
	
	mgr.add_log_history.emit("OK", begin_time, action, msgs)
	refresh()
	
	
func drop_db_from_config(db_name: String) -> void:
	var begin_time = Time.get_unix_time_from_system()
	var action = "Drop Schema %s;" % db_name
	
	if not databases.has(db_name):
		var content = "Database: %s not exist!" % db_name
		mgr.add_log_history.emit("Err", begin_time, action, content)
		return mgr.create_accept_dialog(content)
	
	if _default_database_path == databases[db_name]["data_path"]:
		_default_database_path = ""
	_config_file.erase_section(db_name)
	_config_file.save(ROOT_CONFIG)
	
	var msg = "1 file: %s has been modified" % ROOT_CONFIG
	mgr.add_log_history.emit("OK", begin_time, action, msg)
	
	refresh()
	
func drop_table_from_config(db_name: String, table_name: String) -> void:
	var begin_time = Time.get_unix_time_from_system()
	var action = "Drop table `%s`.`%s`;" % [db_name, table_name]
	var msgs = []
	
	if not databases.has(db_name):
		var content = "Database: %s not exist!" % db_name
		mgr.add_log_history.emit("Err", begin_time, action, content)
		return mgr.create_accept_dialog(content)
		
	if not databases[db_name]["tables"].has(table_name):
		var content = "Table: `%s`.`%s` not exist!" % [db_name, table_name]
		mgr.add_log_history.emit("Err", begin_time, action, content)
		return mgr.create_accept_dialog(content)
		
	# remove config file
	var table_conf_path = databases[db_name]["config_path"] + table_name + CONFIG_EXTENSION
	var conf_path = ProjectSettings.globalize_path(table_conf_path)
	if FileAccess.file_exists(table_conf_path):
		OS.move_to_trash(conf_path)
		msgs.push_back("1 file: %s has been moved to trash." % conf_path)
	else:
		msgs.push_back("1 file: %s intended to move to trash but not found." % conf_path)
		
	# remove data file
	var db_absolute_path = ProjectSettings.globalize_path(databases[db_name]["data_path"])
	var data_path = db_absolute_path + table_name + DATA_EXTENSION
	if FileAccess.file_exists(data_path):
		OS.move_to_trash(data_path)
		msgs.push_back("1 file: %s has been moved to trash." % data_path)
	else:
		msgs.push_back("1 file: %s intended to move to trash but not found." % data_path)
		
	mgr.add_log_history.emit("OK", begin_time, action, msgs)
	
	refresh()
	
func truncate_table_from_config(db_name: String, table_name: String) -> void:
	var begin_time = Time.get_unix_time_from_system()
	var action = "Truncate table `%s`.`%s`;" % [db_name, table_name]
	var msgs = []
	
	if not databases.has(db_name):
		var content = "Database: %s not exist!" % db_name
		mgr.add_log_history.emit("Err", begin_time, action, content)
		return mgr.create_accept_dialog(content)
		
	if not databases[db_name]["tables"].has(table_name):
		var content = "Table: `%s`.`%s` not exist!" % [db_name, table_name]
		mgr.add_log_history.emit("Err", begin_time, action, content)
		return mgr.create_accept_dialog(content)
		
	# clear data file
	var db_absolute_path = ProjectSettings.globalize_path(databases[db_name]["data_path"])
	var data_path = db_absolute_path + table_name + DATA_EXTENSION
	if FileAccess.file_exists(data_path):
		OS.move_to_trash(data_path) # users can get their old data file in trash can
		msgs.push_back("1 file: %s has been moved to trash." % data_path)
	else:
		msgs.push_back("1 file: %s intended to move to trash but not found." % data_path)
		
	# create empty file
	__CONF_MANAGER.get_conf(data_path, "").clear()
	__CONF_MANAGER.save_conf_by_origin_password(data_path)
	msgs.push_back("1 file: %s has been overwritten to an empty file." % data_path)
	
	mgr.add_log_history.emit("OK", begin_time, action, msgs)
	
	refresh()

func _ready():
	if not mgr.run_in_plugin(self):
		return
		
	if Engine.has_singleton("ConfManager"):
		__CONF_MANAGER = Engine.get_singleton("ConfManager")
	else:
		__CONF_MANAGER = ConfManager
		
	if not mgr.user_confirm_add_schema.is_connected(add_db_to_config):
		mgr.user_confirm_add_schema.connect(add_db_to_config)
	if not mgr.user_confirm_add_table.is_connected(add_table_to_config):
		mgr.user_confirm_add_table.connect(add_table_to_config)
	if not mgr.user_confirm_alter_schema.is_connected(modify_db_to_config):
		mgr.user_confirm_alter_schema.connect(modify_db_to_config)
	if not mgr.user_confirm_alter_table.is_connected(modify_table_to_config):
		mgr.user_confirm_alter_table.connect(modify_table_to_config)
	if not mgr.request_user_enter_password.is_connected(deal_password_before_table_cmd_2):
		mgr.request_user_enter_password.connect(deal_password_before_table_cmd_2)
	if not mgr.request_drop_table.is_connected(drop_table_from_config):
		mgr.request_drop_table.connect(drop_table_from_config)
	if not mgr.request_create_table.is_connected(add_table_to_config):
		mgr.request_create_table.connect(add_table_to_config)
	
	load_config()
	popup_menu_database.set_item_submenu(2, "PopupMenuCopyTo")
	popup_menu_database.set_item_submenu(3, "PopupMenuSendTo")
	popup_menu_tables.set_item_submenu(1, "PopupMenuCreateTableLike")
	popup_menu_table_item.set_item_submenu(3, "PopupMenuCopyTo")
	popup_menu_table_item.set_item_submenu(7, "PopupMenuSendTo")
	popup_menu_table_item.set_item_submenu(10, "PopupMenuCreateTableLike")
	popup_menu_table_item.set_item_submenu(12, "PopupMenuPassword")
	popup_menu_column.set_item_submenu(2, "PopupMenuCopyTo")
	popup_menu_column.set_item_submenu(3, "PopupMenuSendTo")
	refresh()
	
func _exit_tree():
	if not mgr.run_in_plugin(self):
		return
		
	_clear()
	_config_file = null
	__CONF_MANAGER = null
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
	if mgr.request_drop_table.is_connected(drop_table_from_config):
		mgr.request_drop_table.disconnect(drop_table_from_config)
	if mgr.request_create_table.is_connected(add_table_to_config):
		mgr.request_create_table.disconnect(add_table_to_config)
	
func refresh() -> void:
	_clear()
	refresh_databases()
	root = create_item()
	var collapsed = false
	for db_name in databases:
		var data = databases[db_name]
		var db := add_database(db_name, data["data_path"], data["config_path"])
		db.collapsed = collapsed if _default_database_path.is_empty() else _default_database_path != data["data_path"]
		database_items.push_back(db)
		collapsed = true # 在没默认数据库的情况下，除了第一个数据库不折叠，其他都折叠
		
		for table_name in data["tables"]:
			add_table(db, table_name)
			
	
	# create table like 子菜单重新生成
	var id = 0
	for db_name in databases:
		var data = databases[db_name]
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
			
			popup_menu_create_table_like_table_item.add_item(t)
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
				if file_name.get_extension() == extension:
					ret.push_back(file_name)
					
			file_name = dir.get_next()
		dir.list_dir_end()
	else:
		push_error("An error occurred when trying to access the path:" + path)
		
	return ret

func add_database(db_name: String, data_path: String, conf_path: String) -> TreeItem:
	var database_item = create_item(root)
	database_item.set_text(0, db_name)
	database_item.set_icon(0, preload("res://addons/gdsql/img/icon_db.png"))
	database_item.set_icon_max_width(0, 20)
	database_item.add_button(0, preload("res://addons/gdsql/img/folder.png"), 
		ITEM_BUTTON_INDEX.FOLDER, false, "Show in File Manager")
	database_item.set_tooltip_text(0, data_path)
	database_item.set_meta("db_name", db_name)
	database_item.set_meta("data_path", data_path)
	database_item.set_meta("config_path", conf_path)
	database_item.set_meta("type", "database")
	if data_path == _default_database_path:
		database_item.set_custom_bg_color(0, Color.BLUE_VIOLET)
	
	var arr := ["Tables", "Views", "Stored Procedures", "Functions"]
	var tooltips := ["数据表", "视图", "存储过程", "函数"]
	for i in arr.size():
		var item = create_item(database_item)
		item.set_text(0, arr[i])
		item.set_icon(0, preload("res://addons/gdsql/img/windows.png"))
		item.set_icon_max_width(0, 16)
		item.set_tooltip_text(0, tooltips[i])
		item.set_meta("type", arr[i])
		item.set_meta("db_name", db_name)
		item.set_meta("data_path", data_path)
		if i > 0:
			item.set_collapsed_recursive(true)
	
	return database_item
	
func add_table(db: TreeItem, table_name: String):
	var table_item = create_item(db.get_child(0)) # child 0 是 Tables。其他是Views、Stored Procedures等等
	var file_name = table_name + DATA_EXTENSION
	var db_name = db.get_meta("db_name")
	var data_path = db.get_meta("data_path") + file_name
	table_item.set_text(0, table_name)
	table_item.set_icon(0, preload("res://addons/gdsql/img/table.png"))
	table_item.set_icon_max_width(0, 20)
	table_item.set_tooltip_text(0, file_name)
	if databases[db_name]["tables"][table_name]["encrypted"] != "":
		var texture
		var tooltip
		if __CONF_MANAGER.has_conf(data_path):
			texture = preload("res://addons/gdsql/img/unlock.png")
			tooltip = "This table is encrypted and you have entered the right password."
		else:
			texture = preload("res://addons/gdsql/img/lock.png") 
			tooltip = "This table's data file is encrypted. Enter password before using it."
		table_item.add_button(0, texture, ITEM_BUTTON_INDEX.ENCRYPT, false, tooltip)
	table_item.add_button(0, preload("res://addons/gdsql/img/quick_search.png"), 
		ITEM_BUTTON_INDEX.QUICK_SEARCH, false, "select * from %s.%s;" % [db_name, table_name])
	table_item.set_meta("db_name", db_name)
	table_item.set_meta("table_name", table_name)
	table_item.set_meta("data_path", data_path)
	table_item.set_meta("type", "table")
	table_item.collapsed = true
	
	# TODO 让column可以多选
	# column的子tree
	var table_columns = databases[db_name]["tables"][table_name]["columns"]
	for col in table_columns:
		var col_item = create_item(table_item)
		var texts = [col["Column Name"]]
		texts.push_back(DataTypeDef.DATA_TYPE_NAMES[col["Data Type"]].replace("TYPE_", "").capitalize())
		col_item.set_text(0, ": ".join(texts))
		col_item.set_tooltip_text(0, "Comment: %s\nDefault(Expression): %s" % \
			[col["Comment"], col["Default(Expression)"]])
		col_item.set_icon(0, preload("res://addons/gdsql/img/dot.png"))
		col_item.set_meta("db_name", db_name)
		col_item.set_meta("table_name", table_name)
		col_item.set_meta("column_name", col["Column Name"])
		col_item.set_meta("type", "column")
		var properties = ["AI", "NN", "UQ", "PK"]
		var tooltips = ["Auto Increment", "Not NULL", "Uniq", "Primary Key"]
		for i in properties.size():
			if col[properties[i]]:
				col_item.add_button(0, load("res://addons/gdsql/img/word_%s.png" \
				% (properties[i] as String).to_lower()), ITEM_BUTTON_INDEX.COLUMN_PROPERTY
				, true, tooltips[i])
				
				
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
				deal_password_before_table_cmd(item, exe_select)
			# Show in File Manager
			ITEM_BUTTON_INDEX.FOLDER:
				var path = ProjectSettings.globalize_path(item.get_meta("data_path"))
				OS.shell_show_in_file_manager(path, true)
			ITEM_BUTTON_INDEX.COLUMN_PROPERTY:
				pass
			ITEM_BUTTON_INDEX.ENCRYPT:
				deal_password_before_table_cmd(item, Callable())


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
				deal_password_before_table_cmd(item, exe_select)
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
				deal_password_before_table_cmd(item, open_tab)
		"Table Data Import Wizard":
			var item := get_selected()
			if item:
				var db_name = item.get_meta("db_name")
				var table_name = item.get_meta("table_name")
				var open_tab = func():
					mgr.open_table_data_import_tab.emit(db_name, table_name)
				deal_password_before_table_cmd(item, open_tab)
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
				deal_password_before_table_cmd(item, open_tab)
		"Drop Table...":
			var item := get_selected()
			if item:
				var db_name = item.get_meta("db_name")
				var table_name = item.get_meta("table_name")
				var open_dialog = func():
					mgr.create_confirmation_dialog(
						"Are you sure to Drop table `%s`.`%s`? Config file and data file of this table will be moved to trash." % \
						[db_name, table_name], drop_table_from_config.bind(db_name, table_name))
				deal_password_before_table_cmd(item, open_dialog)
		"Truncate Table...":
			var item := get_selected()
			if item:
				var db_name = item.get_meta("db_name")
				var table_name = item.get_meta("table_name")
				var open_dialog = func():
					mgr.create_confirmation_dialog(
						"Are you sure to Truncate table `%s`.`%s`?" % \
						[db_name, table_name], truncate_table_from_config.bind(db_name, table_name))
				deal_password_before_table_cmd(item, open_dialog)
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
		"Refresh All":
			refresh()
			
func deal_password_before_table_cmd_2(db_name: String, table_name: String, pass_callback: Callable):
	for db_item in root.get_children():
		if db_item.get_meta("db_name") == db_name:
			for collection in db_item.get_children():
				if collection.get_meta("type") == "Tables":
					for table_item in collection.get_children():
						if table_item.get_meta("table_name") == table_name:
							deal_password_before_table_cmd(table_item, pass_callback)
							return
	mgr.create_accept_dialog("%s.%s not exist!" % [db_name, table_name])
	
func deal_password_before_table_cmd(table_item: TreeItem, pass_callback: Callable):
	var db_name = table_item.get_meta("db_name")
	var table_name = table_item.get_meta("table_name")
	var table_path = table_item.get_meta("data_path")
	var password_dict_obj = DictionaryObject.new({"Password": ""}, 
		{"Password": {"hint": PROPERTY_HINT_PASSWORD}})
	# 加密的表首次操作时需要输入密码
	var valid_pass_md5 = databases[db_name]["tables"][table_name]["encrypted"]
	if valid_pass_md5 == "" or __CONF_MANAGER.has_conf(table_path):
		if pass_callback.is_valid():
			pass_callback.call()
	else:
		var confirmed = func():
			if valid_pass_md5 == (password_dict_obj._get("Password") as String).md5_text():
				# 在内存中load一次表，后续再通过__CONF_MANAGER获取表就不需要密码了
				__CONF_MANAGER.get_conf(table_path, password_dict_obj._get("Password"))
				var texture = preload("res://addons/gdsql/img/unlock.png")
				var tooltip = "This table is encrypted and you have entered the right password."
				var index = table_item.get_button_by_id(0, ITEM_BUTTON_INDEX.ENCRYPT)
				table_item.set_button(0, index, texture)
				table_item.set_button_tooltip_text(0, index, tooltip)
				if pass_callback.is_valid():
					pass_callback.call()
				return true
			else:
				mgr.create_accept_dialog("Password is not correct!")
				return false
				
		var arr: Array[Array] = [
			["This table is encrypted. Please input password of this table."],
			[password_dict_obj],
		]
		mgr.create_custom_dialog(arr, Callable(), confirmed)
	
## Tables目录的create table like子目录的菜单
func _on_popup_menu_create_table_like_tables_index_pressed(index: int) -> void:
	var item = get_selected()
	if item:
		var db_name = item.get_meta("db_name")
		var meta_data = popup_menu_create_table_like_tables.get_item_metadata(index)
		var like_db_name = meta_data["db_name"]
		var like_table_name = meta_data["table_name"]
		mgr.open_add_table_tab.emit(db_name, like_db_name, like_table_name)

## Table Item的create table like子目录的菜单
func _on_popup_menu_create_table_like_table_item_index_pressed(index: int) -> void:
	var item = get_selected()
	if item:
		var db_name = item.get_meta("db_name")
		var meta_data = popup_menu_create_table_like_table_item.get_item_metadata(index)
		var like_db_name = meta_data["db_name"]
		var like_table_name = meta_data["table_name"]
		mgr.open_add_table_tab.emit(db_name, like_db_name, like_table_name)
	
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
				mgr.open_alter_schema_tab.emit(item.get_meta("db_name"), item.get_meta("data_path"))
		"Drop Schema...":
			var item := get_selected()
			if item:
				mgr.create_confirmation_dialog(
					"Are you sure to drop this database `%s`? This will NOT delete the folder from your operation system." \
					% get_selected().get_meta("db_name"),
					drop_db_from_config.bind(item.get_meta("db_name"))
				)
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
				DisplayServer.clipboard_set(item.get_meta("config_path"))
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
			pass
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
				var cmd = """
var dao = BaseDao.new()
var ret = dao.use_db("%s")\\
	.set_password("")\\
	.select("*", true)\\
	.from("%s")\\
	.query()
""" % [databases[db_name]["data_path"], table_name + DATA_EXTENSION]
				DisplayServer.clipboard_set(cmd)
		"Insert Statement":
			var item := get_selected()
			if item:
				var db_name = item.get_meta("db_name")
				var table_name = item.get_meta("table_name")
				var cmd = """
var dao = BaseDao.new()
var ret = dao.use_db("%s")\\
	.set_password("")\\
	.insert_into("%s")\\
	.values(<data: Dictionary>)\\
	.query()
""" % [databases[db_name]["data_path"], table_name + DATA_EXTENSION]
				DisplayServer.clipboard_set(cmd)
		"Update Statement":
			var item := get_selected()
			if item:
				var db_name = item.get_meta("db_name")
				var table_name = item.get_meta("table_name")
				var cmd = """
var dao = BaseDao.new()
var ret = dao.use_db("%s")\\
	.set_password("")\\
	.update("%s")\\
	.sets(<data: Dictionary>)\\
	.where(<cond: String>)\\
	.query()
""" % [databases[db_name]["data_path"], table_name + DATA_EXTENSION]
				DisplayServer.clipboard_set(cmd)
		"Delete Statement":
			var item := get_selected()
			if item:
				var db_name = item.get_meta("db_name")
				var table_name = item.get_meta("table_name")
				var cmd = """
var dao = BaseDao.new()
var ret = dao.use_db("%s")\\
	.set_password("")\\
	.delete_from("%s")\\
	.where(<cond: String>)\\
	.query()
""" % [databases[db_name]["data_path"], table_name + DATA_EXTENSION]
				DisplayServer.clipboard_set(cmd)
		"Config Path":
			var item := get_selected()
			if item:
				var db_name = item.get_meta("db_name")
				var table_name = item.get_meta("table_name")
				var config_path = databases[db_name]["config_path"] + table_name + CONFIG_EXTENSION
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
	match popup_menu_password.get_item_text(index):
		"Set Password":
			var item := get_selected()
			if item == null:
				return
				
			var db_name = item.get_meta("db_name")
			var table_name = item.get_meta("table_name")
			
			var password_dict_obj_1 = DictionaryObject.new({"Password": ""}, 
				{"Password": {"hint": PROPERTY_HINT_PASSWORD}})
			var password_dict_obj_2 = DictionaryObject.new({"Password": ""}, 
				{"Password": {"hint": PROPERTY_HINT_PASSWORD, "hint_string": "Enter same password agian."}})
				
			var confirmed = func():
				if password_dict_obj_1._get("Password") != password_dict_obj_2._get("Password"):
					mgr.create_accept_dialog("Passwords are different!")
					return false
				# 安全起见还是通过检查是否需要用户输入密码再执行后续方法
				deal_password_before_table_cmd_2(db_name, table_name, 
					set_password.bind(db_name, table_name, password_dict_obj_1._get("Password")))
				return true
				
			var arr: Array[Array] = [
				["Set password for this table:"],
				[password_dict_obj_1],
				[password_dict_obj_2],
			]
			mgr.create_custom_dialog(arr, Callable(), confirmed)
			
		"Clear Password":
			pass
		"Change Password":
			pass

## 密码修改相关操作
func _on_popup_menu_password_about_to_popup():
	var item := get_selected()
	if item:
		var db_name = item.get_meta("db_name")
		var table_name = item.get_meta("table_name")
		if databases[db_name]["tables"][table_name]["encrypted"] == "":
			popup_menu_password.set_item_disabled(0, false)
			popup_menu_password.set_item_disabled(1, true)
			popup_menu_password.set_item_disabled(2, true)
		else:
			popup_menu_password.set_item_disabled(0, true)
			popup_menu_password.set_item_disabled(1, false)
			popup_menu_password.set_item_disabled(2, false)
