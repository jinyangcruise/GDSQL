class_name GDSQLConfigFileCacheLoadResult
extends RefCounted

var config: ConfigFile
var cache_hit := false
var bytes_read := -1


func _init(
	loaded_config: ConfigFile = null,
	was_cache_hit: bool = false,
	physical_bytes_read: int = -1,
) -> void:
	config = loaded_config
	cache_hit = was_cache_hit
	bytes_read = physical_bytes_read
