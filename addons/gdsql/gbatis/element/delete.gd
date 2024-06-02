@tool
extends RefCounted
class_name GBatisDelete

var id = ""
var flush_cache = "true"
var database_id = ""
var sql = ""
var method_return_info: Dictionary

func _init(conf: Dictionary) -> void:
	id = conf.get("id").strip_edges()
	flush_cache = conf.get("flushCache", "true").strip_edges()
	database_id = conf.get("databaseId", "").strip_edges()
	
func set_sql(p_sql: String):
	sql = p_sql
	
func set_method_return_info(info: Dictionary):
	method_return_info = info
	
func query() -> QueryResult:
	return null
