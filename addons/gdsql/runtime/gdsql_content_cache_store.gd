@abstract
class_name GDSQLContentCacheStore
extends RefCounted
## Persistence boundary for a disposable effective-content cache.

@abstract
func load_manifest() -> GDSQLOperationResult


@abstract
func has_database(database_name: StringName) -> bool


@abstract
func replace(
		manifest: GDSQLContentCacheManifest,
		database: GDSQLContentDatabaseSnapshot,
) -> GDSQLOperationResult


@abstract
func get_cache_root() -> String


func _tr(message: String) -> String:
	return TranslationServer.get_or_add_domain(&"GDSQL").translate(message)
