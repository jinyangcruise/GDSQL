extends Node
class_name ConfManagerClass
# 项目设置里自动加载了该类，名称为ConfManager

var _conf_map: Dictionary = {}
var _passwords: Dictionary = {}

## 获取配置：前提是该配置的文件是存在的
func get_conf(path: String, password: String) -> ImprovedConfigFile:
	if _conf_map.has(path):
		return _conf_map.get(path)
		
	var conf := ImprovedConfigFile.new()
	
	assert(FileAccess.file_exists(path), "file:[%s] not exist" % path)
	var err = conf.load(path) if password.is_empty() else conf.load_encrypted_pass(path, password)
	assert(err == OK, "conf load failed! " + path + ":" + password)
	var fa = FileAccess.open(path, FileAccess.READ)
	if password.is_empty() and fa.get_length() > 0:
		assert(not conf.get_sections().is_empty(), "conf load failed! file [%s] is encrypted! " % path)
	
	_passwords[path] = password
	_conf_map[path] = conf
	return conf
	
## 创建并获取配置：前提是该配置的文件不存在
func create_conf(path: String, password: String) -> ImprovedConfigFile:
	assert(not FileAccess.file_exists(path), "file:[%s] already exist" % path)
	var conf := ImprovedConfigFile.new()
	_passwords[path] = password
	_conf_map[path] = conf
	return conf

func has_conf(path: String) -> bool:
	return _conf_map.has(path)
	
func remove_conf(path: String):
	_conf_map.erase(path)
	
func save_conf_by_origin_password(path: String):
	assert(has_conf(path), "this conf %s is not under control" % path)
	var conf = get_conf(path, "")
	if _passwords[path] == "":
		conf.save(path)
	else:
		conf.save_encrypted_pass(path, _passwords[path])
		
func save_conf_by_same_password(path: String, ref_path: String):
	assert(has_conf(path), "this conf %s is not under control" % path)
	assert(has_conf(ref_path), "this conf %s is not under control" % ref_path)
	var conf = get_conf(path, "")
	_passwords[path] = _passwords[ref_path]
	if _passwords[ref_path] == "":
		conf.save(path)
	else:
		conf.save_encrypted_pass(path, _passwords[ref_path])
