extends Node

var path: String
var conf: ConfigFile

func _init(p_path: String = "res://addons/gdsql/config/config.cfg") -> void:
	set_path(p_path)
	
func set_path(p_path: String):
	if p_path == path:
		return
	path = p_path
	conf = GDSQL.ConfManager.get_conf(path, "")
	
# 清空所有配置
func clear() -> void:
	conf.clear()
	
# 编码为配置文本字符串
func encode_to_text() -> String:
	return conf.encode_to_text()
	
# 删除整个分组
func erase_section(section: String) -> void:
	conf.erase_section(section)
	
# 删除分组下的键
func erase_section_key(section: String, key: String) -> void:
	conf.erase_key(section, key)
	
# 获取分组下所有键
func get_section_keys(section: String) -> PackedStringArray:
	return conf.get_section_keys(section)
	
# 获取所有分组名
func get_sections() -> PackedStringArray:
	return conf.get_sections()
	
# 获取配置值（带默认值）
func get_value(section: String, key: String, default: Variant = null) -> Variant:
	return conf.get_value(section, key, default)
	
# 判断是否存在分组
func has_section(section: String) -> bool:
	return conf.has_section(section)
	
# 判断是否存在分组+键
func has_section_key(section: String, key: String) -> bool:
	return conf.has_section_key(section, key)
	
# 解析文本格式配置
func parse(data: String) -> Error:
	return conf.parse(data)
	
# 保存配置到文件（使用成员变量 path）
func save() -> Error:
	return conf.save(path)
	
# 保存加密配置（使用成员变量 path）
func save_encrypted(key: PackedByteArray) -> Error:
	return conf.save_encrypted(path, key)
	
# 保存加密配置（密码，使用成员变量 path）
func save_encrypted_pass(password: String) -> Error:
	return conf.save_encrypted_pass(path, password)
	
# 设置配置值
func set_value(section: String, key: String, value: Variant) -> void:
	conf.set_value(section, key, value)
	
func get_database_data(db_name: String) -> Dictionary:
	var ret = {}
	for key in conf.get_section_keys(db_name):
		ret[key] = conf.get_value(db_name, key)
	return ret
	
func get_database_encrypted_dek(db_name: String) -> String:
	return conf.get_value(db_name, "encrypted", "")
	
func get_database_dek(db_name: String) -> PackedByteArray:
	var dek = conf.get_value("_DEK_", db_name, "")
	if dek != "":
		return Marshalls.base64_to_raw(dek)
	return PackedByteArray()
