class_name GDSQLConfigFileContentCacheStore
extends GDSQLContentCacheStore
## Persists a disposable effective-content cache through a staged directory swap.

const DEFAULT_CACHE_ROOT := "user://gdsql/cache/effective_content"
const MANIFEST_FILE := "manifest.cfg"
const CACHE_SECTION := "cache"
const PACKAGE_SECTION_PREFIX := "package:"

var _cache_root: String


func _init(cache_root: String = DEFAULT_CACHE_ROOT) -> void:
	_cache_root = cache_root.trim_suffix("/")


func load_manifest() -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	var path := _cache_root.path_join(MANIFEST_FILE)
	var config := ConfigFile.new()
	var load_error := config.load(path)
	if load_error == ERR_FILE_NOT_FOUND:
		return result
	if load_error != OK:
		return _cache_miss(
			result,
			&"GDSQL_CONTENT_CACHE_MANIFEST_UNREADABLE",
			"Could not read content cache manifest '%s'." % path,
		)
	if not config.has_section(CACHE_SECTION):
		return _cache_miss(
			result,
			&"GDSQL_CONTENT_CACHE_MANIFEST_INVALID",
			"Content cache manifest is missing its cache section.",
		)
	var package_order: Variant = config.get_value(
		CACHE_SECTION,
		"package_order",
		PackedStringArray(),
	)
	if not package_order is PackedStringArray and not package_order is Array:
		return _cache_miss(
			result,
			&"GDSQL_CONTENT_CACHE_MANIFEST_INVALID",
			"Content cache package order must be an array.",
		)
	var packages: Array[GDSQLContentPackageFingerprint] = []
	for package_id_value in package_order:
		var package_id := StringName(package_id_value)
		var section := PACKAGE_SECTION_PREFIX + String(package_id)
		if not config.has_section(section):
			return _cache_miss(
				result,
				&"GDSQL_CONTENT_CACHE_MANIFEST_INVALID",
				"Content cache manifest is missing package '%s'." % package_id,
			)
		packages.append(
			GDSQLContentPackageFingerprint.new(
				package_id,
				String(config.get_value(section, "version", "")),
				String(config.get_value(section, "content_hash", "")),
			),
		)
	result.value = GDSQLContentCacheManifest.new(
		StringName(config.get_value(CACHE_SECTION, "source_database", "")),
		StringName(config.get_value(CACHE_SECTION, "effective_database", "")),
		packages,
		int(config.get_value(CACHE_SECTION, "format_version", 0)),
	)
	return result


func has_database(database_name: StringName) -> bool:
	var resolver := GDSQLDatabasePathResolver.new(_cache_root)
	var database := GDSQLConfigFileCatalogService.new(
		resolver,
		GDSQLGodotVariantCodec.new(),
	).get_database(database_name)
	if database == null:
		return false
	for table in database.tables:
		var storage := ConfigFile.new()
		if storage.load(resolver.resolve_table_path(database_name, table.name)) != OK:
			return false
	return true


func replace(
		manifest: GDSQLContentCacheManifest,
		database: GDSQLContentDatabaseSnapshot,
) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if manifest == null or database == null or database.definition == null \
			or not _is_safe_root(_cache_root):
		return _error(
			result,
			&"GDSQL_CONTENT_CACHE_TARGET_INVALID",
			"Content cache replacement requires a snapshot and a bounded cache directory.",
		)
	var staging_root := _cache_root + ".building"
	var previous_root := _cache_root + ".previous"
	if not _remove_tree(staging_root) or not _remove_tree(previous_root):
		return _error(
			result,
			&"GDSQL_CONTENT_CACHE_CLEANUP_FAILED",
			"Could not prepare the content cache staging directories.",
		)
	var written := _write_snapshot(staging_root, database)
	result.diagnostics.merge(written.diagnostics)
	if not result.is_successful():
		_remove_tree(staging_root)
		return result
	var saved := _save_manifest(staging_root, manifest)
	result.diagnostics.merge(saved.diagnostics)
	if not result.is_successful():
		_remove_tree(staging_root)
		return result
	var cache_absolute := ProjectSettings.globalize_path(_cache_root)
	var staging_absolute := ProjectSettings.globalize_path(staging_root)
	var previous_absolute := ProjectSettings.globalize_path(previous_root)
	var had_cache := DirAccess.dir_exists_absolute(cache_absolute)
	if had_cache and DirAccess.rename_absolute(cache_absolute, previous_absolute) != OK:
		return _error(
			result,
			&"GDSQL_CONTENT_CACHE_REPLACE_FAILED",
			"Could not move the previous content cache aside.",
		)
	if DirAccess.rename_absolute(staging_absolute, cache_absolute) != OK:
		if had_cache:
			DirAccess.rename_absolute(previous_absolute, cache_absolute)
		return _error(
			result,
			&"GDSQL_CONTENT_CACHE_REPLACE_FAILED",
			"Could not activate the rebuilt content cache.",
		)
	_remove_tree(previous_root)
	result.value = true
	return result


func get_cache_root() -> String:
	return _cache_root


func _write_snapshot(
		root: String,
		snapshot: GDSQLContentDatabaseSnapshot,
) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	var created := GDSQLDatabase.create(snapshot.definition.name, root)
	result.diagnostics.merge(created.diagnostics)
	if not result.is_successful():
		return result
	var database := created.get_database()
	for index in snapshot.definition.tables.size():
		var table := snapshot.definition.tables[index]
		var table_created := database.create_table(table)
		result.diagnostics.merge(table_created.diagnostics)
		if not result.is_successful():
			return result
		var session := GDSQLStorageSession.new()
		for row in snapshot.tables[index].rows:
			var staged := database.context.storage.stage_insert(
				table,
				row.duplicate_record(),
				session,
			)
			result.diagnostics.merge(staged.diagnostics)
			if not result.is_successful():
				database.context.storage.rollback(session)
				return result
		var committed := database.context.storage.commit(session)
		result.diagnostics.merge(committed.diagnostics)
		if not result.is_successful():
			return result
	result.value = true
	return result


func _save_manifest(
		root: String,
		manifest: GDSQLContentCacheManifest,
) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	var config := ConfigFile.new()
	config.set_value(CACHE_SECTION, "format_version", manifest.format_version)
	config.set_value(CACHE_SECTION, "source_database", String(manifest.source_database_name))
	config.set_value(CACHE_SECTION, "effective_database", String(manifest.effective_database_name))
	var package_order := PackedStringArray()
	for package in manifest.packages:
		package_order.append(String(package.package_id))
		var section := PACKAGE_SECTION_PREFIX + String(package.package_id)
		config.set_value(section, "version", package.version)
		config.set_value(section, "content_hash", package.content_hash)
	config.set_value(CACHE_SECTION, "package_order", package_order)
	var path := root.path_join(MANIFEST_FILE)
	if config.save(path) != OK:
		return _error(
			result,
			&"GDSQL_CONTENT_CACHE_MANIFEST_SAVE_FAILED",
			"Could not save content cache manifest '%s'." % path,
		)
	result.value = true
	return result


func _is_safe_root(path: String) -> bool:
	var normalized := path.simplify_path().trim_suffix("/")
	return not normalized.is_empty() and normalized not in ["/", "res://", "user://"] \
			and normalized.contains("/cache/") and not normalized.get_file().is_empty()


func _remove_tree(path: String) -> bool:
	var absolute := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute):
		return true
	var directory := DirAccess.open(path)
	if directory == null:
		return false
	for file_name in directory.get_files():
		if DirAccess.remove_absolute(
			ProjectSettings.globalize_path(path.path_join(file_name)),
		) != OK:
			return false
	for directory_name in directory.get_directories():
		if not _remove_tree(path.path_join(directory_name)):
			return false
	return DirAccess.remove_absolute(absolute) == OK


func _error(
		result: GDSQLOperationResult,
		code: StringName,
		message: String,
) -> GDSQLOperationResult:
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result


func _cache_miss(
		result: GDSQLOperationResult,
		code: StringName,
		message: String,
) -> GDSQLOperationResult:
	result.add_diagnostic(
		GDSQLQueryDiagnostic.new(
			code,
			message,
			GDSQLQueryDiagnostic.Severity.WARNING,
		),
	)
	return result
