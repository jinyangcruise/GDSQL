class_name GDSQLConfigFileTableLifecycleTransaction
extends RefCounted
## Moves or removes table file pairs through explicit recoverable commit states.

const BUILDING_SUFFIX := ".building"
const PREVIOUS_SUFFIX := ".previous"
const DROPPING_SUFFIX := ".dropping"
const PREPARING_SUFFIX := ".preparing"
const COMMITTED_SUFFIX := ".committed"
const CONFIG_EXTENSION := ".cfg"
const TRANSACTION_SECTION := "transaction"
const RENAME_TABLE_KIND := "rename_table"
const DROP_TABLE_KIND := "drop_table"

var _path_resolver: GDSQLDatabasePathResolver


func _init(path_resolver: GDSQLDatabasePathResolver) -> void:
	assert(path_resolver != null)
	_path_resolver = path_resolver


func rename_table(
		database_name: StringName,
		current_name: StringName,
		new_name: StringName,
		new_schema: ConfigFile,
) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if not _is_valid_identity(database_name, current_name) \
			or not _is_valid_identity(database_name, new_name) \
			or current_name == new_name or new_schema == null:
		return _error(
			result,
			&"GDSQL_CATALOG_LIFECYCLE_INVALID",
			"Catalog rename requires distinct valid table identities and a schema.",
		)
	var recovered := recover_database(database_name)
	result.diagnostics.merge(recovered.diagnostics)
	if not recovered.is_successful():
		return result
	var old_paths := _paths(database_name, current_name)
	var new_paths := _paths(database_name, new_name)
	if not _has_complete_pair(old_paths) or _has_any_active_path(new_paths):
		return _error(
			result,
			&"GDSQL_CATALOG_RENAME_STATE_INVALID",
			"Table rename requires one complete source pair and an empty target.",
		)
	var staged_schema := new_paths[0] + BUILDING_SUFFIX
	if new_schema.save(staged_schema) != OK:
		_remove_file(staged_schema)
		return _error(
			result,
			&"GDSQL_CATALOG_LIFECYCLE_STAGE_FAILED",
			"Could not stage renamed table schema '%s'." % new_paths[0],
		)
	var marker := _create_marker(
		database_name,
		RENAME_TABLE_KIND,
		current_name,
		new_name,
	)
	result.diagnostics.merge(marker.diagnostics)
	if not marker.is_successful():
		_remove_file(staged_schema)
		return result
	var preparing_path := String(marker.value)
	if _rename(old_paths[1], new_paths[1]) != OK \
			or _rename(old_paths[0], old_paths[0] + PREVIOUS_SUFFIX) != OK \
			or _rename(staged_schema, new_paths[0]) != OK:
		_recover_rename(preparing_path, false)
		return _activation_error(result, database_name, current_name, "rename")
	var committed_path := preparing_path.trim_suffix(PREPARING_SUFFIX) + COMMITTED_SUFFIX
	if _rename(preparing_path, committed_path) != OK:
		_recover_rename(preparing_path, false)
		return _activation_error(result, database_name, current_name, "rename")
	_cleanup_rename(committed_path, old_paths, result)
	result.value = true
	return result


func drop_table(
		database_name: StringName,
		table_name: StringName,
) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if not _is_valid_identity(database_name, table_name):
		return _error(
			result,
			&"GDSQL_CATALOG_LIFECYCLE_INVALID",
			"Catalog removal requires a valid table identity.",
		)
	var recovered := recover_database(database_name)
	result.diagnostics.merge(recovered.diagnostics)
	if not recovered.is_successful():
		return result
	var paths := _paths(database_name, table_name)
	if not _has_complete_pair(paths):
		return _error(
			result,
			&"GDSQL_CATALOG_DROP_STATE_INVALID",
			"Table removal requires a complete schema/storage pair.",
		)
	var marker := _create_marker(
		database_name,
		DROP_TABLE_KIND,
		table_name,
		&"",
	)
	result.diagnostics.merge(marker.diagnostics)
	if not marker.is_successful():
		return result
	var preparing_path := String(marker.value)
	if _rename(paths[1], paths[1] + DROPPING_SUFFIX) != OK \
			or _rename(paths[0], paths[0] + DROPPING_SUFFIX) != OK:
		_recover_drop(preparing_path, false)
		return _activation_error(result, database_name, table_name, "drop")
	var committed_path := preparing_path.trim_suffix(PREPARING_SUFFIX) + COMMITTED_SUFFIX
	if _rename(preparing_path, committed_path) != OK:
		_recover_drop(preparing_path, false)
		return _activation_error(result, database_name, table_name, "drop")
	_cleanup_drop(committed_path, paths, result)
	result.value = true
	return result


func recover_database(database_name: StringName) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if not _path_resolver.is_valid_name(database_name):
		return _error(
			result,
			&"GDSQL_CATALOG_LIFECYCLE_INVALID",
			"Catalog lifecycle recovery requires a valid database identifier.",
		)
	var root := _path_resolver.resolve_catalog_transaction_root(database_name)
	var directory := DirAccess.open(root)
	if directory == null:
		if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(root)):
			return _recovery_error(result, database_name)
		result.value = 0
		return result
	var recovered_count := 0
	var files := directory.get_files()
	files.sort()
	for file_name in files:
		var marker_path := root.path_join(file_name)
		if file_name.ends_with(PREPARING_SUFFIX + BUILDING_SUFFIX):
			if _remove_file(marker_path) != OK:
				return _recovery_error(result, database_name)
			continue
		if not file_name.ends_with(PREPARING_SUFFIX) \
				and not file_name.ends_with(COMMITTED_SUFFIX):
			continue
		var committed := file_name.ends_with(COMMITTED_SUFFIX)
		var marker := ConfigFile.new()
		if marker.load(marker_path) != OK \
				or StringName(marker.get_value(TRANSACTION_SECTION, "database", "")) != database_name:
			return _recovery_error(result, database_name)
		var recovery_error := ERR_INVALID_DATA
		match String(marker.get_value(TRANSACTION_SECTION, "kind", "")):
			RENAME_TABLE_KIND:
				recovery_error = _recover_rename(marker_path, committed)
			DROP_TABLE_KIND:
				recovery_error = _recover_drop(marker_path, committed)
		if recovery_error != OK:
			return _recovery_error(result, database_name)
		recovered_count += 1
	result.value = recovered_count
	return result


func _recover_rename(marker_path: String, committed: bool) -> Error:
	var marker := ConfigFile.new()
	if marker.load(marker_path) != OK:
		return ERR_FILE_CORRUPT
	var database_name := StringName(
		marker.get_value(TRANSACTION_SECTION, "database", ""),
	)
	var current_name := StringName(
		marker.get_value(TRANSACTION_SECTION, "source", ""),
	)
	var new_name := StringName(
		marker.get_value(TRANSACTION_SECTION, "target", ""),
	)
	if not _is_valid_identity(database_name, current_name) \
			or not _is_valid_identity(database_name, new_name):
		return ERR_INVALID_DATA
	var old_paths := _paths(database_name, current_name)
	var new_paths := _paths(database_name, new_name)
	if committed:
		if not _has_complete_pair(new_paths):
			return ERR_FILE_CORRUPT
		for path in old_paths:
			if _remove_file(path) != OK \
					or _remove_file(path + PREVIOUS_SUFFIX) != OK:
				return ERR_CANT_CREATE
		if _remove_file(new_paths[0] + BUILDING_SUFFIX) != OK:
			return ERR_CANT_CREATE
		return _remove_file(marker_path)
	if _remove_file(new_paths[0]) != OK \
			or _remove_file(new_paths[0] + BUILDING_SUFFIX) != OK:
		return ERR_CANT_CREATE
	if FileAccess.file_exists(old_paths[0] + PREVIOUS_SUFFIX):
		if _remove_file(old_paths[0]) != OK \
				or _rename(old_paths[0] + PREVIOUS_SUFFIX, old_paths[0]) != OK:
			return ERR_CANT_CREATE
	if FileAccess.file_exists(new_paths[1]):
		if FileAccess.file_exists(old_paths[1]) \
				or _rename(new_paths[1], old_paths[1]) != OK:
			return ERR_CANT_CREATE
	if not _has_complete_pair(old_paths) or _has_any_active_path(new_paths):
		return ERR_FILE_CORRUPT
	return _remove_file(marker_path)


func _recover_drop(marker_path: String, committed: bool) -> Error:
	var marker := ConfigFile.new()
	if marker.load(marker_path) != OK:
		return ERR_FILE_CORRUPT
	var database_name := StringName(
		marker.get_value(TRANSACTION_SECTION, "database", ""),
	)
	var table_name := StringName(
		marker.get_value(TRANSACTION_SECTION, "source", ""),
	)
	if not _is_valid_identity(database_name, table_name):
		return ERR_INVALID_DATA
	var paths := _paths(database_name, table_name)
	if committed:
		for path in paths:
			if _remove_file(path) != OK \
					or _remove_file(path + DROPPING_SUFFIX) != OK:
				return ERR_CANT_CREATE
		return _remove_file(marker_path)
	for path in paths:
		var dropping_path := path + DROPPING_SUFFIX
		if not FileAccess.file_exists(dropping_path):
			continue
		if FileAccess.file_exists(path) or _rename(dropping_path, path) != OK:
			return ERR_CANT_CREATE
	if not _has_complete_pair(paths):
		return ERR_FILE_CORRUPT
	return _remove_file(marker_path)


func _create_marker(
		database_name: StringName,
		kind: String,
		source: StringName,
		target: StringName,
) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	var root := _path_resolver.resolve_catalog_transaction_root(database_name)
	if DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(root),
	) != OK:
		return _error(
			result,
			&"GDSQL_CATALOG_LIFECYCLE_DIRECTORY_FAILED",
			"Could not create catalog transaction directory '%s'." % root,
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
	marker.set_value(TRANSACTION_SECTION, "database", String(database_name))
	marker.set_value(TRANSACTION_SECTION, "source", String(source))
	marker.set_value(TRANSACTION_SECTION, "target", String(target))
	if marker.save(building_path) != OK \
			or _rename(building_path, preparing_path) != OK:
		_remove_file(building_path)
		return _error(
			result,
			&"GDSQL_CATALOG_LIFECYCLE_MARKER_FAILED",
			"Could not persist catalog lifecycle intent for '%s.%s'." \
					% [database_name, source],
		)
	result.value = preparing_path
	return result


func _cleanup_rename(
		marker_path: String,
		old_paths: PackedStringArray,
		result: GDSQLOperationResult,
) -> void:
	if _remove_file(old_paths[0] + PREVIOUS_SUFFIX) == OK \
			and _remove_file(marker_path) == OK:
		return
	_add_cleanup_warning(result, "renamed table")


func _cleanup_drop(
		marker_path: String,
		paths: PackedStringArray,
		result: GDSQLOperationResult,
) -> void:
	for path in paths:
		if _remove_file(path + DROPPING_SUFFIX) != OK:
			_add_cleanup_warning(result, "removed table")
			return
	if _remove_file(marker_path) != OK:
		_add_cleanup_warning(result, "removed table")


func _add_cleanup_warning(
		result: GDSQLOperationResult,
		operation: String,
) -> void:
	result.add_diagnostic(
		GDSQLQueryDiagnostic.new(
			&"GDSQL_CATALOG_LIFECYCLE_CLEANUP_PENDING",
			"Catalog operation completed, but recovery artifacts for the %s remain." \
					% operation,
			GDSQLQueryDiagnostic.Severity.WARNING,
		),
	)


func _paths(
		database_name: StringName,
		table_name: StringName,
) -> PackedStringArray:
	return PackedStringArray(
		[
			_path_resolver.resolve_schema_path(database_name, table_name),
			_path_resolver.resolve_table_path(database_name, table_name),
		],
	)


func _has_complete_pair(paths: PackedStringArray) -> bool:
	return paths.size() == 2 \
			and FileAccess.file_exists(paths[0]) \
			and FileAccess.file_exists(paths[1])


func _has_any_active_path(paths: PackedStringArray) -> bool:
	for path in paths:
		if FileAccess.file_exists(path):
			return true
	return false


func _remove_file(path: String) -> Error:
	if not FileAccess.file_exists(path):
		return OK
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _rename(source: String, destination: String) -> Error:
	return DirAccess.rename_absolute(
		ProjectSettings.globalize_path(source),
		ProjectSettings.globalize_path(destination),
	)


func _is_valid_identity(
		database_name: StringName,
		table_name: StringName,
) -> bool:
	return _path_resolver.is_valid_name(database_name) \
			and _path_resolver.is_valid_name(table_name)


func _activation_error(
		result: GDSQLOperationResult,
		database_name: StringName,
		table_name: StringName,
		operation: String,
) -> GDSQLOperationResult:
	return _error(
		result,
		&"GDSQL_CATALOG_LIFECYCLE_ACTIVATION_FAILED",
		"Could not complete catalog %s for '%s.%s'." \
				% [operation, database_name, table_name],
	)


func _recovery_error(
		result: GDSQLOperationResult,
		database_name: StringName,
) -> GDSQLOperationResult:
	return _error(
		result,
		&"GDSQL_CATALOG_LIFECYCLE_RECOVERY_FAILED",
		"Could not recover an interrupted table lifecycle operation for '%s'." \
				% database_name,
	)


func _error(
		result: GDSQLOperationResult,
		code: StringName,
		message: String,
) -> GDSQLOperationResult:
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
