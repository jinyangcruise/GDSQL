extends Node
class_name ConfManagerClass
# 项目设置里自动加载了该类，名称为ConfManager

var confMap: Dictionary = {}

func get_conf(path: String, password: String) -> ImprovedConfigFile:
	printt("ppppppppppppp get_conf", path, password)
	if confMap.has(path):
		printt("map has this")
		return confMap.get(path)
		
	var conf := ImprovedConfigFile.new()
	
	assert(FileAccess.file_exists(path), "file:[%s] not exist" % path)
	var err = conf.load(path) if password.is_empty() else conf.load_encrypted_pass(path, password)
	assert(err == OK, "conf load failed! " + path + ":" + password)
	var fa = FileAccess.open(path, FileAccess.READ)
	if password.is_empty() and fa.get_length() > 0:
		assert(not conf.get_sections().is_empty(), "conf load failed! file [%s] is encrypted! " % path)
	
	confMap[path] = conf
	return conf
