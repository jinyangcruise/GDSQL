class_name GDSQLConfigFileCatalogTransaction
extends RefCounted
## Activates one table's schema and row files as a recoverable pair.

const BUILDING_SUFFIX := ".building"
const PREVIOUS_SUFFIX := ".previous"
const CONFIG_EXTENSION := ".cfg"

var _path_resolver: GDSQLDatabasePathResolver


func _init(path_resolver: GDSQLDatabasePathResolver) -> void:
	assert(path_resolver != null)
	_path_resolver = path_resolver


func replace_table(
		database_name: StringName,
		table_name: StringName,
		schema: ConfigFile,
		table_data: ConfigFile,
) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if not _is_valid_identity(database_name, table_name) \
			or schema == null or table_data == null:
		return _error(
			result,
			&"GDSQL_CATALOG_TRANSACTION_INVALID",
			"Catalog replacement requires valid table identity and ConfigFile values.",
		)
	var recovered := recover_table(database_name, table_name)
	result.diagnostics.merge(recovered.diagnostics)
	if not recovered.is_successful():
		return result
	var paths := _paths(database_name, table_name)
	var schema_path := paths[0]
	var table_path := paths[1]
	var schema_exists := FileAccess.file_exists(schema_path)
	var table_exists := FileAccess.file_exists(table_path)
	if schema_exists != table_exists:
		return _error(
			result,
			&"GDSQL_CATALOG_FILE_PAIR_INCOMPLETE",
			"Table '%s.%s' does not have a complete schema/storage pair." \
					% [database_name, table_name],
		)
	var schema_building := schema_path + BUILDING_SUFFIX
	var table_building := table_path + BUILDING_SUFFIX
	if table_data.save(table_building) != OK:
		_remove_file(table_building)
		return _error(
			result,
			&"GDSQL_CATALOG_TRANSACTION_STAGE_FAILED",
			"Could not stage table storage '%s'." % table_path,
		)
	if schema.save(schema_building) != OK:
		_remove_file(table_building)
		_remove_file(schema_building)
		return _error(
			result,
			&"GDSQL_CATALOG_TRANSACTION_STAGE_FAILED",
			"Could not stage table schema '%s'." % schema_path,
		)
	if table_exists:
		if _rename(table_path, table_path + PREVIOUS_SUFFIX) != OK:
			_recover_paths(paths)
			return _activation_error(result, database_name, table_name)
		if _rename(schema_path, schema_path + PREVIOUS_SUFFIX) != OK:
			_recover_paths(paths)
			return _activation_error(result, database_name, table_name)
	if _rename(table_building, table_path) != OK:
		_recover_paths(paths)
		return _activation_error(result, database_name, table_name)
	if _rename(schema_building, schema_path) != OK:
		_recover_paths(paths)
		return _activation_error(result, database_name, table_name)
	_cleanup_previous(paths, result)
	result.value = true
	return result


func recover_database(database_name: StringName) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if not _path_resolver.is_valid_name(database_name):
		return _error(
			result,
			&"GDSQL_CATALOG_TRANSACTION_INVALID",
			"Catalog recovery requires a valid database identifier.",
		)
	var table_names: Dictionary[StringName, bool] = { }
	_collect_table_names(
		_path_resolver.resolve_catalog_path(database_name),
		table_names,
	)
	_collect_table_names(
		_path_resolver.resolve_database_path(database_name).path_join("tables"),
		table_names,
	)
	for table_name in table_names:
		var recovered := recover_table(database_name, table_name)
		result.diagnostics.merge(recovered.diagnostics)
		if not recovered.is_successful():
			return result
	result.value = table_names.size()
	return result


func recover_table(
		database_name: StringName,
		table_name: StringName,
) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if not _is_valid_identity(database_name, table_name):
		return _error(
			result,
			&"GDSQL_CATALOG_TRANSACTION_INVALID",
			"Catalog recovery requires valid database and table identifiers.",
		)
	var recovered := _recover_paths(_paths(database_name, table_name))
	if recovered != OK:
		return _error(
			result,
			&"GDSQL_CATALOG_TRANSACTION_RECOVERY_FAILED",
			"Could not recover interrupted catalog files for '%s.%s'." \
					% [database_name, table_name],
		)
	result.value = true
	return result


func _recover_paths(paths: PackedStringArray) -> Error:
	var has_building := false
	var has_previous := false
	var active_count := 0
	for path in paths:
		has_building = has_building or FileAccess.file_exists(path + BUILDING_SUFFIX)
		has_previous = has_previous or FileAccess.file_exists(path + PREVIOUS_SUFFIX)
		active_count += 1 if FileAccess.file_exists(path) else 0
	if not has_building and not has_previous:
		return OK
	if has_building:
		if has_previous:
			for path in paths:
				var previous := path + PREVIOUS_SUFFIX
				if not FileAccess.file_exists(previous):
					continue
				if _remove_file(path) != OK or _rename(previous, path) != OK:
					return ERR_CANT_CREATE
		elif active_count != paths.size():
			for path in paths:
				if _remove_file(path) != OK:
					return ERR_CANT_CREATE
		for path in paths:
			if _remove_file(path + BUILDING_SUFFIX) != OK:
				return ERR_CANT_CREATE
		return OK
	if active_count == paths.size():
		for path in paths:
			if _remove_file(path + PREVIOUS_SUFFIX) != OK:
				return ERR_CANT_CREATE
		return OK
	for path in paths:
		var previous := path + PREVIOUS_SUFFIX
		if not FileAccess.file_exists(previous):
			continue
		if _remove_file(path) != OK or _rename(previous, path) != OK:
			return ERR_CANT_CREATE
	for path in paths:
		if not FileAccess.file_exists(path):
			return ERR_FILE_CORRUPT
	return OK


func _cleanup_previous(
		paths: PackedStringArray,
		result: GDSQLOperationResult,
) -> void:
	for path in paths:
		if _remove_file(path + PREVIOUS_SUFFIX) == OK:
			continue
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_CATALOG_TRANSACTION_CLEANUP_PENDING",
				"Catalog replacement succeeded, but previous files require cleanup.",
				GDSQLQueryDiagnostic.Severity.WARNING,
			),
		)
		return


func _collect_table_names(
		directory_path: String,
		table_names: Dictionary[StringName, bool],
) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return
	for file_name in directory.get_files():
		var normalized := file_name
		if normalized.ends_with(BUILDING_SUFFIX):
			normalized = normalized.trim_suffix(BUILDING_SUFFIX)
		elif normalized.ends_with(PREVIOUS_SUFFIX):
			normalized = normalized.trim_suffix(PREVIOUS_SUFFIX)
		if not normalized.ends_with(CONFIG_EXTENSION):
			continue
		var table_name := StringName(normalized.trim_suffix(CONFIG_EXTENSION))
		if _path_resolver.is_valid_name(table_name):
			table_names[table_name] = true


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
) -> GDSQLOperationResult:
	return _error(
		result,
		&"GDSQL_CATALOG_TRANSACTION_ACTIVATION_FAILED",
		"Could not activate catalog files for '%s.%s'." \
				% [database_name, table_name],
	)


func _error(
		result: GDSQLOperationResult,
		code: StringName,
		message: String,
) -> GDSQLOperationResult:
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
