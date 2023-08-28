extends Node
class_name ConfManagerClass
# 项目设置里自动加载了该类，名称为ConfManager

var confMap: Dictionary = {}

func get_conf(path: String, password: String) -> ImprovedConfigFile:
	if confMap.has(path):
		return confMap.get(path)
		
	var conf := ImprovedConfigFile.new()
	
	assert(FileAccess.file_exists(path), "file:[%s] not exist" % path)
	var err = conf.load(path) if password.is_empty() else conf.load_encrypted_pass(path, password)
	assert(err == OK, "conf load failed! " + path + ":" + password)
		
	confMap[path] = conf
	return conf
