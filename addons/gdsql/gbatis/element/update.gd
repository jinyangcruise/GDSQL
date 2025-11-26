@tool
extends RefCounted

#<!ELEMENT update 
#(#PCDATA | selectKey | include | trim | where | set | foreach | choose | if | bind)*>
#<!ATTLIST update
#id CDATA #REQUIRED
#parameterMap CDATA #IMPLIED ------------------------ ❌ not support
#parameterType CDATA #IMPLIED ----------------------- ❌ not support
#timeout CDATA #IMPLIED ----------------------------- ❌ not support
#flushCache (true|false) #IMPLIED
#statementType (STATEMENT|PREPARED|CALLABLE) #IMPLIED ❌ not support
#keyProperty CDATA #IMPLIED ------------------------- ❌ not support
#useGeneratedKeys (true|false) #IMPLIED ------------- ❌ not support
#keyColumn CDATA #IMPLIED --------------------------- ❌ not support
#databaseId CDATA #IMPLIED
#lang CDATA #IMPLIED -------------------------------- ❌ not support
#>
var id = ""
var flush_cache = "true"
var database_id = ""
var sql = ""
var method_return_info: Dictionary: set = set_method_return_info

func _init(conf: Dictionary) -> void:
	id = conf.get("id").strip_edges()
	flush_cache = conf.get("flushCache", "true").strip_edges()
	database_id = conf.get("databaseId", "").strip_edges()
	
func clean():
	method_return_info.clear()
	
func set_sql(p_sql: String):
	sql = p_sql
	
func set_method_return_info(info: Dictionary):
	method_return_info = info
	
# INFO 缓存的逻辑在mapper_parser.gd
func query():
	var dao = GDSQL.SQLParser.parse_to_dao(sql)
	if dao == null:
		assert(false, "Parse to dao failed: " + sql)
		return null
	if dao.get_cmd() != "update":
		assert(false, "BaseDao's cmd is not update.")
		return null
	if not database_id.is_empty():
		dao.use_db_name(database_id)
	var query_result = dao.query()
	if query_result == null:
		assert(false, "Error occur in base_dao.query().")
		return null
	if not query_result.ok():
		assert(false, "Error occur. %s" % query_result.get_err())
		return null
		
	if method_return_info.type == TYPE_NIL:
		return
		
	if method_return_info.type == TYPE_INT:
		return query_result.get_affected_rows()
		
	if method_return_info.class_name == "QueryResult":
		return query_result
		
	assert(false, "Method of <update> cannot return %s." % \
		GDSQL.DataTypeDef.DATA_TYPE_NAMES[method_return_info.type])
	return null
