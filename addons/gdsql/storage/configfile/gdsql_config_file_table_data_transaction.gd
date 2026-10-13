class_name GDSQLConfigFileTableDataTransaction
extends RefCounted
## Activates complete replacement table files behind one recoverable commit
## marker. A preparing marker rolls every touched table back; a committed marker
## keeps every replacement and only finishes cleanup.

const FORMAT_VERSION := 1
const TRANSACTION_SECTION := "transaction"
const MARKER_FILE := "table_data_commit.cfg"
const BUILDING_SUFFIX := ".gdsql-row-building"
const PREVIOUS_SUFFIX := ".gdsql-row-previous"
const PREPARING_SUFFIX := ".preparing"
const COMMITTED_SUFFIX := ".committed"

var _path_resolver: GDSQLDatabasePathResolver
var _cache: GDSQLConfigFileCache


func _init(
		path_resolver: GDSQLDatabasePathResolver,
		cache: GDSQLConfigFileCache = null,
) -> void:
	assert(path_resolver != null)
	_path_resolver = path_resolver
	_cache = cache


func replace_tables(
		database_name: StringName,
		replacements: Dictionary,
) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if not _path_resolver.is_valid_name(database_name) or replacements.is_empty():
		return _error(
			result,
			&"GDSQL_STORAGE_TRANSACTION_INVALID",
			"Table-data replacement requires one database and at least one table.",
		)
	var recovered := recover_database(database_name)
	result.diagnostics.merge(recovered.diagnostics)
	if not recovered.is_successful():
		return result
	var table_names := _sorted_table_names(replacements)
	if table_names.is_empty():
		return _error(
			result,
			&"GDSQL_STORAGE_TRANSACTION_INVALID",
			"Table-data replacement contains an invalid table identity or value.",
		)
	var root := _path_resolver.resolve_table_data_transaction_root(database_name)
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root)) != OK:
		return _error(
			result,
			&"GDSQL_STORAGE_TRANSACTION_DIRECTORY_FAILED",
			"Could not create the table-data transaction directory for '%s'." % database_name,
		)
	for table_name in table_names:
		var active_path := _path_resolver.resolve_table_path(database_name, table_name)
		if not FileAccess.file_exists(active_path):
			_cleanup_staging(database_name, table_names)
			return _error(
				result,
				&"GDSQL_STORAGE_TRANSACTION_TABLE_MISSING",
				"Table storage '%s' does not exist." % active_path,
			)
		var staged_path := active_path + BUILDING_SUFFIX
		var replacement := replacements[table_name] as ConfigFile
		if replacement == null or replacement.save(staged_path) != OK \
				or not _is_readable_config(staged_path):
			_cleanup_staging(database_name, table_names)
			return _error(
				result,
				&"GDSQL_STORAGE_TRANSACTION_STAGE_FAILED",
				"Could not stage and verify table storage '%s'." % active_path,
			)
	var marker_result := _create_preparing_marker(database_name, table_names)
	result.diagnostics.merge(marker_result.diagnostics)
	if not marker_result.is_successful():
		_cleanup_staging(database_name, table_names)
		return result
	var preparing_path := String(marker_result.value)
	for table_name in table_names:
		var active_path := _path_resolver.resolve_table_path(database_name, table_name)
		if _rename(active_path, active_path + PREVIOUS_SUFFIX) != OK:
			_merge_failed_recovery(result, preparing_path, database_name)
			return _activation_error(result, database_name)
	for table_name in table_names:
		var active_path := _path_resolver.resolve_table_path(database_name, table_name)
		if _rename(active_path + BUILDING_SUFFIX, active_path) != OK:
			_merge_failed_recovery(result, preparing_path, database_name)
			return _activation_error(result, database_name)
	var committed_path := _marker_path(database_name, true)
	if _rename(preparing_path, committed_path) != OK:
		_merge_failed_recovery(result, preparing_path, database_name)
		return _activation_error(result, database_name)
	_invalidate(database_name, table_names)
	_cleanup_committed(committed_path, database_name, table_names, result)
	result.value = true
	return result


func recover_database(database_name: StringName) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if not _path_resolver.is_valid_name(database_name):
		return _error(
			result,
			&"GDSQL_STORAGE_TRANSACTION_INVALID",
			"Table-data recovery requires a valid database identifier.",
		)
	var preparing_path := _marker_path(database_name, false)
	var committed_path := _marker_path(database_name, true)
	if FileAccess.file_exists(preparing_path) and FileAccess.file_exists(committed_path):
		return _recovery_error(result, database_name)
	var marker_path := preparing_path if FileAccess.file_exists(preparing_path) else committed_path
	if marker_path.is_empty() or not FileAccess.file_exists(marker_path):
		var orphan_result := _remove_orphan_staging(database_name)
		result.diagnostics.merge(orphan_result.diagnostics)
		if orphan_result.is_successful():
			result.value = false
		return result
	var recovered := _recover_marker(marker_path, marker_path == committed_path)
	if recovered != OK:
		return _recovery_error(result, database_name)
	result.value = true
	return result


func _recover_marker(marker_path: String, committed: bool) -> Error:
	var marker := ConfigFile.new()
	if marker.load(marker_path) != OK:
		return ERR_FILE_CORRUPT
	var database_name := StringName(
		marker.get_value(TRANSACTION_SECTION, "database", ""),
	)
	if not _path_resolver.is_valid_name(database_name) \
			or int(marker.get_value(TRANSACTION_SECTION, "format", 0)) != FORMAT_VERSION:
		return ERR_INVALID_DATA
	var table_names := _decode_table_names(
		marker.get_value(TRANSACTION_SECTION, "tables", PackedStringArray()),
	)
	if table_names.is_empty():
		return ERR_INVALID_DATA
	if committed:
		for table_name in table_names:
			var active_path := _path_resolver.resolve_table_path(database_name, table_name)
			if not FileAccess.file_exists(active_path):
				return ERR_FILE_CORRUPT
			if _remove_file(active_path + BUILDING_SUFFIX) != OK \
					or _remove_file(active_path + PREVIOUS_SUFFIX) != OK:
				return ERR_CANT_CREATE
	else:
		for table_name in table_names:
			var active_path := _path_resolver.resolve_table_path(database_name, table_name)
			var previous_path := active_path + PREVIOUS_SUFFIX
			if FileAccess.file_exists(previous_path):
				if _remove_file(active_path) != OK \
						or _rename(previous_path, active_path) != OK:
					return ERR_CANT_CREATE
			if _remove_file(active_path + BUILDING_SUFFIX) != OK \
					or not FileAccess.file_exists(active_path):
				return ERR_FILE_CORRUPT
	_invalidate(database_name, table_names)
	return _remove_file(marker_path)


func _create_preparing_marker(
		database_name: StringName,
		table_names: Array[StringName],
) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	var preparing_path := _marker_path(database_name, false)
	var building_path := preparing_path + BUILDING_SUFFIX
	var marker := ConfigFile.new()
	marker.set_value(TRANSACTION_SECTION, "format", FORMAT_VERSION)
	marker.set_value(TRANSACTION_SECTION, "database", String(database_name))
	marker.set_value(TRANSACTION_SECTION, "tables", PackedStringArray(table_names))
	if marker.save(building_path) != OK or not _is_readable_config(building_path) \
			or _rename(building_path, preparing_path) != OK:
		_remove_file(building_path)
		return _error(
			result,
			&"GDSQL_STORAGE_TRANSACTION_MARKER_FAILED",
			"Could not persist table-data commit intent for '%s'." % database_name,
		)
	result.value = preparing_path
	return result


func _cleanup_committed(
		marker_path: String,
		database_name: StringName,
		table_names: Array[StringName],
		result: GDSQLOperationResult,
) -> void:
	for table_name in table_names:
		var active_path := _path_resolver.resolve_table_path(database_name, table_name)
		if _remove_file(active_path + PREVIOUS_SUFFIX) != OK \
				or _remove_file(active_path + BUILDING_SUFFIX) != OK:
			_add_cleanup_warning(result)
			return
	if _remove_file(marker_path) != OK:
		_add_cleanup_warning(result)


func _cleanup_staging(
		database_name: StringName,
		table_names: Array[StringName],
) -> void:
	for table_name in table_names:
		var active_path := _path_resolver.resolve_table_path(database_name, table_name)
		_remove_file(active_path + BUILDING_SUFFIX)


func _remove_orphan_staging(database_name: StringName) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if _remove_file(_marker_path(database_name, false) + BUILDING_SUFFIX) != OK:
		return _recovery_error(result, database_name)
	var tables_path := _path_resolver.resolve_database_path(database_name).path_join("tables")
	var directory := DirAccess.open(tables_path)
	if directory == null:
		result.value = true
		return result
	for file_name in directory.get_files():
		var path := tables_path.path_join(file_name)
		if file_name.ends_with(BUILDING_SUFFIX):
			if _remove_file(path) != OK:
				return _recovery_error(result, database_name)
		elif file_name.ends_with(PREVIOUS_SUFFIX):
			return _recovery_error(result, database_name)
	result.value = true
	return result


func _sorted_table_names(replacements: Dictionary) -> Array[StringName]:
	var names: Array[StringName] = []
	for key in replacements:
		var name := StringName(key)
		if not _path_resolver.is_valid_name(name) or not replacements[key] is ConfigFile:
			return []
		names.append(name)
	names.sort()
	return names


func _decode_table_names(value: Variant) -> Array[StringName]:
	var names: Array[StringName] = []
	if not value is PackedStringArray and not value is Array:
		return names
	for entry in value:
		var name := StringName(entry)
		if not _path_resolver.is_valid_name(name) or names.has(name):
			return []
		names.append(name)
	names.sort()
	return names


func _marker_path(database_name: StringName, committed: bool) -> String:
	return _path_resolver.resolve_table_data_transaction_root(database_name).path_join(
		MARKER_FILE + (COMMITTED_SUFFIX if committed else PREPARING_SUFFIX),
	)


func _is_readable_config(path: String) -> bool:
	return ConfigFile.new().load(path) == OK


func _invalidate(
		database_name: StringName,
		table_names: Array[StringName],
) -> void:
	if _cache == null:
		return
	for table_name in table_names:
		_cache.invalidate(_path_resolver.resolve_table_path(database_name, table_name))


func _rename(source: String, destination: String) -> Error:
	return DirAccess.rename_absolute(
		ProjectSettings.globalize_path(source),
		ProjectSettings.globalize_path(destination),
	)


func _remove_file(path: String) -> Error:
	if not FileAccess.file_exists(path):
		return OK
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _add_cleanup_warning(result: GDSQLOperationResult) -> void:
	result.add_diagnostic(
		GDSQLQueryDiagnostic.new(
			&"GDSQL_STORAGE_TRANSACTION_CLEANUP_PENDING",
			"Table-data commit succeeded, but recovery artifacts require cleanup.",
			GDSQLQueryDiagnostic.Severity.WARNING,
		),
	)


func _merge_failed_recovery(
		result: GDSQLOperationResult,
		marker_path: String,
		database_name: StringName,
) -> void:
	if _recover_marker(marker_path, false) == OK:
		return
	result.add_diagnostic(
		GDSQLQueryDiagnostic.new(
			&"GDSQL_STORAGE_TRANSACTION_RECOVERY_FAILED",
			"Activation failed and the previous table set for '%s' could not be restored." \
					% database_name,
		),
	)


func _activation_error(
		result: GDSQLOperationResult,
		database_name: StringName,
) -> GDSQLOperationResult:
	return _error(
		result,
		&"GDSQL_STORAGE_TRANSACTION_ACTIVATION_FAILED",
		"Could not atomically activate table data for '%s'." % database_name,
	)


func _recovery_error(
		result: GDSQLOperationResult,
		database_name: StringName,
) -> GDSQLOperationResult:
	return _error(
		result,
		&"GDSQL_STORAGE_TRANSACTION_RECOVERY_FAILED",
		"Could not recover interrupted table data for '%s'." % database_name,
	)


func _error(
		result: GDSQLOperationResult,
		code: StringName,
		message: String,
) -> GDSQLOperationResult:
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
