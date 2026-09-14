class_name GDSQLConfigFileManagedContentConfigurationStore
extends GDSQLManagedContentConfigurationStore
## Persists typed managed-content inputs while preserving other settings.

const DEFAULT_PATH := "res://.gdsql/settings.cfg"
const SECTION := "managed_content"

var _settings_path: String


func _init(settings_path: String = DEFAULT_PATH) -> void:
	_settings_path = settings_path


func load_configuration() -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	var config := ConfigFile.new()
	var load_error := config.load(_settings_path)
	if load_error != OK and load_error != ERR_FILE_NOT_FOUND:
		return _error(
			&"GDSQL_MANAGED_CONTENT_SETTINGS_LOAD_FAILED",
			"Could not load managed-content settings from '%s' (error %d)." % [
				_settings_path,
				load_error,
			],
		)
	var defaults := GDSQLManagedContentConfiguration.create_default()
	var base_root: Variant = config.get_value(
		SECTION,
		"base_package_root",
		defaults.base_package_root,
	)
	var package_roots: Variant = config.get_value(
		SECTION,
		"package_container_roots",
		PackedStringArray(defaults.package_container_roots),
	)
	var enabled_ids: Variant = config.get_value(
		SECTION,
		"enabled_package_ids",
		PackedStringArray(defaults.enabled_package_ids),
	)
	if not base_root is String or not _is_string_collection(package_roots) \
			or not _is_string_collection(enabled_ids):
		return _error(
			&"GDSQL_MANAGED_CONTENT_SETTINGS_INVALID",
			"Managed-content roots and enabled package IDs must be strings or string arrays.",
		)
	var roots: Array[String] = []
	for value in package_roots:
		roots.append(String(value))
	var ids: Array[StringName] = []
	for value in enabled_ids:
		ids.append(StringName(value))
	result.value = GDSQLManagedContentConfiguration.new(String(base_root), roots, ids)
	return result


func save_configuration(
		configuration: GDSQLManagedContentConfiguration,
) -> GDSQLOperationResult:
	if configuration == null:
		return _error(
			&"GDSQL_MANAGED_CONTENT_SETTINGS_REQUIRED",
			"Managed-content configuration is required.",
		)
	var config := ConfigFile.new()
	var load_error := config.load(_settings_path)
	if load_error != OK and load_error != ERR_FILE_NOT_FOUND:
		return _error(
			&"GDSQL_MANAGED_CONTENT_SETTINGS_LOAD_FAILED",
			"Could not load managed-content settings from '%s' (error %d)." % [
				_settings_path,
				load_error,
			],
		)
	config.set_value(SECTION, "base_package_root", configuration.base_package_root)
	config.set_value(
		SECTION,
		"package_container_roots",
		PackedStringArray(configuration.package_container_roots),
	)
	config.set_value(
		SECTION,
		"enabled_package_ids",
		PackedStringArray(configuration.enabled_package_ids),
	)
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(_settings_path.get_base_dir()),
	)
	if directory_error != OK:
		return _error(
			&"GDSQL_MANAGED_CONTENT_SETTINGS_DIRECTORY_FAILED",
			"Could not create the managed-content settings directory (error %d)." \
					% directory_error,
		)
	var save_error := config.save(_settings_path)
	if save_error != OK:
		return _error(
			&"GDSQL_MANAGED_CONTENT_SETTINGS_SAVE_FAILED",
			"Could not save managed-content settings to '%s' (error %d)." % [
				_settings_path,
				save_error,
			],
		)
	var result := GDSQLOperationResult.new()
	result.value = configuration
	return result


func _is_string_collection(value: Variant) -> bool:
	if not value is Array and not value is PackedStringArray:
		return false
	for item in value:
		if not item is String and not item is StringName:
			return false
	return true


func _error(code: StringName, message: String) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
