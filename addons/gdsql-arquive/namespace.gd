@tool
class_name GDSQL
extends RefCounted

enum ORDER_BY { ASC, DESC }

const CryptoUtil = preload("res://addons/gdsql/crypto/crypto.gd")
const SQLParser = preload("res://addons/gdsql/database/sql_parser.gd")
const QueryResult = preload("res://addons/gdsql/database/query_result.gd")
const LeftJoin = preload("res://addons/gdsql/database/left_join.gd")
const ImprovedConfigFile = preload("res://addons/gdsql/database/improved_config_file.gd")
const SQLExpression = preload("res://addons/gdsql/database/expression.gd")
const ConfManagerClass = preload("res://addons/gdsql/database/conf_manager.gd")
const ConditionWrapper = preload("res://addons/gdsql/database/condition_wrapper.gd")
const BaseDao = preload("res://addons/gdsql/database/base_dao.gd")
const AggregateFunctions = preload("res://addons/gdsql/database/aggregate_functions.gd")
const DataTypeDef = preload("res://addons/gdsql/def/data_type_def.gd")
const GBatisUpdate = preload("res://addons/gdsql/gbatis/element/update.gd")
const GBatisSelect = preload("res://addons/gdsql/gbatis/element/select.gd")
const GBatisInsert = preload("res://addons/gdsql/gbatis/element/insert.gd")
const GBatisReplace = preload("res://addons/gdsql/gbatis/element/replace.gd")
const GBatisDelete = preload("res://addons/gdsql/gbatis/element/delete.gd")
const GBatisResultMap = preload("res://addons/gdsql/gbatis/element/result_map.gd")
const GBatisResult = preload("res://addons/gdsql/gbatis/element/result.gd")
const GBatisId = preload("res://addons/gdsql/gbatis/element/id.gd")
const GBatisUQ = preload("res://addons/gdsql/gbatis/element/uq.gd")
const GBatisDiscriminator = preload("res://addons/gdsql/gbatis/element/discriminator.gd")
const GBatisCollection = preload("res://addons/gdsql/gbatis/element/collection.gd")
const GBatisCase = preload("res://addons/gdsql/gbatis/element/case.gd")
const GBatisCache = preload("res://addons/gdsql/gbatis/element/cache.gd")
const GBatisAssociation = preload("res://addons/gdsql/gbatis/element/association.gd")
const GBatisMapperValidator = preload("res://addons/gdsql/gbatis/mapper_validator.gd")
const GBatisMapperRule = preload("res://addons/gdsql/gbatis/mapper_rule.gd")
const GBatisMapperParser = preload("res://addons/gdsql/gbatis/mapper_parser.gd")
const GBatisEntity = preload("res://addons/gdsql/gbatis/gbatis_entity.gd")
const GXMLNode = preload("res://addons/gdsql/gxml/gxml_node.gd")
const GXMLItem = preload("res://addons/gdsql/gxml/gxml_item.gd")
const WorkbenchManagerClass = preload("res://addons/gdsql/basic/gdsql_workbench_manager.gd")
const LeastSquares = preload("res://addons/gdsql/table/least_squares.gd")
const DiffLabelTexture = preload("res://addons/gdsql/tabs/mapper_graph/diff_label_texture.gd")
const DiffHelper = preload("res://addons/gdsql/tabs/mapper_graph/diff_helper.gd")
const GDSQLUtils = preload("res://addons/gdsql/basic/gdsql_utils.gd")
const AdminDao = preload("res://addons/gdsql/database/admin_dao.gd")
const DictionaryObject = preload("res://addons/gdsql/basic/dictionary_object.gd")
const GBatisEntityDBClass = preload("res://addons/gdsql/gbatis/entity_db.gd")
const RootConfigClass = preload("res://addons/gdsql/database/root_config.gd")

static var ConfManager: ConfManagerClass:
	get = _get_conf_manager
static var WorkbenchManager: WorkbenchManagerClass:
	get = _get_workbench_manager
static var GBatisEntityDB: GBatisEntityDBClass:
	get = _get_gbatis_entitydb
static var RootConfig: RootConfigClass:
	get = _get_root_config


static func get_setting_root_config_path() -> String:
	return _get_settings("config/root_config_path", "res://gdsql/define/config.cfg")


static func get_setting_game_conf_db_name() -> String:
	return _get_settings("config/game_conf_db_name", "")


## 获取补充配置文件路径（用于导出游戏中保存运行时创建的数据库/表元数据）。
## 默认存储在 user://gdsql/define/ 下，可在 gdsql/settings.cfg 中
## [config] supplementary_config_path 覆盖。
static func get_setting_supplementary_config_path() -> String:
	return _get_settings("config/supplementary_config_path", "user://gdsql/define/runtime_config.cfg")


static func _get_settings(prop: String, default_value: Variant = null):
	var settings = ConfigFile.new()
	settings.load("res://gdsql/settings.cfg")
	var section = prop.get_slice("/", 0)
	var key = prop.get_slice("/", 1)
	return settings.get_value(section, key, default_value)


static func _get_conf_manager() -> ConfManagerClass:
	if not Engine.has_singleton(&"GDSQLConfManager"):
		var conf_mgr = ConfManagerClass.new()
		conf_mgr.name = &"GDSQLConfManager"
		Engine.register_singleton(&"GDSQLConfManager", conf_mgr)
		Engine.get_main_loop().root.add_child.call_deferred(conf_mgr, true)
	return Engine.get_singleton(&"GDSQLConfManager")


static func _get_workbench_manager() -> WorkbenchManagerClass:
	if not Engine.is_editor_hint():
		return null
	if not Engine.has_singleton(&"GDSQLWorkbenchManager"):
		var wb_mgr = WorkbenchManagerClass.new()
		Engine.register_singleton(&"GDSQLWorkbenchManager", wb_mgr)
		Engine.get_main_loop().root.add_child.call_deferred(wb_mgr, true)
	return Engine.get_singleton(&"GDSQLWorkbenchManager")


static func _get_gbatis_entitydb() -> GBatisEntityDBClass:
	if not Engine.has_singleton(&"GBatisEntityDB"):
		var db = GBatisEntityDBClass.new()
		db.name = &"GBatisEntityDB"
		Engine.register_singleton(&"GBatisEntityDB", db)
		Engine.get_main_loop().root.add_child.call_deferred(db, true)
	return Engine.get_singleton(&"GBatisEntityDB")


static func _get_root_config() -> RootConfigClass:
	if not Engine.has_singleton(&"GDSQLRootConfig"):
		var rc = RootConfigClass.new(get_setting_root_config_path())
		rc.name = &"GDSQLRootConfig"
		Engine.register_singleton(&"GDSQLRootConfig", rc)
		Engine.get_main_loop().root.add_child.call_deferred(rc, true)
		# 在导出游戏中（非编辑器）初始化补充配置，用于存储运行时创建的数据库/表
		if not OS.has_feature("editor"):
			rc.init_supplementary(get_setting_supplementary_config_path())
			# 为非 res:// 的数据库创建数据目录，防止首次查表/插入时目录不存在
			rc.init_database_dirs()
	return Engine.get_singleton(&"GDSQLRootConfig")


static func _clear():
	for singleton_name in [&"GDSQLConfManager", &"GDSQLWorkbenchManager", &"GBatisEntityDB", &"GDSQLRootConfig"]:
		if Engine.has_singleton(singleton_name):
			var mgr = Engine.get_singleton(singleton_name)
			Engine.unregister_singleton(singleton_name)
			mgr.get_parent().remove_child(mgr)
			mgr.queue_free()
