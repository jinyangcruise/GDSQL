class_name GDSQLConfigFileContentPackageDiscovery
extends GDSQLContentPackageDiscovery
## Discovers directory packages whose metadata is stored in manifest.cfg.

const CONTENT_DIRECTORY := "content"

var _manifest_store: GDSQLContentPackageManifestStore


func _init(manifest_store: GDSQLContentPackageManifestStore = null) -> void:
	_manifest_store = (
			manifest_store
			if manifest_store != null
			else GDSQLConfigFileContentPackageManifestStore.new()
	)


func discover(
		base_package_root: String,
		package_container_roots: Array[String],
) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	var packages: Array[GDSQLContentPackageSource] = []
	result.value = packages
	if base_package_root.strip_edges().is_empty():
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_CONTENT_BASE_PACKAGE_ROOT_REQUIRED",
				"A base content package root is required.",
			),
		)
	else:
		_load_source(base_package_root, packages, result)
	var seen_roots: Dictionary[String, bool] = { }
	seen_roots[base_package_root.simplify_path()] = true
	for container_root in package_container_roots:
		var directory := DirAccess.open(container_root)
		if directory == null:
			result.add_diagnostic(
				GDSQLQueryDiagnostic.new(
					&"GDSQL_CONTENT_PACKAGE_CONTAINER_UNAVAILABLE",
					"Package container '%s' is unavailable." % container_root,
					GDSQLQueryDiagnostic.Severity.WARNING,
				),
			)
			continue
		var directory_names := directory.get_directories()
		directory_names.sort()
		for directory_name in directory_names:
			var candidate := container_root.path_join(directory_name)
			var content_candidate := candidate.path_join(CONTENT_DIRECTORY)
			var package_root := ""
			if _has_manifest(content_candidate):
				package_root = content_candidate
			elif _has_manifest(candidate):
				package_root = candidate
			if package_root.is_empty():
				continue
			var normalized := package_root.simplify_path()
			if seen_roots.has(normalized):
				continue
			seen_roots[normalized] = true
			_load_source(package_root, packages, result)
	result.value = packages
	return result


func _load_source(
		package_root: String,
		packages: Array[GDSQLContentPackageSource],
		result: GDSQLOperationResult,
) -> void:
	var loaded := _manifest_store.load_manifest(package_root)
	result.diagnostics.merge(loaded.diagnostics)
	if loaded.is_successful():
		packages.append(
			GDSQLContentPackageSource.new(
				package_root.simplify_path(),
				loaded.get_value() as GDSQLContentPackageManifest,
			),
		)


func _has_manifest(package_root: String) -> bool:
	return FileAccess.file_exists(
		package_root.path_join(GDSQLConfigFileContentPackageManifestStore.MANIFEST_FILE),
	)
