class_name GDSQLConfigFileSetupProfileStore
extends GDSQLSetupProfileStore
## Persists the selected setup profile in project-owned GDSQL settings.

const DEFAULT_PATH := "res://.gdsql/settings.cfg"
const SECTION := "setup"
const PROFILE_KEY := "profile"

var _settings_path: String


func _init(settings_path: String = DEFAULT_PATH) -> void:
	_settings_path = settings_path


func load_profile() -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	var config := ConfigFile.new()
	var load_error := config.load(_settings_path)
	if load_error != OK and load_error != ERR_FILE_NOT_FOUND:
		return _error(
			&"GDSQL_SETUP_PROFILE_LOAD_FAILED",
			"Could not load setup profile from '%s' (error %d)." % [
				_settings_path,
				load_error,
			],
		)
	var stored := StringName(config.get_value(SECTION, PROFILE_KEY, &""))
	var profile := GDSQLSetupProfile.from_id(stored)
	if stored != &"" and profile == GDSQLSetupProfile.Kind.UNSELECTED:
		return _error(
			&"GDSQL_SETUP_PROFILE_INVALID",
			"Unknown GDSQL setup profile '%s'." % stored,
		)
	result.value = profile
	return result


func save_profile(profile: GDSQLSetupProfile.Kind) -> GDSQLOperationResult:
	if not GDSQLSetupProfile.is_selectable(profile):
		return _error(
			&"GDSQL_SETUP_PROFILE_INVALID",
			"Choose either the direct or managed content profile.",
		)
	var config_result := _load_for_write()
	if not config_result.is_successful():
		return config_result
	var config := config_result.get_value() as ConfigFile
	config.set_value(SECTION, PROFILE_KEY, GDSQLSetupProfile.get_id(profile))
	return _save(config, profile)


func clear_profile() -> GDSQLOperationResult:
	var config_result := _load_for_write()
	if not config_result.is_successful():
		return config_result
	var config := config_result.get_value() as ConfigFile
	if config.has_section_key(SECTION, PROFILE_KEY):
		config.erase_section_key(SECTION, PROFILE_KEY)
	if config.has_section(SECTION) and config.get_section_keys(SECTION).is_empty():
		config.erase_section(SECTION)
	return _save(config, GDSQLSetupProfile.Kind.UNSELECTED)


func _load_for_write() -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	var config := ConfigFile.new()
	var load_error := config.load(_settings_path)
	if load_error != OK and load_error != ERR_FILE_NOT_FOUND:
		return _error(
			&"GDSQL_SETUP_PROFILE_LOAD_FAILED",
			"Could not load setup settings '%s' (error %d)." % [_settings_path, load_error],
		)
	result.value = config
	return result


func _save(config: ConfigFile, value: Variant) -> GDSQLOperationResult:
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(_settings_path.get_base_dir()),
	)
	if directory_error != OK:
		return _error(
			&"GDSQL_SETUP_PROFILE_DIRECTORY_FAILED",
			"Could not create the GDSQL settings directory (error %d)." % directory_error,
		)
	var save_error := config.save(_settings_path)
	if save_error != OK:
		return _error(
			&"GDSQL_SETUP_PROFILE_SAVE_FAILED",
			"Could not save setup profile to '%s' (error %d)." % [
				_settings_path,
				save_error,
			],
		)
	var result := GDSQLOperationResult.new()
	result.value = value
	return result


func _error(code: StringName, message: String) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
