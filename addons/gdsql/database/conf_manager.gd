# Must not be a RefCounted, because this obj is registered in Engine singleton which does not count a reference!
# Must not be a pure Object, because will crash when close game.
extends Node

var _conf_map: Dictionary = { }
var _conf_modified_time: Dictionary = { } # detects external config file updates
var _passwords: Dictionary = { } # {path: String|PackedByteArray}
var _valid_if_not_exist_path = []

## ── Global transaction support ──

## Whether a transaction is active. When active, all save_conf_* calls are intercepted
## and changes remain only in the _conf_map in-memory cache.
var _transaction_active := false
## Table paths modified during the transaction, used by commit to flush one by one
## and by rollback to clear from cache.
var _transaction_modified_paths: Array[String] = []


## Start a global transaction. All subsequent DAO/mapper writes go to the
## in-memory buffer only, without flushing to disk.
func begin_transaction() -> void:
	_transaction_active = true
	_transaction_modified_paths.clear()


## Commit the global transaction: flush all modified table files to disk.
func commit_transaction() -> void:
	_transaction_active = false
	for path in _transaction_modified_paths:
		save_conf_by_origin_password_or_dek(path)
	_transaction_modified_paths.clear()


## Rollback the global transaction: discard all in-memory cache changes;
## next access will reload from disk.
func rollback_transaction() -> void:
	_transaction_active = false
	for path in _transaction_modified_paths:
		_conf_map.erase(path)
	_transaction_modified_paths.clear()


## Mark a path as valid even when the file does not yet exist (treat as empty config).
func mark_valid_if_not_exit(path: String) -> void:
	# Use absolute path to prevent multiple config instances for the same file via different path forms
	path = GDSQL.GDSQLUtils.globalize_path(path)
	if not _valid_if_not_exist_path.has(path):
		_valid_if_not_exist_path.push_back(path)


func mark_invalid_if_not_exist(path: String) -> void:
	path = GDSQL.GDSQLUtils.globalize_path(path)
	_valid_if_not_exist_path.erase(path)


## Get a config: the config file must already exist.
func get_conf(path: String, password) -> GDSQL.ImprovedConfigFile:
	# Use absolute path to prevent multiple config instances for the same file via different path forms
	path = GDSQL.GDSQLUtils.globalize_path(path)

	if _conf_map.has(path):
		return _conf_map.get(path)

	var conf := GDSQL.ImprovedConfigFile.new()
	var exist = GDSQL.GDSQLUtils.file_exists(path)
	if not exist and _valid_if_not_exist_path.has(path):
		_passwords[path] = password
		_conf_map[path] = conf
		return conf

	if not exist:
		assert(false, "file:[%s] not exist" % path)
		return null

	var err = OK
	if password.is_empty():
		err = conf.load2(path)
	elif password is PackedByteArray:
		err = conf.load_encrypted2(path, password)
	else:
		err = conf.load_encrypted_pass2(path, password)

	if err != OK:
		assert(false, "conf load failed! err:%s(%s), `%s`:`%s`" % [err, error_string(err), path, password])
		return null

	if password.is_empty() and conf.get_sections().is_empty():
		if ClassDB.class_has_method(&"FileAccess", &"get_size", true):
			if ClassDB.class_call_static(&"FileAccess", &"get_size", path) > 0:
				assert(false, "conf load failed! file [%s] is encrypted! " % path)
				return null
		else:
			if not FileAccess.get_file_as_bytes(path).is_empty():
				assert(false, "conf load failed! file [%s] is encrypted! " % path)
				return null

	#var fa = FileAccess.open(path, FileAccess.READ)
	#if password.is_empty() and fa.get_length() > 0:
	#assert(not conf.get_sections().is_empty(), "conf load failed! file [%s] is encrypted! " % path)
	#return null

	_passwords[path] = password
	_conf_map[path] = conf
	if OS.has_feature("editor"):
		_conf_modified_time[path] = FileAccess.get_modified_time(path)
	return conf


## Create and get a config: the config file must NOT already exist.
func create_conf(path: String, password) -> GDSQL.ImprovedConfigFile:
	path = GDSQL.GDSQLUtils.globalize_path(path)
	if GDSQL.GDSQLUtils.file_exists(path):
		assert(false, "file:[%s] already exist" % path)
		return null

	var conf := GDSQL.ImprovedConfigFile.new()
	_passwords[path] = password
	_conf_map[path] = conf
	return conf


func has_conf(path: String) -> bool:
	path = GDSQL.GDSQLUtils.globalize_path(path)
	return _conf_map.has(path)


func remove_conf(path: String):
	path = GDSQL.GDSQLUtils.globalize_path(path)
	_conf_map.erase(path)
	if OS.has_feature("editor"):
		_conf_modified_time.erase(path)


func save_conf_by_origin_password_or_dek(path: String):
	path = GDSQL.GDSQLUtils.globalize_path(path)
	# When a transaction is active: intercept disk writes, only record modified paths
	if _transaction_active:
		if not _transaction_modified_paths.has(path):
			_transaction_modified_paths.append(path)
		return
	if not has_conf(path):
		assert(false, "this conf %s is not under control" % path)
		return
	var conf = get_conf(path, "")
	if _passwords[path].is_empty():
		conf.save2(path)
	elif _passwords[path] is PackedByteArray:
		conf.save_encrypted2(path, _passwords[path])
	else:
		conf.save_encrypted_pass2(path, _passwords[path])

	if OS.has_feature("editor"):
		_conf_modified_time[path] = FileAccess.get_modified_time(path)


## NOTICE unsafe
func save_conf_by_same_password_or_dek(path: String, ref_path: String):
	path = GDSQL.GDSQLUtils.globalize_path(path)
	ref_path = GDSQL.GDSQLUtils.globalize_path(ref_path)
	if not has_conf(path):
		assert(path, "this conf %s is not under control" % path)
		return
	if not has_conf(ref_path):
		assert(false, "this conf %s is not under control" % ref_path)
		return
	var conf = get_conf(path, "")
	_passwords[path] = _passwords[ref_path]
	if _passwords[ref_path].is_empty():
		conf.save2(path)
	elif _passwords[path] is PackedByteArray:
		conf.save_encrypted2(path, _passwords[path])
	else:
		conf.save_encrypted_pass2(path, _passwords[path])

	if OS.has_feature("editor"):
		_conf_modified_time[path] = FileAccess.get_modified_time(path)


func save_conf_by_dek(path: String, dek: String):
	var dek_raw = Marshalls.base64_to_raw(dek)
	save_conf_by_password(path, dek_raw)


func save_conf_by_password(path: String, password):
	path = GDSQL.GDSQLUtils.globalize_path(path)
	if not has_conf(path):
		assert(false, "this conf %s is not under control" % path)
		return
	var conf = get_conf(path, "")

	_passwords[path] = password
	if _passwords[path].is_empty():
		conf.save2(path)
	elif _passwords[path] is PackedByteArray:
		conf.save_encrypted2(path, _passwords[path])
	else:
		conf.save_encrypted_pass2(path, _passwords[path])

	if OS.has_feature("editor"):
		_conf_modified_time[path] = FileAccess.get_modified_time(path)


func set_conf_indexed_props(path: String, indexed_names: Array):
	path = GDSQL.GDSQLUtils.globalize_path(path)
	if not has_conf(path):
		assert(false, "this conf %s is not under control" % path)
		return
	var conf = get_conf(path, "")
	conf.set_indexed_props(indexed_names)
