class_name GDSQLConfigFileContentPackageScaffolder
extends RefCounted
## Creates the editable directory envelope for a ConfigFile content package.

const MANIFEST_FILE := "manifest.cfg"
const PACKAGE_SECTION := "package"


func scaffold(
		package_root: String,
		manifest: GDSQLContentPackageManifest,
) -> GDSQLOperationResult:
	if package_root.strip_edges().is_empty():
		return _error(
			&"GDSQL_CONTENT_PACKAGE_ROOT_REQUIRED",
			"A content package root is required.",
		)
	var validated := GDSQLContentPackageManifestValidator.new().validate(manifest)
	if not validated.is_successful():
		return validated
	var result := GDSQLOperationResult.new()
	for path in [
		package_root,
		package_root.path_join(manifest.data_path),
		package_root.path_join(manifest.assets_path),
	]:
		var directory_error := DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(path),
		)
		if directory_error != OK:
			return _error(
				&"GDSQL_CONTENT_PACKAGE_DIRECTORY_CREATE_FAILED",
				"Could not create content package directory '%s' (error %d)." % [
					path,
					directory_error,
				],
			)
	var manifest_path := package_root.path_join(MANIFEST_FILE)
	var config := ConfigFile.new()
	if FileAccess.file_exists(manifest_path):
		var load_error := config.load(manifest_path)
		if load_error != OK:
			return _error(
				&"GDSQL_CONTENT_PACKAGE_MANIFEST_LOAD_FAILED",
				"Could not load content package manifest '%s' (error %d)." % [
					manifest_path,
					load_error,
				],
			)
	_set_missing(config, "id", String(manifest.package_id))
	_set_missing(config, "name", manifest.display_name)
	_set_missing(config, "version", manifest.version)
	_set_missing(config, "kind", GDSQLContentPackageKind.get_id(manifest.kind))
	_set_missing(config, "priority", manifest.priority)
	_set_missing(config, "data_path", manifest.data_path)
	_set_missing(config, "assets_path", manifest.assets_path)
	var save_error := config.save(manifest_path)
	if save_error != OK:
		return _error(
			&"GDSQL_CONTENT_PACKAGE_MANIFEST_SAVE_FAILED",
			"Could not save content package manifest '%s' (error %d)." % [
				manifest_path,
				save_error,
			],
		)
	var loaded := GDSQLConfigFileContentPackageManifestStore.new().load_manifest(package_root)
	result.diagnostics.merge(loaded.diagnostics)
	result.value = (
		GDSQLContentPackageSource.new(package_root, loaded.get_value())
		if loaded.is_successful()
		else null
	)
	return result


func _set_missing(config: ConfigFile, key: String, value: Variant) -> void:
	if not config.has_section_key(PACKAGE_SECTION, key):
		config.set_value(PACKAGE_SECTION, key, value)


func _error(code: StringName, message: String) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
