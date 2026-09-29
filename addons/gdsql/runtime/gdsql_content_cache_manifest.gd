class_name GDSQLContentCacheManifest
extends RefCounted
## Describes every input that makes a disposable content cache reusable.

const CURRENT_FORMAT_VERSION := 1

var format_version: int = CURRENT_FORMAT_VERSION
var source_database_name: StringName
var effective_database_name: StringName
var packages: Array[GDSQLContentPackageFingerprint] = []


func _init(
		source_database: StringName = &"",
		effective_database: StringName = &"",
		package_fingerprints: Array[GDSQLContentPackageFingerprint] = [],
		cache_format_version: int = CURRENT_FORMAT_VERSION,
) -> void:
	source_database_name = source_database
	effective_database_name = effective_database
	packages = package_fingerprints.duplicate()
	format_version = cache_format_version


func is_equivalent_to(other: GDSQLContentCacheManifest) -> bool:
	if other == null or format_version != other.format_version \
			or source_database_name != other.source_database_name \
			or effective_database_name != other.effective_database_name \
			or packages.size() != other.packages.size():
		return false
	for index in packages.size():
		if not packages[index].is_equivalent_to(other.packages[index]):
			return false
	return true
