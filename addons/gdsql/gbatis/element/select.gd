@tool
extends RefCounted
class_name GBatisSelect

var id = ""
var result_map = ""
var result_type = ""
var fetch_size = ""
var flush_cache = true
var use_cache = true
var database_id = ""
var sql = ""

func _init(conf: Dictionary) -> void:
	id = conf.get("id").strip_edges()
	result_map = conf.get("resultMap", "").strip_edges()
	result_type = conf.get("resultType", "").strip_edges()
	fetch_size = conf.get("fetchSize", "").strip_edges()
	flush_cache = type_convert(conf.get("flushCache", "false"), TYPE_BOOL).strip_edges()
	use_cache = type_convert(conf.get("useCache", "true"), TYPE_BOOL).strip_edges()
	database_id = conf.get("databaseId", "").strip_edges()
	
func set_sql(p_sql: String):
	sql = p_sql
	
func query():
	# cache TODO
	var dao = SQLParser.parse_to_dao(sql)
	if not database_id.is_empty():
		dao.use_db_name(database_id)
	var query_result = dao.query()
	
	# resultMap TODO transfer to a new QueryResult
	return query_result
