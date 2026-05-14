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

# ----- Helper -----

func _validate_name(name: String) -> String:
	return GDSQL.RootConfig.validate_name(name)
	
func _is_valid_name(name: String) -> bool:
	return name != GDSQL.RootConfig.DEK and (name.is_valid_ascii_identifier() or name.is_valid_unicode_identifier())
	
func _is_editor() -> bool:
	return Engine.is_editor_hint()
	
func _get_mgr() -> GDSQL.WorkbenchManagerClass:
	return GDSQL.WorkbenchManager if _is_editor() else null
	
func _log(action: String, msgs, err: bool = false) -> void:
	var mgr = _get_mgr()
	if mgr:
		mgr.add_log_history.emit("Err" if err else "OK", Time.get_unix_time_from_system(), action, msgs)
		
func _assert_false(action: String, msg: String) -> Error:
	var mgr = _get_mgr()
	if mgr:
		mgr.create_accept_dialog(msg)
		mgr.add_log_history.emit("Err", Time.get_unix_time_from_system(), action, msg)
	push_error(msg)
	return ERR_PARSE_ERROR
	
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
				_assert_false("password", "Incorrect password!")
				return ERR_UNAUTHORIZED
	elif typeof(_password) == TYPE_PACKED_BYTE_ARRAY:
		# DDL 涉及表的操作，需要先load一下表
		if _password and not table_name.is_empty():
			var conf = GDSQL.ConfManager.get_conf(GDSQL.RootConfig.get_table_data_path(db_name, table_name), _password)
			if not conf:
				_assert_false("password", "Incorrect password!")
				return ERR_UNAUTHORIZED
	else:
		var encrypted_dek = GDSQL.RootConfig.get_database_encrypted_dek(db_name)
		if encrypted_dek == "":
			encrypted_dek = GDSQL.RootConfig.get_table_encrypted_dek(db_name, table_name)
			if encrypted_dek == "":
				# 本来没密码，非要输入一个错的密码，也不行。
				_assert_false("password", "Incorrect password!")
				return ERR_UNAUTHORIZED
		var recovered_dek = GDSQL.CryptoUtil.decrypt_dek(encrypted_dek, _password)
		# DDL 涉及表的操作，需要先load一下表
		if recovered_dek and not table_name.is_empty():
			var conf = GDSQL.ConfManager.get_conf(GDSQL.RootConfig.get_table_data_path(db_name, table_name), recovered_dek)
			if not conf:
				_assert_false("password", "Incorrect password!")
				return ERR_UNAUTHORIZED
		else:
			_assert_false("password", "Incorrect password!")
			return ERR_UNAUTHORIZED
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
					mgr.add_log_history.emit("Err", Time.get_unix_time_from_system(),
						action_name, "Missing password!")
			return ERR_UNAUTHORIZED
		else:
			return action_impl.call()
	if reach_max:
		return _assert_false(action_name, "Too many password attempts!")
	return ERR_UNAUTHORIZED
	
# ----- Database Operations -----
	
## Create a new database.
func create_database(name: String, path: String) -> Error:
	return await _exec_with_password_guard("CREATE DATABASE", name,
		func(): return _create_database_impl(name, path))
		
func _create_database_impl(name: String, path: String) -> Error:
	name = _validate_name(name)
	
	if not _is_valid_name(name):
		return _assert_false("CREATE DATABASE", "Invalid database name: " + name)
		
	var dbs = GDSQL.RootConfig.get_databases_info()
	if dbs.has(name):
		return _assert_false("CREATE DATABASE", "Database already exists: " + name)
	for db_name in dbs:
		if dbs[db_name]["data_path"] == path:
			return _assert_false("CREATE DATABASE", "Path already in use: " + path)
			
	GDSQL.RootConfig.set_database_data(name, path, "")
	GDSQL.RootConfig.save()
	
	var msgs = []
	msgs.push_back("1 file: %s has been modified." % GDSQL.RootConfig.path)
	
	var dir = DirAccess.open(GDSQL.RootConfig.get_base_dir())
	if dir == null:
		return _assert_false("CREATE DATABASE", "Cannot open config root: " + GDSQL.RootConfig.get_base_dir())
		
	var config_path = GDSQL.RootConfig.get_database_config_path(name)
	if not dir.dir_exists(config_path):
		var err = dir.make_dir_recursive(config_path)
		if err != OK:
			return _assert_false("CREATE DATABASE", "Cannot make dir %s! Err: %s." % [config_path, err])
		msgs.push_back("Dir: %s has been made." % config_path)
		
	_log("CREATE DATABASE", msgs, false)
	return OK
	
## Rename a database.
func alter_database(old_name: String, new_name: String) -> Error:
	return await _exec_with_password_guard("ALTER DATABASE", old_name,
		func(): return _alter_database_impl(old_name, new_name))
		
func _alter_database_impl(old_name: String, new_name: String) -> Error:
	old_name = _validate_name(old_name)
	new_name = _validate_name(new_name)
	
	if not _is_valid_name(new_name):
		return _assert_false("ALTER DATABASE", "Invalid new database name: " + new_name)
	if old_name == new_name:
		return _assert_false("ALTER DATABASE", "Nothing changed!")
		
	var dbs = GDSQL.RootConfig.get_databases_info()
	if not dbs.has(old_name):
		return _assert_false("ALTER DATABASE", "Database not found: " + old_name)
	if dbs.has(new_name):
		return _assert_false("ALTER DATABASE", "Database name has been occupied: " + new_name)
		
	var data = dbs[old_name].duplicate(true)
	var old_path = GDSQL.RootConfig.get_database_config_path(old_name)
	var new_path = GDSQL.RootConfig.get_database_config_path(new_name)
	
	if DirAccess.dir_exists_absolute(old_path):
		var err = DirAccess.rename_absolute(old_path, new_path)
		if err != OK:
			return _assert_false("ALTER DATABASE", "Cannot rename config dir!")
			
	var old_data_path = data.get("data_path", "")
	if not old_data_path.is_empty() and DirAccess.dir_exists_absolute(old_data_path):
		var old_cfg_dir = GDSQL.RootConfig.get_database_config_path(old_name)
		if old_data_path != old_cfg_dir:
			var new_data_dir = GDSQL.RootConfig.get_database_data_path(new_name)
			DirAccess.make_dir_recursive_absolute(new_data_dir)
			var dir = DirAccess.open(old_data_path)
			if dir:
				dir.list_dir_begin()
				var fn = dir.get_next()
				while fn != "":
					if fn.ends_with(GDSQL.RootConfig.CONFIG_EXTENSION) or fn.ends_with(GDSQL.RootConfig.DATA_EXTENSION):
						DirAccess.copy_absolute(old_data_path.path_join(fn), new_data_dir.path_join(fn))
					fn = dir.get_next()
					
	var dek64 = GDSQL.RootConfig.get_database_dek64(old_name)
	var pw = data.get("password", "")
	GDSQL.RootConfig.set_database_data(new_name, data.get("data_path", ""), pw)
	if dek64:
		GDSQL.RootConfig.set_database_dek(new_name, Marshalls.raw_to_base64(dek64))
	GDSQL.RootConfig.erase_database(old_name)
	GDSQL.RootConfig.save()
	
	_log("ALTER DATABASE", "Database renamed: %s -> %s" % [old_name, new_name], false)
	return OK
	
## Delete a database.
func drop_database(name: String) -> Error:
	return await _exec_with_password_guard("DROP DATABASE", name,
		func(): return _drop_database_impl(name))
		
func _drop_database_impl(name: String) -> Error:
	name = _validate_name(name)
	
	var dbs = GDSQL.RootConfig.get_databases_info()
	if not dbs.has(name):
		return _assert_false("DROP DATABASE", "Database not found: " + name)
		
	var tables = dbs[name].get("tables", {})
	for table_name in tables:
		_remove_table_files(name, table_name)
		
	var cfg_dir = GDSQL.GDSQLUtils.globalize_path(GDSQL.RootConfig.get_database_config_path(name))
	if DirAccess.dir_exists_absolute(cfg_dir):
		OS.move_to_trash(cfg_dir)
		
	var dek64 = GDSQL.RootConfig.get_database_dek64(name)
	if dek64:
		GDSQL.RootConfig.set_database_dek(name, null)
	GDSQL.RootConfig.erase_database(name)
	GDSQL.RootConfig.save()
	
	_log("DROP DATABASE", "Database deleted: " + name, false)
	return OK
	
# ----- Table Operations -----
	
func create_table(db_name: String, table_name: String, column_infos: Array,
		comment: String = "", password: String = "", valid_if_not_exist: bool = false) -> Error:
	return await _exec_with_password_guard("CREATE TABLE", db_name,
		func(): return _create_table_impl(db_name, table_name, column_infos, comment, password, valid_if_not_exist),
		table_name)
		
func _create_table_impl(db_name: String, table_name: String, column_infos: Array,
		comment: String = "", password: String = "", valid_if_not_exist: bool = false) -> Error:
	db_name = _validate_name(db_name)
	table_name = _validate_name(table_name)
	
	var dbs = GDSQL.RootConfig.get_databases_info()
	if not dbs.has(db_name):
		return _assert_false("CREATE TABLE", "Database not found: " + db_name)
	if dbs[db_name].get("tables", {}).has(table_name):
		return _assert_false("CREATE TABLE", "Table already exists: " + table_name)
	if column_infos.is_empty():
		return _assert_false("CREATE TABLE", "No columns defined")
		
	var primarys = []
	var action = "CREATE TABLE `%s`.`%s` (" % [db_name, table_name]
	for i in column_infos:
		action += "\n    `%s` %s%s%s%s%s%s%s," % [
			i["Column Name"],
			type_string(i["Data Type"]),
			" NOT NULL" if i["NN"] else "",
			" AUTO_INCREMENT" if i["AI"] else "",
			" UNIQUE" if i["UQ"] else "",
			" INDEX" if i.get("Index", false) else "",
			(" DEFAULT %s" % i["Default(Expression)"]) if i.get("Default(Expression)", "") != "" else "",
			" COMMENT '%s'" % i["Comment"].c_escape() if i.get("Comment", "") != "" else ""
		]
		if i["PK"]:
			primarys.push_back(i["Column Name"])
	action += "\n    PRIMARY KEY (%s)\n)" % ",".join(primarys.map(func(v): return "`%s`" % v))
	action += ";" if comment.is_empty() else " COMMENT '%s';" % comment.c_escape()
	
	var col_names = []
	for i in column_infos:
		var cn = i.get("Column Name", "")
		if cn in col_names:
			return _assert_false(action, "Duplicate column name: " + cn)
		col_names.append(cn)
		
	var table_conf_path = GDSQL.RootConfig.get_table_config_path(db_name, table_name)
	var msgs = []
	
	var _path = GDSQL.GDSQLUtils.globalize_path(table_conf_path)
	if FileAccess.file_exists(_path):
		return _assert_false(action, "Table config file already exists: " + _path)
		
	var conf: GDSQL.ImprovedConfigFile
	if password.is_empty():
		conf = GDSQL.ConfManager.get_conf(table_conf_path, "")
	else:
		var dek = GDSQL.RootConfig.get_database_dek64(db_name)
		if dek:
			conf = GDSQL.ConfManager.create_conf(table_conf_path, password)
		else:
			conf = GDSQL.ConfManager.get_conf(table_conf_path, password)
			
	if conf == null:
		return _assert_false(action, "Cannot create table config!")
		
	conf.set_value(table_name, "columns", column_infos)
	conf.set_value(table_name, "valid_if_not_exist", valid_if_not_exist)
	conf.set_value(table_name, "comment", comment)
	
	if password.is_empty():
		conf.save(table_conf_path)
	else:
		conf.save_encrypted_pass(table_conf_path, password)
		
	msgs.push_back("1 file: %s has been modified." % table_conf_path)
	
	GDSQL.RootConfig.set_table_data(db_name, table_name, column_infos, comment, password, valid_if_not_exist)
	GDSQL.RootConfig.save()
	
	_log(action, msgs, false)
	return OK
	
func alter_table(db_name: String, old_name: String, new_name: String,
		column_infos: Array, comments: String = "",
		valid_if_not_exist: bool = false) -> Error:
	return await _exec_with_password_guard("ALTER TABLE", db_name,
		func(): return _alter_table_impl(db_name, old_name, new_name, column_infos, comments, valid_if_not_exist),
		old_name)
		
func _alter_table_impl(db_name: String, old_name: String, new_name: String,
		column_infos: Array, comments: String = "",
		valid_if_not_exist: bool = false) -> Error:
	db_name = _validate_name(db_name)
	old_name = _validate_name(old_name)
	new_name = _validate_name(new_name)
	
	var dbs = GDSQL.RootConfig.get_databases_info()
	if not dbs.has(db_name):
		return _assert_false("ALTER TABLE", "Database not found: " + db_name)
	if not dbs[db_name].get("tables", {}).has(old_name):
		return _assert_false("ALTER TABLE", "Table not found: " + old_name)
	if old_name != new_name and dbs[db_name].get("tables", {}).has(new_name):
		return _assert_false("ALTER TABLE", "New table name already exists: " + new_name)
		
	var old_conf_path = GDSQL.RootConfig.get_table_config_path(db_name, old_name)
	GDSQL.ConfManager.remove_conf(old_conf_path)
	
	if old_name != new_name:
		var new_cfg_path = GDSQL.RootConfig.get_table_config_path(db_name, new_name)
		if FileAccess.file_exists(old_conf_path):
			DirAccess.rename_absolute(old_conf_path, new_cfg_path)
		var old_data_path = GDSQL.RootConfig.get_table_data_path(db_name, old_name)
		var new_data_path = GDSQL.RootConfig.get_table_data_path(db_name, new_name)
		if FileAccess.file_exists(old_data_path):
			DirAccess.rename_absolute(old_data_path, new_data_path)
		GDSQL.RootConfig.erase_table(db_name, old_name)
		
	var table_conf_path = GDSQL.RootConfig.get_table_config_path(db_name, new_name)
	var msgs = []
	var conf: GDSQL.ImprovedConfigFile
	var pw = dbs[db_name].get("tables", {}).get(new_name if old_name != new_name else old_name, {}).get("password", "")
	
	if pw.is_empty():
		conf = GDSQL.ConfManager.get_conf(table_conf_path, "")
		if conf:
			conf.set_value(new_name, "columns", column_infos)
			conf.set_value(new_name, "comment", comments)
			conf.set_value(new_name, "valid_if_not_exist", valid_if_not_exist)
			conf.save(table_conf_path)
	else:
		conf = GDSQL.ConfManager.get_conf(table_conf_path, "")
		if conf:
			conf.set_value(new_name, "columns", column_infos)
			conf.save_encrypted_pass(table_conf_path, pw)
			
	GDSQL.RootConfig.set_table_data(db_name, new_name, column_infos, comments, pw, valid_if_not_exist)
	GDSQL.RootConfig.save()
	
	_log("ALTER TABLE", msgs, false)
	return OK
	
func drop_table(db_name: String, table_name: String) -> Error:
	return await _exec_with_password_guard("DROP TABLE", db_name,
		func(): return _drop_table_impl(db_name, table_name), table_name)
		
func _drop_table_impl(db_name: String, table_name: String) -> Error:
	db_name = _validate_name(db_name)
	table_name = _validate_name(table_name)
	
	var dbs = GDSQL.RootConfig.get_databases_info()
	if not dbs.has(db_name):
		return _assert_false("DROP TABLE", "Database not found: " + db_name)
	if not dbs[db_name].get("tables", {}).has(table_name):
		return _assert_false("DROP TABLE", "Table not found: " + table_name)
		
	_remove_table_files(db_name, table_name)
	GDSQL.RootConfig.erase_table(db_name, table_name)
	GDSQL.RootConfig.save()
	
	_log("DROP TABLE", "Table deleted: " + table_name, false)
	return OK
	
func truncate_table(db_name: String, table_name: String) -> Error:
	return await _exec_with_password_guard("TRUNCATE TABLE", db_name,
		func(): return _truncate_table_impl(db_name, table_name), table_name)
		
func _truncate_table_impl(db_name: String, table_name: String) -> Error:
	db_name = _validate_name(db_name)
	table_name = _validate_name(table_name)
	
	var dbs = GDSQL.RootConfig.get_databases_info()
	if not dbs.has(db_name):
		return _assert_false("TRUNCATE TABLE", "Database not found: " + db_name)
	if not dbs[db_name].get("tables", {}).has(table_name):
		return _assert_false("TRUNCATE TABLE", "Table not found: " + table_name)
		
	var data_path = GDSQL.GDSQLUtils.globalize_path(GDSQL.RootConfig.get_table_data_path(db_name, table_name))
	if FileAccess.file_exists(data_path):
		OS.move_to_trash(data_path)
		
	_log("TRUNCATE TABLE", "Table truncated: " + table_name, false)
	return OK
	
# ----- Password Operations -----
	
func set_db_password(db_name: String, password: String) -> Error:
	db_name = _validate_name(db_name)
	
	var dbs = GDSQL.RootConfig.get_databases_info()
	if not dbs.has(db_name):
		return _assert_false("SET PASSWORD", "Database not found: " + db_name)
		
	GDSQL.RootConfig.set_database_data(db_name, dbs[db_name].get("data_path", ""), password)
	GDSQL.RootConfig.save()
	
	_log("SET PASSWORD", "Database password set", false)
	return OK
	
func change_db_password(db_name: String, new_password: String) -> Error:
	return set_db_password(db_name, new_password)
	
func clear_db_password(db_name: String) -> Error:
	return set_db_password(db_name, "")
	
func set_table_password(db_name: String, table_name: String, password: String) -> Error:
	db_name = _validate_name(db_name)
	table_name = _validate_name(table_name)
	
	var dbs = GDSQL.RootConfig.get_databases_info()
	if not dbs.has(db_name):
		return _assert_false("SET PASSWORD", "Database not found: " + db_name)
	if not dbs[db_name].get("tables", {}).has(table_name):
		return _assert_false("SET PASSWORD", "Table not found: " + table_name)
		
	var data_path = GDSQL.RootConfig.get_table_data_path(db_name, table_name)
	var conf_path = GDSQL.RootConfig.get_table_config_path(db_name, table_name)
	
	if password.is_empty():
		GDSQL.ConfManager.save_conf_by_origin_password_or_dek(conf_path)
		GDSQL.ConfManager.save_conf_by_origin_password_or_dek(data_path)
	else:
		GDSQL.ConfManager.save_conf_by_password(conf_path, password)
		GDSQL.ConfManager.save_conf_by_password(data_path, password)
		
	GDSQL.RootConfig.set_table_password(db_name, table_name, password)
	GDSQL.RootConfig.save()
	
	_log("SET PASSWORD", "Table password set", false)
	return OK
	
func change_table_password(db_name: String, table_name: String, new_password: String) -> Error:
	return set_table_password(db_name, table_name, new_password)
	
func clear_table_password(db_name: String, table_name: String) -> Error:
	return set_table_password(db_name, table_name, "")
	
# ----- Private -----
	
func _is_project_path(path: String) -> bool:
	return path.begins_with("res://")
	
func _remove_table_files(db_name: String, table_name: String) -> void:
	var conf_path = GDSQL.RootConfig.get_table_config_path(db_name, table_name)
	var abs_conf = GDSQL.GDSQLUtils.globalize_path(conf_path)
	if FileAccess.file_exists(conf_path):
		if _is_project_path(conf_path) and _is_editor():
			OS.move_to_trash(abs_conf)
		elif not _is_project_path(conf_path):
			OS.move_to_trash(abs_conf)
	GDSQL.ConfManager.remove_conf(conf_path)
	
	var data_path = GDSQL.RootConfig.get_table_data_path(db_name, table_name)
	var abs_data = GDSQL.GDSQLUtils.globalize_path(data_path)
	if FileAccess.file_exists(data_path):
		if _is_project_path(data_path) and _is_editor():
			OS.move_to_trash(abs_data)
		elif not _is_project_path(data_path):
			OS.move_to_trash(abs_data)
			
	var dek64 = GDSQL.RootConfig.get_table_dek64(db_name, table_name)
	if dek64:
		var ts = Time.get_datetime_string_from_system(false, true).to_snake_case().replace(":", "_").validate_filename()
		var tmp_path = "user://%s.%s.%s.dek" % [db_name, table_name, ts]
		var f = FileAccess.open(tmp_path, FileAccess.WRITE)
		f.store_string(dek64)
		f.flush()
		f.close()
		OS.move_to_trash(GDSQL.GDSQLUtils.globalize_path(tmp_path))
