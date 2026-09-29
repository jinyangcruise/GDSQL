class_name GDSQLConfigFileContentPackageManifestStore
extends GDSQLContentPackageManifestStore
## Reads human-authored package metadata from manifest.cfg.

const MANIFEST_FILE := "manifest.cfg"
const PACKAGE_SECTION := "package"
const DEPENDENCIES_SECTION := "dependencies"
const LOAD_ORDER_SECTION := "load_order"

var _validator: GDSQLContentPackageManifestValidator


func _init(validator: GDSQLContentPackageManifestValidator = null) -> void:
	_validator = validator if validator != null else GDSQLContentPackageManifestValidator.new()


func load_manifest(package_root: String) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if package_root.strip_edges().is_empty():
		return _error(
			&"GDSQL_CONTENT_PACKAGE_ROOT_REQUIRED",
			"A content package root is required.",
		)
	var manifest_path := package_root.path_join(MANIFEST_FILE)
	if not FileAccess.file_exists(manifest_path):
		return _error(
			&"GDSQL_CONTENT_PACKAGE_MANIFEST_NOT_FOUND",
			"Content package manifest '%s' was not found." % manifest_path,
		)
	var config := ConfigFile.new()
	var load_error := config.load(manifest_path)
	if load_error != OK:
		return _error(
			&"GDSQL_CONTENT_PACKAGE_MANIFEST_LOAD_FAILED",
			"Could not load content package manifest '%s' (error %d)." % [
				manifest_path,
				load_error,
			],
		)
	if not config.has_section(PACKAGE_SECTION):
		return _error(
			&"GDSQL_CONTENT_PACKAGE_SECTION_REQUIRED",
			"Content package manifest '%s' requires a [package] section." % manifest_path,
		)
	var package_id := StringName(config.get_value(PACKAGE_SECTION, "id", &""))
	var dependencies := _read_dependencies(config, result)
	var manifest := GDSQLContentPackageManifest.new(
		package_id,
		String(config.get_value(PACKAGE_SECTION, "name", package_id)),
		String(config.get_value(PACKAGE_SECTION, "version", "")),
		GDSQLContentPackageKind.from_string(
			String(config.get_value(PACKAGE_SECTION, "kind", "")),
		),
		int(config.get_value(PACKAGE_SECTION, "priority", 0)),
		String(config.get_value(PACKAGE_SECTION, "data_path", "data")),
		String(config.get_value(PACKAGE_SECTION, "assets_path", "assets")),
		dependencies,
		_read_package_ids(config, "after", result),
		_read_package_ids(config, "before", result),
	)
	var validated := _validator.validate(manifest)
	result.diagnostics.merge(validated.diagnostics)
	if result.is_successful():
		result.value = manifest
	return result


func _read_dependencies(
		config: ConfigFile,
		result: GDSQLOperationResult,
) -> Array[GDSQLContentPackageDependency]:
	var dependencies: Array[GDSQLContentPackageDependency] = []
	if not config.has_section(DEPENDENCIES_SECTION):
		return dependencies
	var package_ids := Array(config.get_section_keys(DEPENDENCIES_SECTION))
	package_ids.sort()
	for package_id in package_ids:
		var stored: Variant = config.get_value(DEPENDENCIES_SECTION, package_id, "*")
		if stored is not String and stored is not StringName:
			result.add_diagnostic(
				GDSQLQueryDiagnostic.new(
					&"GDSQL_CONTENT_PACKAGE_DEPENDENCY_TYPE_INVALID",
					"Dependency '%s' version constraint must be text." % package_id,
				),
			)
			continue
		dependencies.append(
			GDSQLContentPackageDependency.new(
				StringName(package_id),
				String(stored),
			),
		)
	return dependencies


func _read_package_ids(
		config: ConfigFile,
		key: String,
		result: GDSQLOperationResult,
) -> Array[StringName]:
	var package_ids: Array[StringName] = []
	if not config.has_section_key(LOAD_ORDER_SECTION, key):
		return package_ids
	var stored: Variant = config.get_value(LOAD_ORDER_SECTION, key, [])
	if stored is not Array and stored is not PackedStringArray:
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_CONTENT_PACKAGE_ORDER_TYPE_INVALID",
				"Load-order '%s' must be an array of package ids." % key,
			),
		)
		return package_ids
	for package_id in stored:
		package_ids.append(StringName(package_id))
	return package_ids


func _error(code: StringName, message: String) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
