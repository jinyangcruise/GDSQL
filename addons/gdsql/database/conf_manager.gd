# Must not be a RefCounted, because this obj is registered in Engine singleton which does not count a reference!
# Must not be a pure Object, because will crash when close game.
extends Node

var _conf_map: Dictionary = {}
var _conf_modified_time: Dictionary = {} # 用于检测外部工具对配置的更新
var _passwords: Dictionary = {}
var _valid_if_not_exist_path = []

## 标记某路径在不存在时，可以当作一个空配置
func mark_valid_if_not_exit(path: String) -> void:
	# 使用绝对路径，防止用户对同一个文件使用不同形式的路径导致获得了多个配置实例
	path = GDSQL.GDSQLUtils.globalize_path(path)
	if not _valid_if_not_exist_path.has(path):
		_valid_if_not_exist_path.push_back(path)

## 获取配置：前提是该配置的文件是存在的
func get_conf(path: String, password: String) -> GDSQL.ImprovedConfigFile:
	# 使用绝对路径，防止用户对同一个文件使用不同形式的路径导致获得了多个配置实例
	path = GDSQL.GDSQLUtils.globalize_path(path)
	
	if _conf_map.has(path):
		return _conf_map.get(path)
		
	var conf := GDSQL.ImprovedConfigFile.new()
	var exist = FileAccess.file_exists(path)
	if not exist and _valid_if_not_exist_path.has(path):
		_passwords[path] = password # FIXME unsafe
		_conf_map[path] = conf
		return conf
		
	if not exist:
		assert(false, "file:[%s] not exist" % path)
		return null
		
	var err = OK
	if password.is_empty():
		err = conf.load(path)
	else:
		err = conf.load_encrypted_pass(path, password)
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
	
## 创建并获取配置：前提是该配置的文件不存在
func create_conf(path: String, password: String) -> GDSQL.ImprovedConfigFile:
	path = GDSQL.GDSQLUtils.globalize_path(path)
	if not FileAccess.file_exists(path):
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
		
func save_conf_by_origin_password(path: String):
	path = GDSQL.GDSQLUtils.globalize_path(path)
	if not has_conf(path):
		assert(false, "this conf %s is not under control" % path)
		return
	var conf = get_conf(path, "")
	if _passwords[path] == "":
		conf.save(path)
	else:
		conf.save_encrypted_pass(path, _passwords[path])
	if OS.has_feature("editor"):
		_conf_modified_time[path] = FileAccess.get_modified_time(path)
		
## NOTICE unsafe
func save_conf_by_same_password(path: String, ref_path: String):
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
	if _passwords[ref_path] == "":
		conf.save(path)
	else:
		conf.save_encrypted_pass(path, _passwords[ref_path])
	if OS.has_feature("editor"):
		_conf_modified_time[path] = FileAccess.get_modified_time(path)
		
func save_conf_by_password(path: String, password: String):
	path = GDSQL.GDSQLUtils.globalize_path(path)
	if not has_conf(path):
		assert(false, "this conf %s is not under control" % path)
		return
	var conf = get_conf(path, "")
	_passwords[path] = password
	if _passwords[path] == "":
		conf.save(path)
	else:
		conf.save_encrypted_pass(path, _passwords[path])
	if OS.has_feature("editor"):
		_conf_modified_time[path] = FileAccess.get_modified_time(path)
		
func set_conf_indexed_props(path: String, indexed_names: Array):
	path = GDSQL.GDSQLUtils.globalize_path(path)
	if not has_conf(path):
		assert(false, "this conf %s is not under control" % path)
		return
	var conf = get_conf(path, "")
	conf.set_indexed_props(indexed_names)
