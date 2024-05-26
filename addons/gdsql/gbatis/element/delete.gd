@tool
extends RefCounted
class_name GBatisDelete

var id = ""
var flush_cache = true
var database_id = ""
var sql = ""

func _init(conf: Dictionary) -> void:
	id = conf.get("id").strip_edges()
	flush_cache = type_convert(conf.get("flushCache", "true").strip_edges(), TYPE_BOOL)
	database_id = conf.get("databaseId", "").strip_edges()
	
func set_sql(p_sql: String):
	sql = p_sql
	
func query() -> QueryResult:
	return null
