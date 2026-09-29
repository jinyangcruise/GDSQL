class_name GDSQLContentCacheResult
extends GDSQLOperationResult
## Reports whether effective content reused or rebuilt its disposable cache.

enum Status {
	HIT,
	REBUILT,
}

var status: Status
var manifest: GDSQLContentCacheManifest
var cache_root: String


func complete(
		cache_status: Status,
		cache_manifest: GDSQLContentCacheManifest,
		root: String,
) -> void:
	status = cache_status
	manifest = cache_manifest
	cache_root = root
	value = cache_manifest


func was_rebuilt() -> bool:
	return status == Status.REBUILT
