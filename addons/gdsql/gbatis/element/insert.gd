@tool
extends RefCounted
class_name GBatisInsert
#<!ELEMENT insert (#PCDATA | selectKey | include | trim | where | set | foreach 
#| choose | if | bind)*>
#<!ATTLIST insert
#id CDATA #REQUIRED
#parameterMap CDATA #IMPLIED ------------------------ ❌ not support
#parameterType CDATA #IMPLIED ----------------------- ❌ not support
#timeout CDATA #IMPLIED ----------------------------- ❌ not support
#flushCache (true|false) #IMPLIED
#statementType (STATEMENT|PREPARED|CALLABLE) #IMPLIED ❌ not support
#useGeneratedKeys (true|false) #IMPLIED
#keyProperty CDATA #IMPLIED ------------------------- 由数据库内部生成的主键对应的对象
#                                                     的属性或字典的键，多个用逗号分割，
#                                                     配合useGeneratedKeys使用，如
#                                                     果useGeneratedKeys为true，但
#                                                     是未配置该特性，则默认属性和列名
#                                                     完全相同时，才进行设置。
#keyColumn CDATA #IMPLIED --------------------------- keyProperty对应的列名。如果
#                                                     property和column名称一样，可
#                                                     以省略该特性；否则请按照和
#                                                     keyProperty相同的顺序填写相应
#                                                     的列名。
#databaseId CDATA #IMPLIED
#lang CDATA #IMPLIED -------------------------------- ❌ not support
#> 
var id = ""
var flush_cache = "true"
var use_generated_keys = "false"
var key_property = ""
var key_column = ""
var database_id = ""
var sql = ""
var method_return_info: Dictionary: set = set_method_return_info
var param_obj_or_dict: set = set_param_obj_or_dict

func _init(conf: Dictionary) -> void:
	id = conf.get("id").strip_edges()
	flush_cache = conf.get("flushCache", "true").strip_edges()
	use_generated_keys = conf.get("useGeneratedKeys", "false").strip_edges()
	key_property = conf.get("keyProperty", "").strip_edges()
	key_column = conf.get("keyColumn", "").strip_edges()
	if key_column == "":
		key_column = key_property
	elif key_property.get_slice_count(",") != key_column.get_slice_count(","):
		assert(false, "Split count not match of keyProperty and keyColumn.")
	database_id = conf.get("databaseId", "").strip_edges()
	
func clean():
	method_return_info.clear()
	param_obj_or_dict = null
	
func set_sql(p_sql: String):
	sql = p_sql
	
func set_method_return_info(info: Dictionary):
	method_return_info = info
	
func set_param_obj_or_dict(param):
	param_obj_or_dict = param
	
# INFO 缓存的逻辑在mapper_parser.gd
func query():
	var dao = SQLParser.parse_to_dao(sql)
	if dao == null:
		assert(false, "Parse to dao failed: " + sql)
		return null
	if not dao.get_cmd().begins_with("insert"):
		assert(false, "BaseDao's cmd is not insert.")
		return null
	if not database_id.is_empty():
		dao.use_db_name(database_id)
	var query_result = dao.query()
	if query_result == null:
		assert(false, "Error occur in base_dao.query().")
		return null
	if not query_result.ok():
		assert(false, "Error occur. %s" % query_result.get_err())
		return false
		
	if use_generated_keys == "true" and param_obj_or_dict:
		var generated_keys = query_result.get_generated_keys()
		var key_properties = [] if key_property == "" else key_property.split(",") as PackedStringArray
		var key_columns = [] if key_column == "" else key_column.split(",") as PackedStringArray
		
		for p in key_properties:
			if param_obj_or_dict is Object:
				if not p in param_obj_or_dict:
					assert(false, "Invalid property %s in Object." % p)
					return null
			else:
				if not param_obj_or_dict.has(p):
					assert(false, "Invalid key %s in Dictionary." % p)
					return null
					
		for k in generated_keys:
			var v = generated_keys[k]
			if key_properties.is_empty():
				if param_obj_or_dict is Object:
					if k in param_obj_or_dict:
						param_obj_or_dict.set(k, v)
				else:
					if param_obj_or_dict.has(k):
						param_obj_or_dict[k] = v
			else:
				var index = key_columns.find(k)
				if index > -1:
					var prop_or_key = key_properties[index].strip_edges()
					if param_obj_or_dict is Object:
						param_obj_or_dict.set(prop_or_key, v)
					else:
						param_obj_or_dict[prop_or_key] = v
						
	if method_return_info.type == TYPE_NIL:
		return
		
	if method_return_info.type == TYPE_INT:
		return query_result.get_affected_rows()
		
	if method_return_info.class_name == "QueryResult":
		return query_result
		
	assert(false, "Method of <insert> cannot return %s." % \
		DataTypeDef.DATA_TYPE_NAMES[method_return_info.type])
	return null
