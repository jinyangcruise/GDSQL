@tool
extends RefCounted
class_name GDSQL

const CryptoUtil = preload("res://addons/gdsql/crypto/crypto.gd")
const SQLParser = preload("res://addons/gdsql/database/sql_parser.gd")
const QueryResult = preload("res://addons/gdsql/database/query_result.gd")
const LeftJoin = preload("res://addons/gdsql/database/left_join.gd")
const ImprovedConfigFile = preload("res://addons/gdsql/database/improved_config_file.gd")
const SQLExpression = preload("res://addons/gdsql/database/expression.gd")
const ConfManagerClass = preload("res://addons/gdsql/database/conf_manager.gd")
static var ConfManager: ConfManagerClass: get = _get_conf_manager
const ConditionWrapper = preload("res://addons/gdsql/database/condition_wrapper.gd")
enum ORDER_BY { ASC, DESC }
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
const WorkbenchManagerClass = preload("res://addons/gdsql/singletons/gdsql_workbench_manager.gd")
static var WorkbenchManager: WorkbenchManagerClass: get = _get_workbench_manager
const LeastSquares = preload("res://addons/gdsql/table/least_squares.gd")
const DiffLabelTexture = preload("res://addons/gdsql/tabs/diff_label_texture.gd")
const DiffHelper = preload("res://addons/gdsql/tabs/diff_helper.gd")
const GDSQLUtils = preload("res://addons/gdsql/gdsql_utils.gd")
const DictionaryObject = preload("res://addons/gdsql/dictionary_object.gd")
const GBatisEntityDBClass = preload("res://addons/gdsql/gbatis/entity_db.gd")
static var GBatisEntityDB: GBatisEntityDBClass: get = _get_gbatis_entitydb
const RootConfigClass = preload("res://addons/gdsql/database/root_config.gd")
static var RootConfig: RootConfigClass: get = _get_root_config

static func get_setting_root_config_path() -> String:
	return _get_settings("root_config_path", "res://addons/gdsql/config/config.cfg")
	
static func get_setting_game_conf_db_dir() -> String:
	return _get_settings("game_conf_db_dir", "res://src/config/")
	
static func get_setting_gdsql_config_dir() -> String:
	return _get_settings("gdsql_config_dir", "res://addons/gdsql/config/")
	
static func _get_settings(key: String, default_value: Variant = null):
	return ProjectSettings.get_setting("gdsql/" + key, default_value)
	
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
	if not Engine.has_singleton(&"RootConfig"):
		var db = RootConfigClass.new(get_setting_root_config_path())
		db.name = &"RootConfig"
		Engine.register_singleton(&"RootConfig", db)
		Engine.get_main_loop().root.add_child.call_deferred(db, true)
	return Engine.get_singleton(&"RootConfig")
	
static func _clear():
	for singleton_name in [&"GDSQLConfManager", &"GDSQLWorkbenchManager", &"GBatisEntityDB"]:
		if Engine.has_singleton(singleton_name):
			var mgr = Engine.get_singleton(singleton_name)
			Engine.unregister_singleton(singleton_name)
			mgr.free()
