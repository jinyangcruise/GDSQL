class_name GDSQLContentCacheManager
extends RefCounted
## Reuses a compatible cache or rebuilds it from immutable package sources.

var _overlay_loader: GDSQLContentOverlayLoader
var _fingerprints: GDSQLContentPackageFingerprintProvider
var _store: GDSQLContentCacheStore


func _init(
		overlay_loader: GDSQLContentOverlayLoader,
		fingerprint_provider: GDSQLContentPackageFingerprintProvider,
		cache_store: GDSQLContentCacheStore,
) -> void:
	_overlay_loader = overlay_loader
	_fingerprints = fingerprint_provider
	_store = cache_store


func ensure_cache(
		ordered_packages: Array[GDSQLContentPackageSource],
		source_database_name: StringName = GDSQLContentOverlayLoader.DEFAULT_SOURCE_DATABASE,
		effective_database_name: StringName = GDSQLContentOverlayLoader.DEFAULT_EFFECTIVE_DATABASE,
) -> GDSQLContentCacheResult:
	var result := GDSQLContentCacheResult.new()
	if _overlay_loader == null or _fingerprints == null or _store == null:
		return _error(
			result,
			&"GDSQL_CONTENT_CACHE_DEPENDENCY_REQUIRED",
			"Content cache construction requires an overlay loader, fingerprint provider, and store.",
		)
	var package_fingerprints: Array[GDSQLContentPackageFingerprint] = []
	for package in ordered_packages:
		var fingerprinted := _fingerprints.fingerprint(package)
		result.diagnostics.merge(fingerprinted.diagnostics)
		if fingerprinted.is_successful():
			package_fingerprints.append(
				fingerprinted.get_value() as GDSQLContentPackageFingerprint,
			)
	if not result.is_successful():
		return result
	var expected := GDSQLContentCacheManifest.new(
		source_database_name,
		effective_database_name,
		package_fingerprints,
	)
	var loaded := _store.load_manifest()
	result.diagnostics.merge(loaded.diagnostics)
	if not result.is_successful():
		return result
	var current := loaded.get_value() as GDSQLContentCacheManifest
	if expected.is_equivalent_to(current) and _store.has_database(effective_database_name):
		result.complete(GDSQLContentCacheResult.Status.HIT, current, _store.get_cache_root())
		return result
	var built := _overlay_loader.build_effective_database(
		ordered_packages,
		source_database_name,
		effective_database_name,
	)
	result.diagnostics.merge(built.diagnostics)
	if not result.is_successful():
		return result
	var replaced := _store.replace(expected, built.database)
	result.diagnostics.merge(replaced.diagnostics)
	if result.is_successful():
		result.complete(
			GDSQLContentCacheResult.Status.REBUILT,
			expected,
			_store.get_cache_root(),
		)
	return result


func _error(
		result: GDSQLContentCacheResult,
		code: StringName,
		message: String,
) -> GDSQLContentCacheResult:
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
