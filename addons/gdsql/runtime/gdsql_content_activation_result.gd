class_name GDSQLContentActivationResult
extends GDSQLDatabaseResult
## Reports cache preparation and active content-role replacement together.

var cache_result: GDSQLContentCacheResult


func complete(
		database: GDSQLDatabase,
		prepared_cache: GDSQLContentCacheResult,
) -> void:
	value = database
	cache_result = prepared_cache


func was_rebuilt() -> bool:
	return cache_result != null and cache_result.was_rebuilt()
