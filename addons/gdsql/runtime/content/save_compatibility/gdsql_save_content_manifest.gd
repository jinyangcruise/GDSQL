class_name GDSQLSaveContentManifest
extends RefCounted
## Records the effective package set a save was created or confirmed against.

const CURRENT_FORMAT_VERSION := 1

var format_version: int = CURRENT_FORMAT_VERSION
var effective_database_name: StringName
var packages: Array[GDSQLContentPackageFingerprint] = []


func _init(
		effective_database: StringName = &"",
		expected_packages: Array[GDSQLContentPackageFingerprint] = [],
		manifest_format_version: int = CURRENT_FORMAT_VERSION,
) -> void:
	effective_database_name = effective_database
	packages = expected_packages.duplicate()
	format_version = manifest_format_version


static func from_cache_manifest(
		cache_manifest: GDSQLContentCacheManifest,
) -> GDSQLSaveContentManifest:
	if cache_manifest == null:
		return null
	var fingerprints: Array[GDSQLContentPackageFingerprint] = []
	for package in cache_manifest.packages:
		fingerprints.append(
			GDSQLContentPackageFingerprint.new(
				package.package_id,
				package.version,
				package.content_hash,
			),
		)
	return GDSQLSaveContentManifest.new(
		cache_manifest.effective_database_name,
		fingerprints,
	)
