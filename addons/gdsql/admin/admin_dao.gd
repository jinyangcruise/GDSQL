@tool
extends RefCounted
## GDSQL AdminDao - Runtime database/table administration API
##
## Provides the same operations as the UI tree_databases.gd,
## but as a pure code API without UI dependencies.
##
## Usage:
##   var dao = GDSQL.AdminDao.new()
##   var err = await dao.create_database("mydb", "user://mydb/")
##   if err != OK: printerr("Failed: ", error_string(err))

var _db_name: String = ""
var _db_path: String = ""
var _password = ""  # can be String or PackedByteArray
var _request_password: Array = []
var _begin_time: float = 0
# ----- Helper -----

func _validate_name(name: String) -> String:
	return GDSQL.RootConfig.validate_name(name)
	
func _is_editor() -> bool:
	return Engine.is_editor_hint()
	
func _get_mgr() -> GDSQL.WorkbenchManagerClass:
	return GDSQL.WorkbenchManager if _is_editor() else null
	
#func _assert_false(action: String, msg: String) -> Error:
	#var mgr = _get_mgr()
	#if mgr:
		#_mgr_create_accept_dialog(msg)
		#_mgr_add_log_history_emit("Err", Time.get_unix_time_from_system(), action, msg)
	#push_error(msg)
	#return FAILED
	
#func _mgr_add_log_history_emit(status: String, begin_time: float, action: String, msgs) -> void:
	#var mgr = _get_mgr()
	#if mgr:
		#mgr.add_log_history.emit(status, begin_time, action, msgs)
		
func _mgr_sys_confirm_drop_table_emit(db_name: String, table_name: String) -> void:
	var mgr = _get_mgr()
	if mgr:
		mgr.sys_confirm_drop_table.emit(db_name, table_name)
		
#func _mgr_create_accept_dialog(msgs):
	#var mgr = _get_mgr()
	#if mgr:
		#mgr.create_accept_dialog(msgs)
		
func _error_occur(action: String, msgs, error: Error = FAILED) -> Error:
	assert(error != OK, "Inner error!")
	var mgr = _get_mgr()
	if mgr:
		mgr.add_log_history.emit("Err", _begin_time, action, msgs)
		mgr.create_accept_dialog(msgs)
	else:
		push_error(error_string(error), action, msgs)
	return error
	
func _success(action: String, msgs) -> Error:
	var mgr = _get_mgr()
	if mgr:
		mgr.add_log_history.emit("OK", _begin_time, action, msgs)
		mgr.create_accept_dialog(msgs)
	return OK
	
func _mgr_create_confirmation_dialog(msgs, confirm_callback: Callable):
	var mgr = _get_mgr()
	if mgr:
		mgr.create_confirmation_dialog(msgs, confirm_callback)
		
## 是否需要用户输入密码
func need_user_enter_password() -> bool:
	return not _request_password.is_empty()
	
## 处理密码逻辑，参考 base_dao.gd 的 _handle_defualt_password。
## 设置 _request_password 标记是否需要用户输入密码。
func _handle_password(db_name: String, table_name: String = "") -> Error:
	_request_password.clear()
	if _is_editor():
		var mgr = _get_mgr()
		if mgr and mgr.need_request_password(db_name, table_name, _password):
			_request_password.push_back(true)
	elif _password.is_empty():
		_password = GDSQL.RootConfig.get_database_dek(db_name)
		if _password.is_empty() and not table_name.is_empty():
			_password = GDSQL.RootConfig.get_table_dek(db_name, table_name)
		# DDL 涉及表的操作，需要先load一下表
		if _password and not table_name.is_empty():
			var conf = GDSQL.ConfManager.get_conf(GDSQL.RootConfig.get_table_data_path(db_name, table_name), _password)
			if not conf:
				return _error_occur("Password", tr("Incorrect password!"), ERR_UNAUTHORIZED)
				
	elif typeof(_password) == TYPE_PACKED_BYTE_ARRAY:
		# DDL 涉及表的操作，需要先load一下表
		if _password and not table_name.is_empty():
			var conf = GDSQL.ConfManager.get_conf(GDSQL.RootConfig.get_table_data_path(db_name, table_name), _password)
			if not conf:
				return _error_occur("Password", tr("Incorrect password!"), ERR_UNAUTHORIZED)
	else:
		var encrypted_dek = GDSQL.RootConfig.get_database_encrypted_dek(db_name)
		if encrypted_dek == "":
			encrypted_dek = GDSQL.RootConfig.get_table_encrypted_dek(db_name, table_name)
			if encrypted_dek == "":
				# 本来没密码，非要输入一个错的密码，也不行。
				return _error_occur("Password", tr("Incorrect password!"), ERR_UNAUTHORIZED)
				
		var recovered_dek = GDSQL.CryptoUtil.decrypt_dek(encrypted_dek, _password)
		# DDL 涉及表的操作，需要先load一下表
		if recovered_dek and not table_name.is_empty():
			var conf = GDSQL.ConfManager.get_conf(GDSQL.RootConfig.get_table_data_path(db_name, table_name), recovered_dek)
			if not conf:
				return _error_occur("Password", tr("Incorrect password!"), ERR_UNAUTHORIZED)
		else:
			return _error_occur("Password", tr("Incorrect password!"), ERR_UNAUTHORIZED)
	return OK
	
## 密码对话框循环，参考 sql_graph.gd 的 _deal_query_need_enter_password。
## 在编辑器模式下如果_handle_password标记了需要密码，就弹密码框等待用户输入，
## 输入正确后自动重试操作。
## pass action_impl: Callable  实现操作的函数(返回Error)
func _exec_with_password_guard(action_name: String, db_name: String, action_impl: Callable, table_name: String = "") -> Error:
	var reach_max = false
	for i in 100:
		reach_max = i == 99
		_handle_password(db_name, table_name)
		if need_user_enter_password():
			_request_password.clear()
			var mgr = _get_mgr()
			if mgr:
				var password_ret = [null]
				mgr.request_curr_password(password_ret)
				while true:
					await mgr.get_tree().process_frame
					if password_ret[0] != null:
						break
				if password_ret[0]:
					continue
				else:
					_error_occur(action_name, tr("Missing password!"))
			return ERR_UNAUTHORIZED
		else:
			return action_impl.call()
	if reach_max:
		return _error_occur(action_name, tr("Too many password attempts!"))
	return ERR_UNAUTHORIZED
	
# ----- Database Operations -----
	
## Create a new database.
func create_database(name: String, path: String) -> Error:
	_begin_time = Time.get_unix_time_from_system()
	return _create_database_impl(name, path)
	
func _create_database_impl(db_name: String, path: String) -> Error:
	db_name = _validate_name(db_name)
	path = GDSQL.GDSQLUtils.globalize_path(path)
	
	var action = "CREATE DATABASE %s PATH %s;" % [db_name, path]
	var msgs = []
	
	if not _can_path_be_modified(path):
		msgs.push_back(tr("Failed! Cannot create a database inside the project in exported games."))
		return _error_occur(action, msgs)
		
	if db_name == GDSQL.RootConfig.DEK or not (db_name.is_valid_ascii_identifier() or db_name.is_valid_unicode_identifier()):
		msgs.push_back(tr("Failed! Database name `%s` is invalid!") % db_name)
		return _error_occur(action, msgs)
		
	var databases = GDSQL.RootConfig.get_databases_info()
	for a_db_name: String in databases:
		if a_db_name == db_name:
			msgs.push_back(tr("Failed! Database name `%s` has been occupied!") % db_name)
			return _error_occur(action, msgs)
			
		if databases[a_db_name]["data_path"] == path:
			msgs.push_back(tr("Failed! Database path `%s`(%s) already exist!") % [path, a_db_name])
			return _error_occur(action, msgs)
			
	GDSQL.RootConfig.set_database_data(db_name, path, "")
	GDSQL.RootConfig.save()
	msgs.push_back(tr("1 file: %s has been modified.") % GDSQL.RootConfig.path)
	
	var dir = DirAccess.open(GDSQL.RootConfig.get_base_dir())
	if dir == null:
		msgs.push_back(tr("Failed! Cannot open config root %s dir! Err: %s.") % 
			[GDSQL.RootConfig.get_base_dir(), DirAccess.get_open_error()])
		return _error_occur(action, msgs)
		
	var config_path = GDSQL.RootConfig.get_database_config_path(db_name)
	if not dir.dir_exists(config_path):
		var err = dir.make_dir_recursive(config_path)
		if err == OK:
			msgs.push_back(tr("Dir: %s has been made.") % config_path)
		else:
			msgs.push_back(tr("Failed! Cannot make dir %s ! Err: %s.") % [config_path, err])
			return _error_occur(action, msgs)
			
	return _success(action, msgs)
	
## Rename a database.
func alter_database(old_name: String, new_name: String) -> Error:
	_begin_time = Time.get_unix_time_from_system()
	return await _exec_with_password_guard("ALTER DATABASE", old_name,
		func(): return _alter_database_impl(old_name, new_name))
		
func _alter_database_impl(old_db_name: String, new_db_name: String) -> Error:
	old_db_name = _validate_name(old_db_name)
	new_db_name = _validate_name(new_db_name)
	
	var action = "ALTER DATABASE `%s` RENAME `%s`;" % [old_db_name, new_db_name]
	var msgs = []
	
	if new_db_name == GDSQL.RootConfig.DEK or not (new_db_name.is_valid_ascii_identifier() or new_db_name.is_valid_unicode_identifier()):
		msgs.push_back(tr("Failed! Database name `%s` is invalid!") % new_db_name)
		return _error_occur(action, msgs)
		
	if old_db_name == new_db_name:
		msgs.push_back(tr("Nothing changed!"))
		return _error_occur(action, msgs)
		
	var databases = GDSQL.RootConfig.get_databases_info()
	if not databases.has(old_db_name):
		msgs.push_back(tr("Database [%s] not exist!") % old_db_name)
		return _error_occur(action, msgs)
		
	if databases.has(new_db_name):
		msgs.push_back(tr("Database's name [%s] has been occupied!") % new_db_name)
		return _error_occur(action, msgs)
		
	var old_config_path = GDSQL.RootConfig.get_database_config_path(old_db_name)
	if not _can_path_be_modified(old_config_path):
		msgs.push_back(tr("Failed! Cannot alter a database inside the project in exported games."))
		return _error_occur(action, msgs)
		
	var new_config_path = GDSQL.RootConfig.get_database_config_path(new_db_name)
	if not _can_path_be_modified(new_config_path):
		msgs.push_back(tr("Failed! Cannot alter a database inside the project in exported games."))
		return _error_occur(action, msgs)
		
	var old_data = databases[old_db_name]
	GDSQL.RootConfig.set_database_data(new_db_name, old_data["data_path"], old_data["encrypted"])
	GDSQL.RootConfig.erase_database(old_db_name)
	GDSQL.RootConfig.save()
	msgs.push_back(tr("1 file: %s has been modified.") % GDSQL.RootConfig.path)
	
	var dir = DirAccess.open(GDSQL.RootConfig.get_base_dir())
	if dir == null:
		msgs.push_back(tr("Failed! Cannot open config root %s dir! Err: %s.") % 
			[GDSQL.RootConfig.get_base_dir(), DirAccess.get_open_error()])
		return _error_occur(action, msgs)
		
	if dir.dir_exists(old_config_path):
		var err = dir.rename(old_config_path, new_config_path)
		if err == OK:
			msgs.push_back(tr("1 file: %s has been renamed to %s.") % [old_config_path, new_config_path])
		else:
			msgs.push_back(tr("Failed! Cannot rename dir from %s to %s ! Err: %s.") % [old_config_path, new_config_path, err])
			return _error_occur(action, msgs)
	else:
		var err = dir.make_dir_recursive(new_config_path)
		if err == OK:
			msgs.push_back(tr("Dir: %s has been made.") % new_config_path)
		else:
			msgs.push_back(tr("Failed! Cannot make dir %s ! Err: %s.") % [new_config_path, err])
			return _error_occur(action, msgs)
			
	return _success(action, msgs)
	
## Delete a database.
func drop_database(name: String) -> Error:
	_begin_time = Time.get_unix_time_from_system()
	return await _exec_with_password_guard("DROP DATABASE", name,
		func(): return _drop_database_impl(name))
		
func _drop_database_impl(db_name: String) -> Error:
	db_name = _validate_name(db_name)
	
	var action = "Drop Schema %s;" % db_name
	var msgs = []
	
	var db_data_path = GDSQL.RootConfig.get_database_data_path(db_name)
	if db_data_path == "":
		var content = tr("Database: %s not exist!") % db_name
		return _error_occur(action, content)
		
	if not _can_path_be_modified(db_data_path):
		msgs.push_back(tr("Failed! Cannot drop a database inside the project in exported games."))
		return _error_occur(action, msgs)
		
	if _is_editor():
		var dek64 = GDSQL.RootConfig.get_database_dek64(db_name)
		if dek64:
			# In case user want to revert but don't know the dek.
			var tmp_file_path = "user://%s.%s.%s.dek" % [db_name, 
				Time.get_datetime_string_from_system(false, true).to_snake_case().replace(":", "_").validate_filename()]
			var file = FileAccess.open(tmp_file_path, FileAccess.WRITE)
			file.store_string(dek64)
			file.flush()
			file.close()
			OS.move_to_trash(GDSQL.GDSQLUtils.globalize_path(tmp_file_path))
			
	var databases = GDSQL.RootConfig.get_databases_info()
	if not databases.has(db_name):
		msgs.push_back(tr("Failed! Database %s not exists!") % db_name)
		return _error_occur(action, msgs)
		
	for table_name in databases[db_name]["tables"]:
		_remove_table_files(db_name, table_name)
		
	GDSQL.RootConfig.set_database_dek(db_name, null)
	GDSQL.RootConfig.erase_database(db_name)
	GDSQL.RootConfig.save()
	msgs.push_back(tr("1 file: %s has been modified") % GDSQL.RootConfig.path)
	return _success(action, msgs)
	
# ----- Table Operations -----
	
func create_table(db_name: String, table_name: String, column_infos: Array,
comment: String = "", password: String = "", valid_if_not_exist: bool = false) -> Error:
	_begin_time = Time.get_unix_time_from_system()
	return await _exec_with_password_guard("CREATE TABLE", db_name,
		func(): return _create_table_impl(db_name, table_name, column_infos, comment, password, valid_if_not_exist),
		table_name)
		
func _create_table_impl(db_name: String, table_name: String, column_infos: Array,
comment: String = "", password: String = "", valid_if_not_exist: bool = false) -> Error:
	db_name = _validate_name(db_name)
	table_name = _validate_name(table_name)
	
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
	
	var db_data_path = GDSQL.RootConfig.get_database_data_path(db_name)
	if db_data_path == "":
		var content = tr("Database: %s not exist!") % db_name
		return _error_occur(action, content)
		
	if not _can_path_be_modified(db_data_path):
		msgs.push_back(tr("Failed! Cannot create a table inside the project in exported games."))
		return _error_occur(action, msgs)
		
	# 检查是否有重复的字段
	var exist_col = {}
	for i in column_infos:
		if exist_col.has(i["Column Name"]):
			msgs.push_back(tr("Duplicate column [%s].") % i["Column Name"])
			return _error_occur(action, msgs)
			
		exist_col[i["Column Name"]] = true
		
	var db_dek64 = GDSQL.RootConfig.get_database_dek64(db_name)
	if db_dek64 and password:
		msgs.push_back(tr("Failed! Database %s is encrypted! Cannot set another password for this table!"))
		return _error_occur(action, msgs)
		
	var conf_dir = DirAccess.open(GDSQL.RootConfig.get_database_config_path(db_name))
	if conf_dir == null:
		msgs.push_back(tr("Failed! Cannot open database config dir %s! Err: %s.") \
			% [GDSQL.RootConfig.get_database_config_path(db_name), DirAccess.get_open_error()])
		return _error_occur(action, msgs)
		
	if conf_dir.file_exists(table_name + GDSQL.RootConfig.CONFIG_EXTENSION):
		msgs.push_back(tr("Failed! Table conf %s already exist!") % (table_name + GDSQL.RootConfig.CONFIG_EXTENSION))
		return _error_occur(action, msgs)
		
	var db_absolute_path = GDSQL.GDSQLUtils.globalize_path(db_data_path)
	var table_data_path = GDSQL.GDSQLUtils.globalize_path(GDSQL.RootConfig.get_table_data_path(db_name, table_name))
	if not DirAccess.dir_exists_absolute(db_absolute_path):
		var err = DirAccess.make_dir_recursive_absolute(db_absolute_path)
		if err == OK:
			msgs.push_back(tr("Dir: %s has been made.") % db_absolute_path)
		else:
			msgs.push_back(tr("Failed! Cannot make dir %s ! Err: %s.") % [db_absolute_path, err])
			return _error_occur(action, msgs)
	else:
		if FileAccess.file_exists(table_data_path):
			msgs.push_back(tr("Failed! Data file [%s] already exist!") % table_data_path)
			return _error_occur(action, msgs)
			
	# 不记录path、database等信息，是方便转移数据表时，直接剪切文件到对应的数据库目录即可（配置文件和数据文件分别到各自目录）
	var dek64 = "" if password == "" else GDSQL.CryptoUtil.generate_dek()
	var config_file = ConfigFile.new()
	var table_conf_path = GDSQL.RootConfig.get_table_config_path(db_name, table_name)
	config_file.set_value(table_name, "encrypted", "" if dek64 == "" else GDSQL.CryptoUtil.encrypt_dek(dek64, password))
	config_file.set_value(table_name, "comment", comment)
	config_file.set_value(table_name, "valid_if_not_exist", valid_if_not_exist)
	config_file.set_value(table_name, "columns", column_infos)
	config_file.save(table_conf_path)
	msgs.push_back(tr("1 file: %s has been saved.") % table_conf_path)
	
	# 先设置成虚拟的文件，便于首次保存
	GDSQL.ConfManager.mark_valid_if_not_exit(table_data_path)
	GDSQL.ConfManager.get_conf(table_data_path, "") # load data
	if db_dek64:
		GDSQL.ConfManager.save_conf_by_dek(table_data_path, db_dek64)
	elif dek64:
		GDSQL.ConfManager.save_conf_by_dek(table_data_path, dek64)
		GDSQL.RootConfig.set_table_dek(db_name, table_name, dek64)
		GDSQL.RootConfig.save()
		msgs.push_back(tr("1 file: %s has been modified.") % GDSQL.RootConfig.path)
	else:
		GDSQL.ConfManager.save(table_data_path)
	if not valid_if_not_exist:
		GDSQL.ConfManager.mark_invalid_if_not_exist(table_data_path)
	msgs.push_back(tr("1 file: %s has been saved.") % table_data_path)
	
	return _success(action, msgs)
	
func alter_table(db_name: String, old_name: String, new_name: String,
column_infos: Array, comments: String = "", valid_if_not_exist: bool = false) -> Error:
	_begin_time = Time.get_unix_time_from_system()
	return await _exec_with_password_guard("ALTER TABLE", db_name,
		func(): return _alter_table_impl(db_name, old_name, new_name, column_infos, comments, valid_if_not_exist),
		old_name)
		
func _alter_table_impl(db_name: String, old_table_name: String, new_table_name: String,
column_infos: Array, comments: String = "", valid_if_not_exist: bool = false) -> Error:
	db_name = _validate_name(db_name)
	old_table_name = _validate_name(old_table_name)
	new_table_name = _validate_name(new_table_name)
	
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
	
	var db_data_path = GDSQL.RootConfig.get_database_data_path(db_name)
	if db_data_path == "":
		var content = tr("Database: %s not exist!") % db_name
		return _error_occur(action, content)
		
	if not _can_path_be_modified(db_data_path):
		msgs.push_back(tr("Failed! Cannot alter a table inside the project in exported games."))
		return _error_occur(action, msgs)
		
	if primarys.size() != 1:
		msgs.push_back(tr("Multiple primary key or none primary key is not supported!"))
		return _error_occur(action, msgs)
		
	var databases = GDSQL.RootConfig.get_databases_info()
	if not databases.has(db_name):
		msgs.push_back(tr("Failed! Database %s not exists!") % db_name)
		return _error_occur(action, msgs)
		
	var table_columns = GDSQL.RootConfig.get_table_columns(db_name, new_table_name)
	if new_table_name != old_table_name and table_columns:
		msgs.push_back(tr("Failed! Table [%s] name has been occupied!") % new_table_name)
		return _error_occur(action, msgs)
		
	var old_table_data_path = GDSQL.RootConfig.get_table_data_path(db_name, old_table_name)
	var new_table_data_path = GDSQL.RootConfig.get_table_data_path(db_name, new_table_name)
	if not FileAccess.file_exists(old_table_data_path):
		var config_file = ConfigFile.new()
		var table_conf_path = GDSQL.RootConfig.get_table_config_path(db_name, new_table_name)
		config_file.set_value(new_table_name, "encrypted", GDSQL.RootConfig.get_table_encrypted_dek(db_name, old_table_name)) # 保留原密码
		config_file.set_value(new_table_name, "comment", comments)
		config_file.set_value(new_table_name, "valid_if_not_exist", valid_if_not_exist)
		config_file.set_value(new_table_name, "columns", column_infos)
		config_file.save(table_conf_path) # 如果新路径和旧路径一致，就会覆盖掉，也是我们所期待的
		msgs.push_back(tr("1 file: %s has been saved.") % table_conf_path)
		
		if old_table_data_path != new_table_data_path:
			var old_table_conf_path = GDSQL.RootConfig.get_table_config_path(db_name, old_table_name)
			var old_table_conf_path_abs = GDSQL.GDSQLUtils.globalize_path(old_table_conf_path)
			if FileAccess.file_exists(old_table_conf_path_abs):
				OS.move_to_trash(old_table_conf_path_abs) # 删配置
				msgs.push_back(tr("1 file: %s has been moved to trash.") % old_table_conf_path_abs)
				
		return _success(action, msgs)
		
	if new_table_data_path != old_table_data_path and FileAccess.file_exists(new_table_data_path):
		msgs.push_back(tr("Failed! File [%s] already exist!") % new_table_data_path)
		return _error_occur(action, msgs)
		
	# 检查是否有重复的字段
	var exist_col = {}
	for i in column_infos:
		if exist_col.has(i["Column Name"]):
			var msg = tr("Duplicate Column [%s].") % i["Column Name"]
			return _error_occur(action, msg)
			
		exist_col[i["Column Name"]] = true
		
	var dek = GDSQL.RootConfig.get_database_dek(db_name)
	if not dek:
		dek = GDSQL.RootConfig.get_table_dek(db_name, old_table_name)
		
	var old_table_data_file = GDSQL.ConfManager.get_conf(old_table_data_path, dek)
	var old_values = old_table_data_file.get_all_section_values() # 数据表中的旧数据
	var warnings = []
	# 数据为空就没必要检查字段了
	if not old_values.is_empty():
		var old_columns = GDSQL.RootConfig.get_table_columns(db_name, old_table_name)
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
				# 检查自增
				if not old_columns_map[col_name]["AI"] and i["AI"]:
					if not [TYPE_INT, TYPE_FLOAT].has(i["Data Type"]):
						msgs.push_back(tr("Column [%s] data type must be int or float to support auto increment!") % col_name)
						return _error_occur(action, msgs)
						
					for j: Dictionary in old_values:
						if not [TYPE_INT, TYPE_FLOAT].has(typeof(j[col_name])):
							msgs.push_back(
								tr("Old datas' field [%s] are not int or float, cannot support auto increment!") % col_name)
							return _error_occur(action, msgs)
				# 检查主键
				if i["PK"]:
					# 唯一
					var exist = {}
					for j: Dictionary in old_values:
						if exist.has(j[col_name]):
							msgs.push_back(tr("Old datas have duplicate value of primary key [%s]!") % col_name)
							return _error_occur(action, msgs)
							
						exist[j[col_name]] = true
						
				# 检查唯一
				if i["UQ"]:
					var exist = {}
					for j: Dictionary in old_values:
						if exist.has(j[col_name]):
							msgs.push_back(tr("Old datas have duplicate value of unique key [%s]!") % col_name)
							return _error_occur(action, msgs)
							
						exist[j[col_name]] = true
				# 检查非null
				if i["NN"]:
					for j: Dictionary in old_values:
						if j[col_name] == null:
							msgs.push_back(tr("Old datas have NULL value of not null key [%s]!") % col_name)
							return _error_occur(action, msgs)
							
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
			
		var config_file = ConfigFile.new()
		var table_conf_path = GDSQL.RootConfig.get_table_config_path(db_name, new_table_name)
		config_file.set_value(new_table_name, "encrypted", GDSQL.RootConfig.get_table_encrypted_dek(db_name, old_table_name)) # 保留原密码
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
			var old_table_conf_path_abs = GDSQL.GDSQLUtils.globalize_path(old_table_conf_path)
			var old_table_data_path_abs = GDSQL.GDSQLUtils.globalize_path(old_table_data_path)
			if FileAccess.file_exists(old_table_conf_path_abs):
				OS.move_to_trash(old_table_conf_path_abs) # 删配置
				msgs.push_back(tr("1 file: %s has been moved to trash.") % old_table_conf_path_abs)
			if FileAccess.file_exists(old_table_data_path_abs):
				OS.move_to_trash(old_table_data_path_abs) # 删数据
				msgs.push_back(tr("1 file: %s has been moved to trash.") % old_table_data_path_abs)
				
		return _success(action, msgs)
		
	if warnings.is_empty() or not _is_editor():
		return apply.call()
		
	_mgr_create_confirmation_dialog("\n".join(warnings), apply)
	return OK
	
func drop_table(db_name: String, table_name: String) -> Error:
	_begin_time = Time.get_unix_time_from_system()
	return await _exec_with_password_guard("DROP TABLE", db_name,
		func(): return _drop_table_impl(db_name, table_name), table_name)
		
func _drop_table_impl(db_name: String, table_name: String) -> Error:
	db_name = _validate_name(db_name)
	table_name = _validate_name(table_name)
	
	var action = "Drop table `%s`.`%s`;" % [db_name, table_name]
	var msgs = []
	
	var db_data_path = GDSQL.RootConfig.get_database_data_path(db_name)
	if db_data_path == "":
		var content = tr("Database: %s not exist!") % db_name
		return _error_occur(action, content)
		
	if not _can_path_be_modified(db_data_path):
		msgs.push_back(tr("Failed! Cannot drop a table inside the project in exported games."))
		return _error_occur(action, msgs)
		
	var databases = GDSQL.RootConfig.get_databases_info()
	if not databases.has(db_name):
		var content = tr("Database: %s not exist!") % db_name
		return _error_occur(action, content)
		
	if not databases[db_name]["tables"].has(table_name):
		var content = tr("Table: `%s`.`%s` not exist!") % [db_name, table_name]
		return _error_occur(action, content)
		
	# remove config file
	var table_conf_path = GDSQL.RootConfig.get_table_config_path(db_name, table_name)
	var conf_path = GDSQL.GDSQLUtils.globalize_path(table_conf_path)
	if FileAccess.file_exists(table_conf_path):
		OS.move_to_trash(conf_path)
		msgs.push_back(tr("1 file: %s has been moved to trash.") % conf_path)
	else:
		msgs.push_back(tr("1 file: %s could not be found when attempting to move to trash.") % conf_path)
	GDSQL.ConfManager.remove_conf(table_conf_path)
	
	# remove data file
	var data_path = GDSQL.GDSQLUtils.globalize_path(GDSQL.RootConfig.get_table_data_path(db_name, table_name))
	if FileAccess.file_exists(data_path):
		OS.move_to_trash(data_path)
		msgs.push_back(tr("1 file: %s has been moved to trash.") % data_path)
	else:
		msgs.push_back(tr("1 file: %s could not be found when attempting to move to trash.") % data_path)
		
	var dek64 = GDSQL.RootConfig.get_table_dek64(db_name, table_name)
	if dek64:
		# In case user want to revert but don't know the dek.
		if _is_editor():
			var tmp_file_path = "user://%s.%s.%s.dek" % [db_name, table_name, 
				Time.get_datetime_string_from_system(false, true).to_snake_case().replace(":", "_").validate_filename()]
			var file = FileAccess.open(tmp_file_path, FileAccess.WRITE)
			file.store_string(dek64)
			file.flush()
			file.close()
			OS.move_to_trash(GDSQL.GDSQLUtils.globalize_path(tmp_file_path))
			
		GDSQL.RootConfig.set_table_dek(db_name, table_name, null)
		GDSQL.RootConfig.save()
		msgs.push_back(tr("1 file: %s has been modified") % GDSQL.RootConfig.path)
		
	GDSQL.ConfManager.remove_conf(data_path)
	
	_mgr_sys_confirm_drop_table_emit(db_name, table_name)
	return _success(action, msgs)
	
func truncate_table(db_name: String, table_name: String) -> Error:
	_begin_time = Time.get_unix_time_from_system()
	return await _exec_with_password_guard("TRUNCATE TABLE", db_name,
		func(): return _truncate_table_impl(db_name, table_name), table_name)
		
func _truncate_table_impl(db_name: String, table_name: String) -> Error:
	db_name = _validate_name(db_name)
	table_name = _validate_name(table_name)
	
	var action = "Truncate table `%s`.`%s`;" % [db_name, table_name]
	var msgs = []
	
	var db_data_path = GDSQL.RootConfig.get_database_data_path(db_name)
	if db_data_path == "":
		var content = tr("Database: %s not exist!") % db_name
		return _error_occur(action, content)
		
	if not _can_path_be_modified(db_data_path):
		msgs.push_back(tr("Failed! Cannot truncate a table inside the project in exported games."))
		return _error_occur(action, msgs)
		
	var databases = GDSQL.RootConfig.get_databases_info()
	if not databases.has(db_name):
		var content = tr("Database: %s not exist!") % db_name
		return _error_occur(action, content)
		
	if not databases[db_name]["tables"].has(table_name):
		var content = tr("Table: `%s`.`%s` not exist!") % [db_name, table_name]
		return _error_occur(action, content)
		
	# clear data file
	var data_path = GDSQL.GDSQLUtils.globalize_path(GDSQL.RootConfig.get_table_data_path(db_name, table_name))
	if FileAccess.file_exists(data_path):
		OS.move_to_trash(data_path) # users can get their old data file in trash can
		msgs.push_back(tr("1 file: %s has been moved to trash.") % data_path)
	else:
		msgs.push_back(tr("1 file: %s could not be found when attempting to move to trash.") % data_path)
		
	# create empty file
	var data_file = ConfigFile.new()
	data_file.save(data_path)
	
	# Update cache.
	GDSQL.ConfManager.get_conf(data_path, "")._clear()
	
	var dek64 = GDSQL.RootConfig.get_database_dek64(db_name)
	if not dek64:
		dek64 = GDSQL.RootConfig.get_table_dek(db_name, table_name)
		
	if dek64:
		GDSQL.ConfManager.save_conf_by_dek(data_path, dek64)
	else:
		GDSQL.ConfManager.save_conf_by_password(data_path, "")
	msgs.push_back(tr("1 file: %s has been overwritten with an empty file.") % data_path)
	
	return _success(action, msgs)
	
func set_db_password(db_name: String, password: String) -> Error:
	_begin_time = Time.get_unix_time_from_system()
	db_name = _validate_name(db_name)
	
	var action = "ALTER DATABASE `%s` SET PASSWORD" % db_name
	var msgs = []
	
	if password == "":
		msgs.push_back(tr("Failed! Password is empty!"))
		return _error_occur(action, msgs)
		
	var db_data_path = GDSQL.RootConfig.get_database_data_path(db_name)
	if db_data_path == "":
		var content = tr("Database: %s not exist!") % db_name
		return _error_occur(action, content)
		
	if not _can_path_be_modified(db_data_path):
		msgs.push_back(tr("Failed! Cannot set database password inside the project in exported games."))
		return _error_occur(action, msgs)
		
	var databases = GDSQL.RootConfig.get_databases_info()
	if not databases.has(db_name):
		msgs.push_back(tr("Failed! Database %s not exists!") % db_name)
		return _error_occur(action, msgs)
		
	for table_name in databases[db_name]["tables"]:
		if databases[db_name]["tables"][table_name]["encrypted"] != "":
			msgs.push_back(tr("Failed! Table %s.%s is already encrypted! Must clear its password first!") % [db_name, table_name])
			return _error_occur(action, msgs)
			
	var dek64 = GDSQL.CryptoUtil.generate_dek()
	GDSQL.RootConfig.set_database_encrypted(db_name, GDSQL.CryptoUtil.encrypt_dek(dek64, password))
	GDSQL.RootConfig.set_database_dek(db_name, dek64)
	GDSQL.RootConfig.save()
	msgs.push_back(tr("1 file: %s has been modified.") % GDSQL.RootConfig.path)
	
	for table_name in databases[db_name]["tables"]:
		var table_data_path = GDSQL.RootConfig.get_table_data_path(db_name, table_name)
		var table_data_file_exist = FileAccess.file_exists(table_data_path)
		if table_data_file_exist:
			if not GDSQL.ConfManager.get_conf(table_data_path, ""): # load data
				msgs.push_back(tr("Failed! Get file %s content failed!") % table_data_path)
				return _error_occur(action, msgs)
				
	for table_name in databases[db_name]["tables"]:
		var table_data_path = GDSQL.RootConfig.get_table_data_path(db_name, table_name)
		var table_data_file_exist = FileAccess.file_exists(table_data_path)
		if table_data_file_exist:
			GDSQL.ConfManager.save_conf_by_dek(table_data_path, dek64)
			msgs.push_back(tr("1 file: %s has been encrypted.") % table_data_path)
			
		# 清除该表数据的缓存，可以让用户使用该表时必须输入密码，以加深印象
		GDSQL.ConfManager.remove_conf(table_data_path)
		
	return _success(action, msgs)
	
func change_db_password(db_name: String, password: String) -> Error:
	_begin_time = Time.get_unix_time_from_system()
	db_name = _validate_name(db_name)
	
	var action = "ALTER DATABASE `%s` CHANGE PASSWORD" % db_name
	var msgs = []
	
	if password == "":
		msgs.push_back(tr("Failed! Password is empty!"))
		return _error_occur(action, msgs)
		
	var db_data_path = GDSQL.RootConfig.get_database_data_path(db_name)
	if db_data_path == "":
		var content = tr("Database: %s not exist!") % db_name
		return _error_occur(action, content)
		
	if not _can_path_be_modified(db_data_path):
		msgs.push_back(tr("Failed! Cannot change database password inside the project in exported games."))
		return _error_occur(action, msgs)
		
	var databases = GDSQL.RootConfig.get_databases_info()
	if not databases.has(db_name):
		msgs.push_back(tr("Failed! Database %s not exists!") % db_name)
		return _error_occur(action, msgs)
		
	if databases[db_name]["encrypted"] == "":
		msgs.push_back(tr("Failed! Database %s is not encrypted!") % db_name)
		return _error_occur(action, msgs)
		
	# 修改密码不会导致dek变化，所以文件也不变化，变化的是dek的加密字符串，这样达到最大效率。
	var dek64 = GDSQL.RootConfig.get_database_dek64(db_name)
	if not dek64:
		msgs.push_back(tr("Failed! Dek of %s should not be empty!") % db_name)
		return _error_occur(action, msgs)
		
	GDSQL.RootConfig.set_database_encrypted(db_name, GDSQL.CryptoUtil.encrypt_dek(dek64, password))
	GDSQL.RootConfig.save()
	msgs.push_back(tr("1 file: %s has been modified.") % GDSQL.RootConfig.path)
	
	# 修改密码不会导致dek变化，所以文件也不变化，变化的是dek的加密字符串，这样达到最大效率。
	# 因此这里不会把数据文件重新加密。
	for table_name in databases[db_name]["tables"]:
		var table_data_path = GDSQL.RootConfig.get_table_data_path(db_name, table_name)
		GDSQL.ConfManager.remove_conf(table_data_path)
		
	return _success(action, msgs)
	
func clear_db_password(db_name: String) -> Error:
	_begin_time = Time.get_unix_time_from_system()
	db_name = _validate_name(db_name)
	
	var action = "ALTER DATABASE `%s` CLEAR PASSWORD" % db_name
	var msgs = []
	
	var db_data_path = GDSQL.RootConfig.get_database_data_path(db_name)
	if db_data_path == "":
		var content = tr("Database: %s not exist!") % db_name
		return _error_occur(action, content)
		
	if not _can_path_be_modified(db_data_path):
		msgs.push_back(tr("Failed! Cannot clear database password inside the project in exported games."))
		return _error_occur(action, msgs)
		
	var databases = GDSQL.RootConfig.get_databases_info()
	if not databases.has(db_name):
		msgs.push_back(tr("Failed! Database %s not exists!") % db_name)
		return _error_occur(action, msgs)
		
	if databases[db_name]["encrypted"] == "":
		msgs.push_back(tr("Failed! Database %s is not encrypted! No need to clear password.") % db_name)
		return _error_occur(action, msgs)
		
	var dek = GDSQL.RootConfig.get_database_dek(db_name)
	GDSQL.RootConfig.set_database_encrypted(db_name, "")
	GDSQL.RootConfig.set_database_dek(db_name, null)
	GDSQL.RootConfig.save()
	msgs.push_back(tr("1 file: %s has been modified.") % GDSQL.RootConfig.path)
	
	for table_name in databases[db_name]["tables"]:
		var table_data_path = GDSQL.RootConfig.get_table_data_path(db_name, table_name)
		var table_data_file_exist = FileAccess.file_exists(table_data_path)
		
		if table_data_file_exist:
			GDSQL.ConfManager.get_conf(table_data_path, dek)
			GDSQL.ConfManager.save_conf_by_password(table_data_path, "")
			msgs.push_back(tr("1 file: %s has been decrypted.") % table_data_path)
			
	return _success(action, msgs)
	
func set_table_password(db_name: String, table_name: String, password: String) -> Error:
	_begin_time = Time.get_unix_time_from_system()
	db_name = _validate_name(db_name)
	table_name = _validate_name(table_name)
	
	var action = "ALTER TABLE `%s`.`%s` SET PASSWORD" % [db_name, table_name]
	var msgs = []
	
	if password == "":
		msgs.push_back(tr("Failed! Password is empty!"))
		return _error_occur(action, msgs)
		
	var db_data_path = GDSQL.RootConfig.get_database_data_path(db_name)
	if db_data_path == "":
		var content = tr("Database: %s not exist!") % db_name
		return _error_occur(action, content)
		
	if not _can_path_be_modified(db_data_path):
		msgs.push_back(tr("Failed! Cannot set table password inside the project in exported games."))
		return _error_occur(action, msgs)
		
	var databases = GDSQL.RootConfig.get_databases_info()
	if not databases.has(db_name):
		msgs.push_back(tr("Failed! Database %s not exists!") % db_name)
		return _error_occur(action, msgs)
		
	if databases[db_name]["encrypted"] != "":
		msgs.push_back(tr("Failed! Database %s is already encrypted!") % db_name)
		return _error_occur(action, msgs)
		
	if not databases[db_name]["tables"].has(table_name):
		msgs.push_back(tr("Failed! Table %s.%s not exists!") % [db_name, table_name])
		return _error_occur(action, msgs)
		
	if databases[db_name]["tables"][table_name]["encrypted"] != "":
		msgs.push_back(tr("Failed! Table %s.%s is already encrypted!") % [db_name, table_name])
		return _error_occur(action, msgs)
		
	var table_conf_path = GDSQL.RootConfig.get_table_config_path(db_name, table_name)
	if not FileAccess.file_exists(table_conf_path):
		msgs.push_back(tr("Failed! Table conf %s does not exist!") % table_conf_path)
		return _error_occur(action, msgs)
		
	var table_data_path = GDSQL.GDSQLUtils.globalize_path(GDSQL.RootConfig.get_table_data_path(db_name, table_name))
	var dek64 = GDSQL.CryptoUtil.generate_dek()
	var config_file = ConfigFile.new()
	config_file.load(table_conf_path)
	config_file.set_value(table_name, "encrypted", GDSQL.CryptoUtil.encrypt_dek(dek64, password))
	config_file.save(table_conf_path)
	msgs.push_back(tr("1 file: %s has been saved.") % table_conf_path)
	
	GDSQL.RootConfig.set_table_dek(db_name, table_name, dek64)
	GDSQL.RootConfig.save()
	msgs.push_back(tr("1 file: %s has been modified.") % GDSQL.RootConfig.path)
	
	var table_data_file_exist = FileAccess.file_exists(table_data_path)
	if table_data_file_exist:
		if not GDSQL.ConfManager.get_conf(table_data_path, ""): # load data
			msgs.push_back(tr("Failed! Get file %s content failed!") % table_data_path)
			return _error_occur(action, msgs)
			
		GDSQL.ConfManager.save_conf_by_dek(table_data_path, dek64)
		msgs.push_back(tr("1 file: %s has been encrypted.") % table_data_path)
		
	# 清除该表数据的缓存，可以让用户使用该表时必须输入密码，以加深印象
	GDSQL.ConfManager.remove_conf(table_data_path)
	
	return _success(action, msgs)
	
func change_table_password(db_name: String, table_name: String, password: String) -> Error:
	_begin_time = Time.get_unix_time_from_system()
	db_name = _validate_name(db_name)
	table_name = _validate_name(table_name)
	
	var action = "ALTER TABLE `%s`.`%s` CHANGE PASSWORD" % [db_name, table_name]
	var msgs = []
	
	if password == "":
		msgs.push_back(tr("Failed! Password is empty!"))
		return _error_occur(action, msgs)
		
	var db_data_path = GDSQL.RootConfig.get_database_data_path(db_name)
	if db_data_path == "":
		var content = tr("Database: %s not exist!") % db_name
		return _error_occur(action, content)
		
	if not _can_path_be_modified(db_data_path):
		msgs.push_back(tr("Failed! Cannot change table password inside the project in exported games."))
		return _error_occur(action, msgs)
		
	var databases = GDSQL.RootConfig.get_databases_info()
	if not databases.has(db_name):
		msgs.push_back(tr("Failed! Database %s not exists!") % db_name)
		return _error_occur(action, msgs)
		
	if not databases[db_name]["tables"].has(table_name):
		msgs.push_back(tr("Failed! Table %s.%s not exists!") % [db_name, table_name])
		return _error_occur(action, msgs)
		
	if databases[db_name]["tables"][table_name]["encrypted"] == "":
		msgs.push_back(tr("Failed! Table %s.%s is not encrypted!") % [db_name, table_name])
		return _error_occur(action, msgs)
		
	var table_conf_path = GDSQL.RootConfig.get_table_config_path(db_name, table_name)
	if not FileAccess.file_exists(table_conf_path):
		msgs.push_back(tr("Failed! Table conf %s does not exist!") % table_conf_path)
		return _error_occur(action, msgs)
		
	var dek = GDSQL.RootConfig.get_table_dek64(db_name, table_name)
	if not dek:
		msgs.push_back(tr("Failed! Dek of %s.%s should not be empty!") % [db_name, table_name])
		return _error_occur(action, msgs)
		
	var config_file = ConfigFile.new()
	config_file.load(table_conf_path)
	config_file.set_value(table_name, "encrypted", GDSQL.CryptoUtil.encrypt_dek(dek, password))
	config_file.save(table_conf_path)
	msgs.push_back(tr("1 file: %s has been saved.") % table_conf_path)
	
	# 修改密码不会导致dek变化，所以文件也不变化，变化的是dek的加密字符串，这样达到最大效率。
	# 因此这里不会把数据文件重新加密。
	# 清除该表数据的缓存，可以让用户使用该表时必须输入密码，以加深印象
	var table_data_path = GDSQL.GDSQLUtils.globalize_path(GDSQL.RootConfig.get_table_data_path(db_name, table_name))
	GDSQL.ConfManager.remove_conf(table_data_path)
	
	return _success(action, msgs)
	
func clear_table_password(db_name: String, table_name: String) -> Error:
	_begin_time = Time.get_unix_time_from_system()
	db_name = _validate_name(db_name)
	table_name = _validate_name(table_name)
	
	var action = "ALTER TABLE `%s`.`%s` CLEAR PASSWORD" % [db_name, table_name]
	var msgs = []
	
	var db_data_path = GDSQL.RootConfig.get_database_data_path(db_name)
	if db_data_path == "":
		var content = tr("Database: %s not exist!") % db_name
		return _error_occur(action, content)
		
	if not _can_path_be_modified(db_data_path):
		msgs.push_back(tr("Failed! Cannot clear table password inside the project in exported games."))
		return _error_occur(action, msgs)
		
	var databases = GDSQL.RootConfig.get_databases_info()
	if not databases.has(db_name):
		msgs.push_back(tr("Failed! Database %s not exists!") % db_name)
		return _error_occur(action, msgs)
		
	if not databases[db_name]["tables"].has(table_name):
		msgs.push_back(tr("Failed! Table %s.%s not exists!") % [db_name, table_name])
		return _error_occur(action, msgs)
		
	if databases[db_name]["tables"][table_name]["encrypted"] == "":
		msgs.push_back(tr("Failed! Table %s.%s is not encrypted! No need to clear password.") % [db_name, table_name])
		return _error_occur(action, msgs)
		
	var table_conf_path = GDSQL.RootConfig.get_table_config_path(db_name, table_name)
	if not FileAccess.file_exists(table_conf_path):
		msgs.push_back(tr("Failed! Table conf %s does not exist!") % table_conf_path)
		return _error_occur(action, msgs)
		
	var table_data_path = GDSQL.GDSQLUtils.globalize_path(GDSQL.RootConfig.get_table_data_path(db_name, table_name))
	var dek = GDSQL.RootConfig.get_table_dek(db_name, table_name)
	if not dek:
		msgs.push_back(tr("Failed! Dek of %s.%s should not be empty!") % [db_name, table_name])
		return _error_occur(action, msgs)
		
	var config_file = ConfigFile.new()
	config_file.load(table_conf_path)
	config_file.set_value(table_name, "encrypted", "")
	config_file.save(table_conf_path)
	msgs.push_back(tr("1 file: %s has been saved.") % table_conf_path)
	
	GDSQL.RootConfig.set_table_dek(db_name, table_name, null)
	GDSQL.RootConfig.save()
	msgs.push_back(tr("1 file: %s has been modified.") % GDSQL.RootConfig.path)
	
	var table_data_file_exist = FileAccess.file_exists(table_data_path)
	if table_data_file_exist:
		GDSQL.ConfManager.get_conf(table_data_path, dek)
		GDSQL.ConfManager.save_conf_by_password(table_data_path, "")
		msgs.push_back(tr("1 file: %s has been decrypted.") % table_data_path)
		
	return _success(action, msgs)
	
func _is_project_path(path: String) -> bool:
	return path.begins_with("res://")
	
func _can_path_be_modified(path: String) -> bool:
	return not (_is_project_path(path) and _is_editor())
	
func _remove_table_files(db_name: String, table_name: String) -> void:
	var conf_path = GDSQL.RootConfig.get_table_config_path(db_name, table_name)
	var abs_conf_path = GDSQL.GDSQLUtils.globalize_path(conf_path)
	if FileAccess.file_exists(abs_conf_path):
		OS.move_to_trash(abs_conf_path)
	GDSQL.ConfManager.remove_conf(abs_conf_path)
	
	var data_path = GDSQL.RootConfig.get_table_data_path(db_name, table_name)
	var abs_data_path = GDSQL.GDSQLUtils.globalize_path(data_path)
	if FileAccess.file_exists(abs_data_path):
		OS.move_to_trash(abs_data_path)
	GDSQL.ConfManager.remove_conf(abs_data_path)
	
	if _is_editor():
		var dek64 = GDSQL.RootConfig.get_table_dek64(db_name, table_name)
		if dek64:
			var ts = Time.get_datetime_string_from_system(false, true).to_snake_case().replace(":", "_").validate_filename()
			var tmp_path = "user://%s.%s.%s.dek" % [db_name, table_name, ts]
			var f = FileAccess.open(tmp_path, FileAccess.WRITE)
			f.store_string(dek64)
			f.flush()
			f.close()
			OS.move_to_trash(GDSQL.GDSQLUtils.globalize_path(tmp_path))
