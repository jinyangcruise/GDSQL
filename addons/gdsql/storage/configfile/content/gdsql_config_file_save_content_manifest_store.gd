class_name GDSQLConfigFileSaveContentManifestStore
extends GDSQLSaveContentManifestStore
## Stores one save's content expectations beside its database catalog.

const FILE_NAME := "content_manifest.cfg"
const CONTENT_SECTION := "content"
const PACKAGE_SECTION_PREFIX := "package:"

var _save_root: String


func _init(save_root: String) -> void:
	_save_root = save_root.trim_suffix("/")


func load_manifest() -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	var path := _save_root.path_join(FILE_NAME)
	var config := ConfigFile.new()
	var load_error := config.load(path)
	if load_error == ERR_FILE_NOT_FOUND:
		return result
	if load_error != OK:
		return _error(result, &"GDSQL_SAVE_CONTENT_MANIFEST_UNREADABLE", path)
	var format_version := int(config.get_value(CONTENT_SECTION, "format_version", 0))
	var package_order: Variant = config.get_value(
		CONTENT_SECTION,
		"package_order",
		PackedStringArray(),
	)
	if format_version != GDSQLSaveContentManifest.CURRENT_FORMAT_VERSION \
			or not package_order is PackedStringArray and not package_order is Array:
		return _error(result, &"GDSQL_SAVE_CONTENT_MANIFEST_INVALID", path)
	var packages: Array[GDSQLContentPackageFingerprint] = []
	var seen: Dictionary[StringName, bool] = { }
	for package_id_value in package_order:
		var package_id := StringName(package_id_value)
		var section := PACKAGE_SECTION_PREFIX + String(package_id)
		if package_id == &"" or seen.has(package_id) or not config.has_section(section):
			return _error(result, &"GDSQL_SAVE_CONTENT_MANIFEST_INVALID", path)
		seen[package_id] = true
		packages.append(
			GDSQLContentPackageFingerprint.new(
				package_id,
				String(config.get_value(section, "version", "")),
				String(config.get_value(section, "content_hash", "")),
			),
		)
	var manifest := GDSQLSaveContentManifest.new(
		StringName(config.get_value(CONTENT_SECTION, "effective_database", "")),
		packages,
		format_version,
	)
	if not _is_valid_manifest(manifest):
		return _error(result, &"GDSQL_SAVE_CONTENT_MANIFEST_INVALID", path)
	result.value = manifest
	return result


func save_manifest(manifest: GDSQLSaveContentManifest) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if not _is_valid_manifest(manifest) or _save_root.is_empty() \
			or _save_root.begins_with("res://"):
		return _error(
			result,
			&"GDSQL_SAVE_CONTENT_MANIFEST_TARGET_INVALID",
			_save_root.path_join(FILE_NAME),
		)
	var config := ConfigFile.new()
	config.set_value(CONTENT_SECTION, "format_version", manifest.format_version)
	config.set_value(
		CONTENT_SECTION,
		"effective_database",
		String(manifest.effective_database_name),
	)
	var package_order := PackedStringArray()
	for package in manifest.packages:
		package_order.append(String(package.package_id))
		var section := PACKAGE_SECTION_PREFIX + String(package.package_id)
		config.set_value(section, "version", package.version)
		config.set_value(section, "content_hash", package.content_hash)
	config.set_value(CONTENT_SECTION, "package_order", package_order)
	var path := _save_root.path_join(FILE_NAME)
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_save_root)) != OK \
			or config.save(path) != OK:
		return _error(result, &"GDSQL_SAVE_CONTENT_MANIFEST_SAVE_FAILED", path)
	result.value = true
	return result


func _is_valid_manifest(manifest: GDSQLSaveContentManifest) -> bool:
	if manifest == null \
			or manifest.format_version != GDSQLSaveContentManifest.CURRENT_FORMAT_VERSION \
			or manifest.effective_database_name == &"" or manifest.packages.is_empty():
		return false
	var seen: Dictionary[StringName, bool] = { }
	for package in manifest.packages:
		if package == null or package.package_id == &"" or package.version.is_empty() \
				or package.content_hash.is_empty() or seen.has(package.package_id):
			return false
		seen[package.package_id] = true
	return true


func _error(
		result: GDSQLOperationResult,
		code: StringName,
		path: String,
) -> GDSQLOperationResult:
	result.add_diagnostic(
		GDSQLQueryDiagnostic.new(
			code,
			"Could not use save content manifest '%s'." % path,
		),
	)
	return result
