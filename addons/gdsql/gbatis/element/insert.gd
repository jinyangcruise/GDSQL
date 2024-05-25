@tool
extends RefCounted
class_name GBatisInsert

var id = ""
var flush_cache = ""
var use_generated_keys = ""
var database_id = ""
var sql = ""

func _init(conf: Dictionary) -> void:
	id = conf.get("id").strip_edges()
	flush_cache = conf.get("flushCache", "true").strip_edges()
	use_generated_keys = conf.get("useGeneratedKeys", "false").strip_edges()
	database_id = conf.get("databaseId", "").strip_edges()
	
func set_sql(p_sql: String):
	sql = p_sql
	
func query() -> QueryResult:
	return null
