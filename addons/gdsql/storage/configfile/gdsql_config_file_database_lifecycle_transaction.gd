class_name GDSQLConfigFileDatabaseLifecycleTransaction
extends RefCounted
## Coordinates root registration visibility with physical database lifecycle.

const BUILDING_SUFFIX := ".building"
const PREVIOUS_SUFFIX := ".previous"
const DROPPING_SUFFIX := ".dropping"
const PREPARING_SUFFIX := ".preparing"
const COMMITTED_SUFFIX := ".committed"
const CONFIG_EXTENSION := ".cfg"
const TRANSACTION_SECTION := "transaction"
const REGISTER_DATABASE_KIND := "register_database"
const UNREGISTER_DATABASE_KIND := "unregister_database"
const RENAME_DATABASE_KIND := "rename_database"
const DROP_DATABASE_KIND := "drop_database"

var _path_resolver: GDSQLDatabasePathResolver


func _init(path_resolver: GDSQLDatabasePathResolver) -> void:
	assert(path_resolver != null)
	_path_resolver = path_resolver


func register_database(database_name: StringName) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if not _path_resolver.is_valid_name(database_name):
		return _error(
			result,
			&"GDSQL_DATABASE_LIFECYCLE_INVALID",
			"Database registration requires a valid identifier.",
		)
	var recovered := recover()
	result.diagnostics.merge(recovered.diagnostics)
	if not recovered.is_successful():
		return result
	var had_registry := FileAccess.file_exists(_registry_path())
	var registry_result := _load_registry(true)
	result.diagnostics.merge(registry_result.diagnostics)
	if not registry_result.is_successful():
		return result
	var registry := registry_result.value as ConfigFile
	if registry.has_section(String(database_name)) \
			or not _directory_exists(
				_path_resolver.resolve_database_path(database_name),
			):
		return _error(
			result,
			&"GDSQL_DATABASE_REGISTER_STATE_INVALID",
			"Database registration requires an unregistered physical database.",
		)
	registry.set_value(
		String(database_name),
		"path",
		_path_resolver.resolve_database_path(database_name),
	)
	return _replace_registration(
		result,
		registry,
		REGISTER_DATABASE_KIND,
		database_name,
		had_registry,
	)


func unregister_database(database_name: StringName) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if not _path_resolver.is_valid_name(database_name):
		return _error(
			result,
			&"GDSQL_DATABASE_LIFECYCLE_INVALID",
			"Database unregister requires a valid identifier.",
		)
	var recovered := recover()
	result.diagnostics.merge(recovered.diagnostics)
	if not recovered.is_successful():
		return result
	var registry_result := _load_registry()
	result.diagnostics.merge(registry_result.diagnostics)
	if not registry_result.is_successful():
		return result
	var registry := registry_result.value as ConfigFile
	if not registry.has_section(String(database_name)):
		return _error(
			result,
			&"GDSQL_DATABASE_UNREGISTER_STATE_INVALID",
			"Database unregister requires an existing registration.",
		)
	registry.erase_section(String(database_name))
	return _replace_registration(
		result,
		registry,
		UNREGISTER_DATABASE_KIND,
		database_name,
		true,
	)


func rename_database(
		current_name: StringName,
		new_name: StringName,
) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if not _is_valid_rename(current_name, new_name):
		return _error(
			result,
			&"GDSQL_DATABASE_LIFECYCLE_INVALID",
			"Database rename requires distinct valid identifiers.",
		)
	var recovered := recover()
	result.diagnostics.merge(recovered.diagnostics)
	if not recovered.is_successful():
		return result
	var registry_result := _load_registry()
	result.diagnostics.merge(registry_result.diagnostics)
	if not registry_result.is_successful():
		return result
	var registry := registry_result.value as ConfigFile
	if not registry.has_section(String(current_name)) \
			or registry.has_section(String(new_name)):
		return _error(
			result,
			&"GDSQL_DATABASE_RENAME_STATE_INVALID",
			"Database rename requires one registered source and an empty target.",
		)
	var old_path := _path_resolver.resolve_database_path(current_name)
	var new_path := _path_resolver.resolve_database_path(new_name)
	if not _directory_exists(old_path) or _directory_exists(new_path):
		return _error(
			result,
			&"GDSQL_DATABASE_RENAME_STATE_INVALID",
			"Database rename requires one source directory and an empty target.",
		)
	registry.erase_section(String(current_name))
	registry.set_value(String(new_name), "path", new_path)
	var staged := _stage_registry(registry)
	result.diagnostics.merge(staged.diagnostics)
	if not staged.is_successful():
		return result
	var marker := _create_marker(
		RENAME_DATABASE_KIND,
		current_name,
		new_name,
	)
	result.diagnostics.merge(marker.diagnostics)
	if not marker.is_successful():
		_remove_file(_registry_path() + BUILDING_SUFFIX)
		return result
	var preparing_path := String(marker.value)
	if _rename(old_path, new_path) != OK \
			or _activate_staged_registry() != OK:
		_recover_rename(preparing_path, false)
		return _activation_error(result, current_name, "rename")
	var committed_path := _commit_marker(preparing_path)
	if committed_path.is_empty():
		_recover_rename(preparing_path, false)
		return _activation_error(result, current_name, "rename")
	_cleanup_rename(committed_path, result)
	result.value = true
	return result


func drop_database(database_name: StringName) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if not _path_resolver.is_valid_name(database_name):
		return _error(
			result,
			&"GDSQL_DATABASE_LIFECYCLE_INVALID",
			"Database removal requires a valid identifier.",
		)
	var recovered := recover()
	result.diagnostics.merge(recovered.diagnostics)
	if not recovered.is_successful():
		return result
	var registry_result := _load_registry()
	result.diagnostics.merge(registry_result.diagnostics)
	if not registry_result.is_successful():
		return result
	var registry := registry_result.value as ConfigFile
	if not registry.has_section(String(database_name)):
		return _error(
			result,
			&"GDSQL_DATABASE_DROP_STATE_INVALID",
			"Database removal requires a registered source.",
		)
	var database_path := _path_resolver.resolve_database_path(database_name)
	var dropping_path := database_path + DROPPING_SUFFIX
	if not _directory_exists(database_path) or _directory_exists(dropping_path):
		return _error(
			result,
			&"GDSQL_DATABASE_DROP_STATE_INVALID",
			"Database removal requires one source directory and an empty quarantine.",
		)
	registry.erase_section(String(database_name))
	var staged := _stage_registry(registry)
	result.diagnostics.merge(staged.diagnostics)
	if not staged.is_successful():
		return result
	var marker := _create_marker(
		DROP_DATABASE_KIND,
		database_name,
		&"",
	)
	result.diagnostics.merge(marker.diagnostics)
	if not marker.is_successful():
		_remove_file(_registry_path() + BUILDING_SUFFIX)
		return result
	var preparing_path := String(marker.value)
	if _rename(database_path, dropping_path) != OK \
			or _activate_staged_registry() != OK:
		_recover_drop(preparing_path, false)
		return _activation_error(result, database_name, "drop")
	var committed_path := _commit_marker(preparing_path)
	if committed_path.is_empty():
		_recover_drop(preparing_path, false)
		return _activation_error(result, database_name, "drop")
	_cleanup_drop(committed_path, dropping_path, result)
	result.value = true
	return result


func recover() -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	var root := _path_resolver.resolve_catalog_transaction_root()
	var directory := DirAccess.open(root)
	if directory == null:
		if _directory_exists(root):
			return _recovery_error(result)
		if _recover_orphan_registry_files() != OK:
			return _recovery_error(result)
		result.value = 0
		return result
	var recovered_count := 0
	var files := directory.get_files()
	files.sort()
	for file_name in files:
		var marker_path := root.path_join(file_name)
		if file_name.ends_with(PREPARING_SUFFIX + BUILDING_SUFFIX):
			if _remove_file(marker_path) != OK:
				return _recovery_error(result)
			continue
		if not file_name.ends_with(PREPARING_SUFFIX) \
				and not file_name.ends_with(COMMITTED_SUFFIX):
			continue
		var marker := ConfigFile.new()
		if marker.load(marker_path) != OK:
			return _recovery_error(result)
		var committed := file_name.ends_with(COMMITTED_SUFFIX)
		var recovery_error := ERR_INVALID_DATA
		match String(marker.get_value(TRANSACTION_SECTION, "kind", "")):
			REGISTER_DATABASE_KIND:
				recovery_error = _recover_registration(marker_path, committed, true)
			UNREGISTER_DATABASE_KIND:
				recovery_error = _recover_registration(marker_path, committed, false)
			RENAME_DATABASE_KIND:
				recovery_error = _recover_rename(marker_path, committed)
			DROP_DATABASE_KIND:
				recovery_error = _recover_drop(marker_path, committed)
		if recovery_error == ERR_BUSY and committed:
			_add_cleanup_warning(result)
		elif recovery_error != OK:
			return _recovery_error(result)
		recovered_count += 1
	if _recover_orphan_registry_files() != OK:
		return _recovery_error(result)
	result.value = recovered_count
	return result


func _replace_registration(
		result: GDSQLOperationResult,
		registry: ConfigFile,
		kind: String,
		database_name: StringName,
		had_registry: bool,
) -> GDSQLOperationResult:
	var staged := _stage_registry(registry)
	result.diagnostics.merge(staged.diagnostics)
	if not staged.is_successful():
		return result
	var marker := _create_marker(
		kind,
		database_name,
		&"",
		had_registry,
	)
	result.diagnostics.merge(marker.diagnostics)
	if not marker.is_successful():
		_remove_file(_registry_path() + BUILDING_SUFFIX)
		return result
	var preparing_path := String(marker.value)
	if _activate_staged_registry(had_registry) != OK:
		_recover_registration(
			preparing_path,
			false,
			kind == REGISTER_DATABASE_KIND,
		)
		return _activation_error(result, database_name, "registration")
	var committed_path := _commit_marker(preparing_path)
	if committed_path.is_empty():
		_recover_registration(
			preparing_path,
			false,
			kind == REGISTER_DATABASE_KIND,
		)
		return _activation_error(result, database_name, "registration")
	if _cleanup_registry_and_marker(committed_path) != OK:
		_add_cleanup_warning(result)
	result.value = true
	return result


func _recover_registration(
		marker_path: String,
		committed: bool,
		registering: bool,
) -> Error:
	var marker := _load_marker(marker_path)
	if marker == null:
		return ERR_FILE_CORRUPT
	var database_name := StringName(
		marker.get_value(TRANSACTION_SECTION, "source", ""),
	)
	if not _path_resolver.is_valid_name(database_name):
		return ERR_INVALID_DATA
	var had_registry := bool(
		marker.get_value(TRANSACTION_SECTION, "had_registry", true),
	)
	if committed:
		var is_registered := _registry_has(database_name)
		if is_registered != registering:
			return ERR_FILE_CORRUPT
		return _cleanup_registry_and_marker(marker_path)
	if _restore_previous_registry(had_registry) != OK:
		return ERR_CANT_CREATE
	var is_registered := _registry_has(database_name)
	if is_registered == registering:
		return ERR_FILE_CORRUPT
	return _remove_file(marker_path)


func _recover_rename(marker_path: String, committed: bool) -> Error:
	var marker := _load_marker(marker_path)
	if marker == null:
		return ERR_FILE_CORRUPT
	var current_name := StringName(
		marker.get_value(TRANSACTION_SECTION, "source", ""),
	)
	var new_name := StringName(
		marker.get_value(TRANSACTION_SECTION, "target", ""),
	)
	if not _is_valid_rename(current_name, new_name):
		return ERR_INVALID_DATA
	var old_path := _path_resolver.resolve_database_path(current_name)
	var new_path := _path_resolver.resolve_database_path(new_name)
	if committed:
		if not _registry_has_only(new_name, current_name) \
				or not _directory_exists(new_path):
			return ERR_FILE_CORRUPT
		if _directory_exists(old_path) \
				and _remove_directory_recursive(old_path) != OK:
			return ERR_BUSY
		return _cleanup_registry_and_marker(marker_path)
	if _directory_exists(new_path):
		if _directory_exists(old_path) or _rename(new_path, old_path) != OK:
			return ERR_CANT_CREATE
	if _restore_previous_registry() != OK:
		return ERR_CANT_CREATE
	if not _registry_has_only(current_name, new_name) \
			or not _directory_exists(old_path) \
			or _directory_exists(new_path):
		return ERR_FILE_CORRUPT
	return _remove_file(marker_path)


func _recover_drop(marker_path: String, committed: bool) -> Error:
	var marker := _load_marker(marker_path)
	if marker == null:
		return ERR_FILE_CORRUPT
	var database_name := StringName(
		marker.get_value(TRANSACTION_SECTION, "source", ""),
	)
	if not _path_resolver.is_valid_name(database_name):
		return ERR_INVALID_DATA
	var database_path := _path_resolver.resolve_database_path(database_name)
	var dropping_path := database_path + DROPPING_SUFFIX
	if committed:
		if _registry_has(database_name):
			return ERR_FILE_CORRUPT
		if _directory_exists(database_path) \
				and _remove_directory_recursive(database_path) != OK:
			return ERR_BUSY
		if _remove_directory_recursive(dropping_path) != OK:
			return ERR_BUSY
		return _cleanup_registry_and_marker(marker_path)
	if _directory_exists(dropping_path):
		if _directory_exists(database_path) \
				or _rename(dropping_path, database_path) != OK:
			return ERR_CANT_CREATE
	if _restore_previous_registry() != OK:
		return ERR_CANT_CREATE
	if not _registry_has(database_name) or not _directory_exists(database_path):
		return ERR_FILE_CORRUPT
	return _remove_file(marker_path)


func _stage_registry(registry: ConfigFile) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	var building_path := _registry_path() + BUILDING_SUFFIX
	if registry.save(building_path) != OK:
		_remove_file(building_path)
		return _error(
			result,
			&"GDSQL_DATABASE_LIFECYCLE_STAGE_FAILED",
			"Could not stage the updated database registry.",
		)
	result.value = true
	return result


func _activate_staged_registry(had_registry: bool = true) -> Error:
	var registry_path := _registry_path()
	if had_registry \
			and _rename(registry_path, registry_path + PREVIOUS_SUFFIX) != OK:
		return ERR_CANT_CREATE
	if _rename(registry_path + BUILDING_SUFFIX, registry_path) == OK:
		return OK
	if had_registry:
		_rename(registry_path + PREVIOUS_SUFFIX, registry_path)
	return ERR_CANT_CREATE


func _restore_previous_registry(had_registry: bool = true) -> Error:
	var registry_path := _registry_path()
	var previous_path := registry_path + PREVIOUS_SUFFIX
	if FileAccess.file_exists(previous_path):
		if _remove_file(registry_path) != OK \
				or _rename(previous_path, registry_path) != OK:
			return ERR_CANT_CREATE
	elif not had_registry and _remove_file(registry_path) != OK:
		return ERR_CANT_CREATE
	return _remove_file(registry_path + BUILDING_SUFFIX)


func _recover_orphan_registry_files() -> Error:
	var registry_path := _registry_path()
	var building_path := registry_path + BUILDING_SUFFIX
	var previous_path := registry_path + PREVIOUS_SUFFIX
	var has_building := FileAccess.file_exists(building_path)
	var has_previous := FileAccess.file_exists(previous_path)
	if has_building and has_previous:
		if _remove_file(registry_path) != OK \
				or _rename(previous_path, registry_path) != OK:
			return ERR_CANT_CREATE
		return _remove_file(building_path)
	if has_building:
		return _remove_file(building_path)
	if not has_previous:
		return OK
	if FileAccess.file_exists(registry_path):
		return _remove_file(previous_path)
	return _rename(previous_path, registry_path)


func _create_marker(
		kind: String,
		source: StringName,
		target: StringName,
		had_registry: bool = true,
) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	var root := _path_resolver.resolve_catalog_transaction_root()
	if DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(root),
	) != OK:
		return _error(
			result,
			&"GDSQL_DATABASE_LIFECYCLE_DIRECTORY_FAILED",
			"Could not create database transaction directory '%s'." % root,
		)
	var marker_id := "%s__%s" % [kind, source]
	if target != &"":
		marker_id += "__%s" % target
	var preparing_path := root.path_join(
		marker_id + CONFIG_EXTENSION + PREPARING_SUFFIX,
	)
	var building_path := preparing_path + BUILDING_SUFFIX
	var marker := ConfigFile.new()
	marker.set_value(TRANSACTION_SECTION, "kind", kind)
	marker.set_value(TRANSACTION_SECTION, "source", String(source))
	marker.set_value(TRANSACTION_SECTION, "target", String(target))
	marker.set_value(TRANSACTION_SECTION, "had_registry", had_registry)
	if marker.save(building_path) != OK \
			or _rename(building_path, preparing_path) != OK:
		_remove_file(building_path)
		return _error(
			result,
			&"GDSQL_DATABASE_LIFECYCLE_MARKER_FAILED",
			"Could not persist database lifecycle intent for '%s'." % source,
		)
	result.value = preparing_path
	return result


func _commit_marker(preparing_path: String) -> String:
	var committed_path := preparing_path.trim_suffix(PREPARING_SUFFIX) \
			+ COMMITTED_SUFFIX
	return committed_path if _rename(preparing_path, committed_path) == OK else ""


func _cleanup_rename(
		marker_path: String,
		result: GDSQLOperationResult,
) -> void:
	if _cleanup_registry_and_marker(marker_path) != OK:
		_add_cleanup_warning(result)


func _cleanup_drop(
		marker_path: String,
		dropping_path: String,
		result: GDSQLOperationResult,
) -> void:
	if _remove_directory_recursive(dropping_path) != OK \
			or _cleanup_registry_and_marker(marker_path) != OK:
		_add_cleanup_warning(result)


func _cleanup_registry_and_marker(marker_path: String) -> Error:
	if _remove_file(_registry_path() + PREVIOUS_SUFFIX) != OK \
			or _remove_file(_registry_path() + BUILDING_SUFFIX) != OK \
			or _remove_file(marker_path) != OK:
		return ERR_BUSY
	return OK


func _load_registry(allow_missing: bool = false) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	var registry := ConfigFile.new()
	var load_error := registry.load(_registry_path())
	if load_error != OK and not (allow_missing and load_error == ERR_FILE_NOT_FOUND):
		return _error(
			result,
			&"GDSQL_DATABASE_LIFECYCLE_REGISTRY_UNREADABLE",
			"Could not read the database registry.",
		)
	result.value = registry
	return result


func _load_marker(path: String) -> ConfigFile:
	var marker := ConfigFile.new()
	return marker if marker.load(path) == OK else null


func _registry_has(database_name: StringName) -> bool:
	var registry := ConfigFile.new()
	return registry.load(_registry_path()) == OK \
			and registry.has_section(String(database_name))


func _registry_has_only(
		present_name: StringName,
		absent_name: StringName,
) -> bool:
	var registry := ConfigFile.new()
	return registry.load(_registry_path()) == OK \
			and registry.has_section(String(present_name)) \
			and not registry.has_section(String(absent_name))


func _remove_directory_recursive(path: String) -> Error:
	if not _directory_exists(path):
		return OK
	var directory := DirAccess.open(path)
	if directory == null:
		return ERR_CANT_OPEN
	for file_name in directory.get_files():
		if _remove_file(path.path_join(file_name)) != OK:
			return ERR_CANT_CREATE
	for directory_name in directory.get_directories():
		if _remove_directory_recursive(path.path_join(directory_name)) != OK:
			return ERR_CANT_CREATE
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _registry_path() -> String:
	return _path_resolver.resolve_catalog_path()


func _directory_exists(path: String) -> bool:
	return DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path))


func _remove_file(path: String) -> Error:
	if not FileAccess.file_exists(path):
		return OK
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _rename(source: String, destination: String) -> Error:
	return DirAccess.rename_absolute(
		ProjectSettings.globalize_path(source),
		ProjectSettings.globalize_path(destination),
	)


func _is_valid_rename(
		current_name: StringName,
		new_name: StringName,
) -> bool:
	return _path_resolver.is_valid_name(current_name) \
			and _path_resolver.is_valid_name(new_name) \
			and current_name != new_name


func _add_cleanup_warning(result: GDSQLOperationResult) -> void:
	result.add_diagnostic(
		GDSQLQueryDiagnostic.new(
			&"GDSQL_DATABASE_LIFECYCLE_CLEANUP_PENDING",
			"Database operation committed, but recovery artifacts remain for retry.",
			GDSQLQueryDiagnostic.Severity.WARNING,
		),
	)


func _activation_error(
		result: GDSQLOperationResult,
		database_name: StringName,
		operation: String,
) -> GDSQLOperationResult:
	return _error(
		result,
		&"GDSQL_DATABASE_LIFECYCLE_ACTIVATION_FAILED",
		"Could not complete database %s for '%s'." % [operation, database_name],
	)


func _recovery_error(result: GDSQLOperationResult) -> GDSQLOperationResult:
	return _error(
		result,
		&"GDSQL_DATABASE_LIFECYCLE_RECOVERY_FAILED",
		"Could not recover an interrupted database lifecycle operation.",
	)


func _error(
		result: GDSQLOperationResult,
		code: StringName,
		message: String,
) -> GDSQLOperationResult:
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
