extends Node

const CONFIG_EXTENSION = ".cfg"
const DATA_EXTENSION = ".gsql"
const DEK = "_DEK_"

var path: String
var conf: ConfigFile

func _init(p_path: String = "res://addons/gdsql/config/config.cfg") -> void:
	set_path(p_path)
	
func set_path(p_path: String):
	if p_path == path:
		return
	path = p_path
	conf = GDSQL.ConfManager.get_conf(path, "")
	
func get_base_dir() -> String:
	return path.get_base_dir()
	
func reload():
	GDSQL.ConfManager.remove_conf(path)
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
	
func validate_name(p_name: String) -> String:
	var ret = p_name.to_lower()
	if ret.ends_with(DATA_EXTENSION):
		return ret.get_basename()
	return ret
	
func get_databases() -> Array[String]:
	var ret: Array[String]
	for section in conf.get_sections():
		if section != DEK:
			ret.push_back(section)
	return ret
	
func get_tables(db_name: String) -> Array[String]:
	var ret: Array[String]
	var db_conf_path = get_database_config_path(db_name)
	var table_confs = GDSQL.GDSQLUtils.get_specific_extension_files(db_conf_path, CONFIG_EXTENSION.substr(1))
	for file_name in table_confs:
		ret.push_back(file_name.get_basename())
	return ret
	
func get_databases_info() -> Dictionary:
	var databases = {}
	for db_name in GDSQL.RootConfig.get_sections():
		if db_name == GDSQL.RootConfig.DEK:
			continue
			
		databases[db_name] = {
			"data_path": get_value(db_name, "data_path"),
			"encrypted": get_value(db_name, "encrypted", ""),
			"tables": {}
		}
		
		var db_conf_path = get_database_config_path(db_name)
		var table_confs = GDSQL.GDSQLUtils.get_specific_extension_files(db_conf_path, CONFIG_EXTENSION.substr(1))
		for file_name in table_confs:
			var table_conf = ConfigFile.new()
			table_conf.load(db_conf_path.path_join(file_name))
			var table_name = file_name.get_basename()
			
			var table_info = {}
			for key in table_conf.get_section_keys(table_name):
				table_info[key] = table_conf.get_value(table_name, key)
			databases[db_name]["tables"][table_name] = table_info
			
	return databases
	
func set_database_data(db_name: String, data_path: String, encypted_dek: String):
	db_name = validate_name(db_name)
	conf.set_value(db_name, "data_path", data_path)
	conf.set_value(db_name, "encrypted", encypted_dek)
	
func set_database_data_path(db_name: String, data_path: String):
	db_name = validate_name(db_name)
	conf.set_value(db_name, "data_path", data_path)
	
func set_database_encrypted(db_name: String, encypted_dek: String):
	db_name = validate_name(db_name)
	conf.set_value(db_name, "encrypted", encypted_dek)
	
func erase_database(db_name: String):
	db_name = validate_name(db_name)
	erase_section(db_name)
	
func set_database_dek(db_name: String, dek = null):
	db_name = validate_name(db_name)
	conf.set_value(DEK, get_database_data_path(db_name), dek)
	
func get_database_dek64(db_name: String) -> String:
	db_name = validate_name(db_name)
	return conf.get_value(DEK, get_database_data_path(db_name), "")
	
func get_table_dek64(db_name: String, table_name: String) -> String:
	db_name = validate_name(db_name)
	table_name = validate_name(table_name)
	return conf.get_value(DEK, get_table_data_path(db_name, table_name), "")
	
func set_table_dek(db_name: String, table_name: String, dek = null):
	db_name = validate_name(db_name)
	table_name = validate_name(table_name)
	conf.set_value(DEK, get_table_data_path(db_name, table_name), dek)
	
func get_database_data(db_name: String) -> Dictionary:
	db_name = validate_name(db_name)
	var ret = {}
	for key in conf.get_section_keys(db_name):
		ret[key] = conf.get_value(db_name, key)
	return ret
	
func get_database_config_path(db_name: String) -> String:
	db_name = validate_name(db_name)
	return get_base_dir().path_join(db_name)
	
func get_database_data_path(db_name: String) -> String:
	db_name = validate_name(db_name)
	return conf.get_value(db_name, "data_path", "")
	
func get_database_name_by_db_path(p_path: String) -> String:
	for db_name in conf.get_sections():
		if conf.has_section_key(db_name, "data_path"):
			if conf.get_value(db_name, "data_path") == p_path or \
			GDSQL.GDSQLUtils.globalize_path(conf.get_value(db_name, "data_path")) == GDSQL.GDSQLUtils.globalize_path(p_path):
				return db_name
	return ""
	
func get_table_config_path(db_name: String, table_name: String) -> String:
	db_name = validate_name(db_name)
	table_name = validate_name(table_name)
	return get_database_config_path(db_name).path_join(table_name) + CONFIG_EXTENSION
	
func get_table_data_path(db_name: String, table_name: String) -> String:
	db_name = validate_name(db_name)
	table_name = validate_name(table_name)
	return conf.get_value(db_name, "data_path").path_join(table_name) + DATA_EXTENSION
	
func get_database_encrypted_dek(db_name: String) -> String:
	db_name = validate_name(db_name)
	return conf.get_value(db_name, "encrypted", "")
	
func get_database_dek(db_name: String) -> PackedByteArray:
	var dek64 = get_database_dek64(db_name)
	if dek64 != "":
		return Marshalls.base64_to_raw(dek64)
	return PackedByteArray()
	
func get_table_dek(db_name: String, table_name: String) -> PackedByteArray:
	var dek64 = get_table_dek64(db_name, table_name)
	if dek64 != "":
		return Marshalls.base64_to_raw(dek64)
	return PackedByteArray()
	
func get_table_config(db_name: String, table_name: String) -> ConfigFile:
	table_name = validate_name(table_name)
	get_table_config_path(db_name, table_name)
	return GDSQL.ConfManager.get_conf(get_table_config_path(db_name, table_name), "")
	
func get_table_config_by_db_path(db_path: String, table_name: String) -> ConfigFile:
	var db_name = get_database_name_by_db_path(db_path)
	table_name = validate_name(table_name)
	get_table_config_path(db_name, table_name)
	return GDSQL.ConfManager.get_conf(get_table_config_path(db_name, table_name), "")
	
func get_table_columns(db_name: String, table_name: String) -> Array:
	table_name = validate_name(table_name)
	get_table_config_path(db_name, table_name)
	var table_config = GDSQL.ConfManager.get_conf(get_table_config_path(db_name, table_name), "")
	return table_config.get_value(table_name, "columns", [])
	
func get_table_comment(db_name: String, table_name: String) -> String:
	table_name = validate_name(table_name)
	get_table_config_path(db_name, table_name)
	var table_config = GDSQL.ConfManager.get_conf(get_table_config_path(db_name, table_name), "")
	return table_config.get_value(table_name, "comment", "")
	
func get_table_columns_by_db_path(db_path: String, table_name: String) -> Array:
	var db_name = get_database_name_by_db_path(db_path)
	var columns = get_table_columns(db_name, table_name)
	return columns.duplicate(true).map(func(v): v["db_name"] = db_name; return v)
	
func get_table_valid_if_not_exist(db_name: String, table_name: String) -> bool:
	db_name = validate_name(db_name)
	table_name = validate_name(table_name)
	var table_config = GDSQL.ConfManager.get_conf(get_table_config_path(db_name, table_name), "")
	return table_config.get_value(table_name, "valid_if_not_exist", false)
	
