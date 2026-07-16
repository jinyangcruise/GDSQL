extends Node

const CONFIG_EXTENSION = ".cfg"
const DATA_EXTENSION = ".gsql"
const DEK = "_DEK_"

var path: String
var conf: ConfigFile
## 补充配置：仅在导出游戏（非编辑器）中有效，用于保存运行时创建的数据库/表元数据。
## 位于 user:// 下，可读写。主配置 conf（res://）在导出后只读。
var supplementary_path: String = ""
var supplementary_conf: ConfigFile = null


func _init(p_path: String = "res://gdsql/define/config.cfg") -> void:
	set_path(p_path)


func set_path(p_path: String):
	if p_path == path:
		return
	path = p_path
	conf = GDSQL.ConfManager.get_conf(path, "")


## 初始化补充配置（仅在导出游戏中需要调用）。
## supp_path：补充配置文件路径，应在可写目录（如 user://）下。
func init_supplementary(supp_path: String) -> void:
	supplementary_path = supp_path
	supplementary_conf = ConfigFile.new()
	if GDSQL.GDSQLUtils.file_exists(supp_path):
		supplementary_conf.load(supp_path)


func get_base_dir() -> String:
	return path.get_base_dir()


## 在导出游戏中，为非项目内（非 res://）的数据库创建数据目录。
## 防止在查表或插入数据时才发现目录不存在。
func init_database_dirs() -> void:
	if OS.has_feature("editor"):
		return

	for db_name in get_databases():
		var data_path = get_database_data_path(db_name)
		if data_path == "":
			continue
		if data_path.begins_with("res://"):
			continue
		var abs_path = GDSQL.GDSQLUtils.globalize_path(data_path)
		if not DirAccess.dir_exists_absolute(abs_path):
			DirAccess.make_dir_recursive_absolute(abs_path)


## 获取补充配置的基础目录（即 supplementary_path 所在目录）
func get_supplementary_base_dir() -> String:
	return supplementary_path.get_base_dir() if supplementary_path else ""


func reload():
	GDSQL.ConfManager.remove_conf(path)
	conf = GDSQL.ConfManager.get_conf(path, "")
	if supplementary_conf != null and GDSQL.GDSQLUtils.file_exists(supplementary_path):
		supplementary_conf.load(supplementary_path)


# 清空所有配置
func clear() -> void:
	conf.clear()
	if supplementary_conf:
		supplementary_conf.clear()


# 编码为配置文本字符串（仅主配置）
func encode_to_text() -> String:
	return conf.encode_to_text()


# 删除整个分组
func erase_section(section: String) -> void:
	if supplementary_conf and supplementary_conf.has_section(section):
		supplementary_conf.erase_section(section)
	else:
		conf.erase_section(section)


# 删除分组下的键
func erase_section_key(section: String, key: String) -> void:
	if supplementary_conf and supplementary_conf.has_section_key(section, key):
		supplementary_conf.erase_key(section, key)
	else:
		conf.erase_key(section, key)


# 获取分组下所有键（优先补充配置）
func get_section_keys(section: String) -> PackedStringArray:
	if supplementary_conf and supplementary_conf.has_section(section):
		return supplementary_conf.get_section_keys(section)
	return conf.get_section_keys(section)


# 获取所有分组名（合并主配置与补充配置）
func get_sections() -> PackedStringArray:
	var sections = conf.get_sections()
	if supplementary_conf:
		for section in supplementary_conf.get_sections():
			if not sections.has(section):
				sections.append(section)
	return sections


# 获取配置值（补充配置优先，回退到主配置）
func get_value(section: String, key: String, default: Variant = null) -> Variant:
	if supplementary_conf and supplementary_conf.has_section_key(section, key):
		return supplementary_conf.get_value(section, key, default)
	return conf.get_value(section, key, default)


# 判断是否存在分组（任一配置中存在即为 true）
func has_section(section: String) -> bool:
	if supplementary_conf and supplementary_conf.has_section(section):
		return true
	return conf.has_section(section)


# 判断是否存在分组+键（任一配置中存在即为 true）
func has_section_key(section: String, key: String) -> bool:
	if supplementary_conf and supplementary_conf.has_section_key(section, key):
		return true
	return conf.has_section_key(section, key)


# 解析文本格式配置
func parse(data: String) -> Error:
	return conf.parse(data)


# 保存配置。
# 在导出游戏中：保存补充配置到 supplementary_path（user:// 下可写）。
# 在编辑器中：保存主配置到 path（res:// 下）。
func save() -> Error:
	if _use_supplementary():
		# 确保目录存在
		var dir_path = supplementary_path.get_base_dir()
		if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir_path)):
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))
		return supplementary_conf.save(supplementary_path)
	GDSQL.ConfManager.save_conf_by_origin_password_or_dek(path)
	return OK


# 保存加密配置（使用成员变量 path）
func save_encrypted(key: PackedByteArray) -> Error:
	GDSQL.ConfManager.save_conf_by_password(path, key)
	return OK


# 保存加密配置（密码，使用成员变量 path）
func save_encrypted_pass(password: String) -> Error:
	GDSQL.ConfManager.save_conf_by_password(path, password)
	return OK


# 设置配置值（在导出游戏中写入补充配置，编辑器中写入主配置）
func set_value(section: String, key: String, value: Variant) -> void:
	if _use_supplementary():
		supplementary_conf.set_value(section, key, value)
	else:
		conf.set_value(section, key, value)


func validate_name(p_name: String) -> String:
	var ret = p_name.to_lower()
	if ret.ends_with(DATA_EXTENSION):
		return ret.get_basename()
	return ret


func set_database_display_name(db_name: String, display_name: String):
	db_name = validate_name(db_name)
	set_value(db_name, "display_name", display_name)


func get_database_display_name(db_name: String) -> String:
	db_name = validate_name(db_name)
	var dn = get_value(db_name, "display_name", "")
	return dn if dn != "" else db_name


func get_databases() -> Array[String]:
	var ret: Array[String]
	for section in conf.get_sections():
		if section != DEK:
			ret.push_back(section)
	if supplementary_conf:
		for section in supplementary_conf.get_sections():
			if section != DEK and not ret.has(section):
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
	var databases = { }
	for db_name in GDSQL.RootConfig.get_sections():
		if db_name == GDSQL.RootConfig.DEK:
			continue

		databases[db_name] = {
			"data_path": get_value(db_name, "data_path"),
			"encrypted": get_value(db_name, "encrypted", ""),
			"display_name": get_database_display_name(db_name),
			"tables": { },
		}

		var db_conf_path = get_database_config_path(db_name)
		var table_confs = GDSQL.GDSQLUtils.get_specific_extension_files(db_conf_path, CONFIG_EXTENSION.substr(1))
		for file_name in table_confs:
			var table_conf = GDSQL.ImprovedConfigFile.new()
			table_conf.load2(db_conf_path.path_join(file_name))
			var table_name = file_name.get_basename()

			var table_info = { }
			for key in table_conf.get_section_keys(table_name):
				table_info[key] = table_conf.get_value(table_name, key)
			databases[db_name]["tables"][table_name] = table_info

	return databases


func set_database_data(db_name: String, data_path: String, encypted_dek: String, display_name: String = ""):
	db_name = validate_name(db_name)
	set_value(db_name, "data_path", data_path)
	set_value(db_name, "encrypted", encypted_dek)
	if display_name != "":
		set_value(db_name, "display_name", display_name)


func set_database_data_path(db_name: String, data_path: String):
	db_name = validate_name(db_name)
	set_value(db_name, "data_path", data_path)


func set_database_encrypted(db_name: String, encypted_dek: String):
	db_name = validate_name(db_name)
	set_value(db_name, "encrypted", encypted_dek)


func erase_database(db_name: String):
	db_name = validate_name(db_name)
	erase_section(db_name)


func set_database_dek(db_name: String, dek = null):
	db_name = validate_name(db_name)
	set_value(DEK, get_database_data_path(db_name), dek)


func get_database_dek64(db_name: String) -> String:
	db_name = validate_name(db_name)
	return get_value(DEK, get_database_data_path(db_name), "")


func get_table_dek64(db_name: String, table_name: String) -> String:
	db_name = validate_name(db_name)
	table_name = validate_name(table_name)
	return get_value(DEK, get_table_data_path(db_name, table_name), "")


func set_table_dek(db_name: String, table_name: String, dek = null):
	db_name = validate_name(db_name)
	table_name = validate_name(table_name)
	set_value(DEK, get_table_data_path(db_name, table_name), dek)


func get_database_data(db_name: String) -> Dictionary:
	db_name = validate_name(db_name)
	var ret = { }
	for key in get_section_keys(db_name):
		ret[key] = get_value(db_name, key)
	return ret


## 获取数据库配置目录路径。
## 对于运行时创建的数据库（归属补充配置），返回 user:// 下的路径；
## 对于预定义数据库（归属主配置），返回主配置所在目录下的路径。
func get_database_config_path(db_name: String) -> String:
	db_name = validate_name(db_name)
	if _is_db_in_supplementary(db_name):
		return supplementary_path.get_base_dir().path_join(db_name)
	return get_base_dir().path_join(db_name)


func get_database_data_path(db_name: String) -> String:
	db_name = validate_name(db_name)
	return get_value(db_name, "data_path", "")


func get_database_name_by_db_path(p_path: String) -> String:
	for db_name in get_sections():
		if has_section_key(db_name, "data_path"):
			if get_value(db_name, "data_path") == p_path or \
					GDSQL.GDSQLUtils.globalize_path(get_value(db_name, "data_path")) == GDSQL.GDSQLUtils.globalize_path(p_path):
				return db_name
	return ""


func get_table_config_path(db_name: String, table_name: String) -> String:
	db_name = validate_name(db_name)
	table_name = validate_name(table_name)
	return get_database_config_path(db_name).path_join(table_name) + CONFIG_EXTENSION


func get_table_data_path(db_name: String, table_name: String) -> String:
	db_name = validate_name(db_name)
	table_name = validate_name(table_name)
	return get_value(db_name, "data_path").path_join(table_name) + DATA_EXTENSION


func get_database_encrypted_dek(db_name: String) -> String:
	db_name = validate_name(db_name)
	return get_value(db_name, "encrypted", "")


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


func get_table_display_name(db_name: String, table_name: String) -> String:
	table_name = validate_name(table_name)
	get_table_config_path(db_name, table_name)
	var table_config = GDSQL.ConfManager.get_conf(get_table_config_path(db_name, table_name), "")
	var dn = table_config.get_value(table_name, "display_name", "")
	return dn if dn != "" else table_name


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


func get_table_encrypted_dek(db_name: String, table_name: String) -> String:
	table_name = validate_name(table_name)
	get_table_config_path(db_name, table_name)
	var table_config = GDSQL.ConfManager.get_conf(get_table_config_path(db_name, table_name), "")
	return table_config.get_value(table_name, "encrypted", "")


func get_table_columns_by_db_path(db_path: String, table_name: String) -> Array:
	var db_name = get_database_name_by_db_path(db_path)
	var columns = get_table_columns(db_name, table_name)

	return columns.duplicate(true).map(
		func(v):
			v["db_name"] = db_name
			return v
	)


func get_table_valid_if_not_exist(db_name: String, table_name: String) -> bool:
	db_name = validate_name(db_name)
	table_name = validate_name(table_name)
	var table_config = GDSQL.ConfManager.get_conf(get_table_config_path(db_name, table_name), "")
	return table_config.get_value(table_name, "valid_if_not_exist", false)


func check_table_exit(p_db_name_or_path: String, p_table_name: String):
	var p_db_name_or_path_bak = p_db_name_or_path
	var p_table_name_bak = p_table_name
	if p_db_name_or_path.contains("/") or p_db_name_or_path.contains("\\"):
		p_db_name_or_path = validate_name(p_db_name_or_path)
	p_table_name = validate_name(p_table_name)
	var possible = []
	var find_db = ""
	var info = get_databases_info()
	const SIMILARITY = 0.6
	for db_name in info:
		if p_db_name_or_path == db_name or GDSQL.GDSQLUtils.globalize_path(p_db_name_or_path) == \
				GDSQL.GDSQLUtils.globalize_path(info[db_name].data_path):
			find_db = db_name if db_name == p_db_name_or_path_bak else info[db_name].get("display_name", db_name)
			possible.clear()
			for table_name in info[db_name].tables:
				if p_table_name == table_name:
					return [
						true,
						find_db,
						table_name if table_name == p_table_name_bak else info[db_name].tables[table_name].get("display_name", table_name),
					]
				elif p_table_name.similarity(table_name) >= SIMILARITY:
					possible.push_back(info[db_name].tables[table_name].get("display_name", table_name))
			break
		elif p_db_name_or_path.similarity(db_name) >= SIMILARITY:
			possible.push_back(info[db_name].get("display_name", db_name))
		elif GDSQL.GDSQLUtils.globalize_path(p_db_name_or_path).similarity(
			GDSQL.GDSQLUtils.globalize_path(info[db_name].data_path),
		) >= SIMILARITY:
			possible.push_back(info[db_name].data_path)

	if not find_db:
		if possible.is_empty():
			return [false, false, false]
		else:
			return [false, possible, false]
	else:
		if possible.is_empty():
			return [false, find_db, false]
		else:
			return [false, find_db, possible]


## 是否使用补充配置（即当前处于导出游戏中）
func _use_supplementary() -> bool:
	return supplementary_conf != null


## 判断某数据库名是否归属于补充配置
func _is_db_in_supplementary(db_name: String) -> bool:
	return supplementary_conf != null and supplementary_conf.has_section(db_name)
