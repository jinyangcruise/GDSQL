@tool
extends RefCounted
class_name GDSQL

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
const PasswordDef = preload("res://addons/gdsql/def/password_def.gd")
const DataTypeDef = preload("res://addons/gdsql/def/data_type_def.gd")
const GBatisUpdate = preload("res://addons/gdsql/gbatis/element/update.gd")
const GBatisSelect = preload("res://addons/gdsql/gbatis/element/select.gd")
const GBatisInsert = preload("res://addons/gdsql/gbatis/element/insert.gd")
const GBatisReplace = preload("res://addons/gdsql/gbatis/element/replace.gd")
const GBatisDelete = preload("res://addons/gdsql/gbatis/element/delete.gd")
const GBatisResultMap = preload("res://addons/gdsql/gbatis/element/result_map.gd")
const GBatisResult = preload("res://addons/gdsql/gbatis/element/result.gd")
const GBatisId = preload("res://addons/gdsql/gbatis/element/id.gd")
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

static func _get_conf_manager() -> ConfManagerClass:
	if not Engine.has_singleton(&"GDSQLConfManager"):
		Engine.register_singleton(&"GDSQLConfManager", ConfManagerClass.new())
	return Engine.get_singleton(&"GDSQLConfManager")
	
static func _get_workbench_manager() -> WorkbenchManagerClass:
	if not Engine.has_singleton(&"GDSQLWorkbenchManager"):
		Engine.register_singleton(&"GDSQLWorkbenchManager", WorkbenchManagerClass.new())
	return Engine.get_singleton(&"GDSQLWorkbenchManager")
	
static func _clear():
	for singleton_name in [&"GDSQLConfManager", &"GDSQLWorkbenchManager"]:
		if Engine.has_singleton(singleton_name):
			var mgr = Engine.get_singleton(singleton_name)
			Engine.unregister_singleton(singleton_name)
			mgr.free()
