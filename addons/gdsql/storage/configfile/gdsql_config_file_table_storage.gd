class_name GDSQLConfigFileTableStorage
extends GDSQLTableStorage

var path_resolver: GDSQLDatabasePathResolver
var config_cache: GDSQLConfigFileCache
var codec: GDSQLGodotVariantCodec


func _init(
		path_resolver: GDSQLDatabasePathResolver,
		config_cache: GDSQLConfigFileCache,
		codec: GDSQLGodotVariantCodec,
) -> void:
	self.path_resolver = path_resolver
	self.config_cache = config_cache
	self.codec = codec


func read_table(table: GDSQLTableDefinition, session: GDSQLStorageSession) -> GDSQLTableSnapshot:
	var snapshot := GDSQLTableSnapshot.new()
	snapshot.primary_key = table.primary_key
	var path := path_resolver.resolve_table_path(table.database_name, table.name)
	var config := config_cache.get_or_load(path)
	if config == null:
		return snapshot
	for section in config.get_sections():
		var values: Dictionary = { }
		for key in config.get_section_keys(section):
			values[StringName(key)] = codec.decode(config.get_value(section, key))
		snapshot.rows.append(GDSQLRowRecord.new(values))
	return snapshot


func find_by_primary_key(
		table: GDSQLTableDefinition,
		key: Variant,
		session: GDSQLStorageSession,
) -> GDSQLRowRecord:
	return read_table(table, session).find_by_primary_key(key)


func stage_insert(
		table: GDSQLTableDefinition,
		row: GDSQLRowRecord,
		session: GDSQLStorageSession,
) -> GDSQLStorageOperationResult:
	var result := GDSQLStorageOperationResult.new()
	if table.primary_key == &"" or not row.has_column(table.primary_key):
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_STORAGE_PRIMARY_KEY_REQUIRED",
				"Insert requires the table primary key.",
			),
		)
		return result
	var key: Variant = row.get_value(table.primary_key)
	if find_by_primary_key(table, key, session) != null or _has_staged_key(session, table, key):
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_STORAGE_DUPLICATE_PRIMARY_KEY",
				"Primary key '%s' already exists in %s.%s." % [key, table.database_name, table.name],
			),
		)
		return result
	session.operations.append({ "type": &"insert", "table": table, "row": row.duplicate_record() })
	session.dirty = true
	result.value = row
	return result


func stage_update(table: GDSQLTableDefinition, key: Variant, row: GDSQLRowRecord, session: GDSQLStorageSession) -> GDSQLStorageOperationResult:
	var result := GDSQLStorageOperationResult.new()
	if find_by_primary_key(table, key, session) == null:
		return _missing_row_result(table, key, &"update")
	if not row.has_column(table.primary_key) or row.get_value(table.primary_key) != key:
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_STORAGE_PRIMARY_KEY_UPDATE_FORBIDDEN",
				"An update cannot remove or change the table primary key.",
			),
		)
		return result
	session.operations.append(
		{ "type": &"update", "table": table, "key": key, "row": row.duplicate_record() },
	)
	session.dirty = true
	result.value = row
	return result


func stage_delete(table: GDSQLTableDefinition, key: Variant, session: GDSQLStorageSession) -> GDSQLStorageOperationResult:
	if find_by_primary_key(table, key, session) == null:
		return _missing_row_result(table, key, &"delete")
	var result := GDSQLStorageOperationResult.new()
	session.operations.append({ "type": &"delete", "table": table, "key": key })
	session.dirty = true
	result.value = true
	return result


func commit(session: GDSQLStorageSession) -> GDSQLStorageCommitResult:
	var result := GDSQLStorageCommitResult.new()
	var touched_paths: Dictionary = { }
	for operation in session.operations:
		var table := operation["table"] as GDSQLTableDefinition
		var path := path_resolver.resolve_table_path(table.database_name, table.name)
		var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		if directory_error != OK:
			return _commit_error(&"GDSQL_STORAGE_DIRECTORY_UNWRITABLE", "Could not create table directory: %s" % path.get_base_dir())
		var config := config_cache.get_or_load(path)
		if config == null:
			return _commit_error(&"GDSQL_STORAGE_TABLE_UNREADABLE", "Could not load table file: %s" % path)
		var operation_type := operation["type"] as StringName
		if operation_type == &"delete":
			config.erase_section(str(operation["key"]))
		else:
			var row := operation["row"] as GDSQLRowRecord
			var section := str(row.get_value(table.primary_key))
			if operation_type == &"update":
				config.erase_section(section)
			for column: Variant in row.values.keys():
				config.set_value(section, String(column), codec.encode(row.values[column]))
		touched_paths[path] = true
	for path: String in touched_paths:
		var save_error := config_cache.flush(path)
		if save_error != OK:
			return _commit_error(&"GDSQL_STORAGE_COMMIT_FAILED", "Could not save table file: %s" % path)
	session.clear()
	result.value = true
	return result


func rollback(session: GDSQLStorageSession) -> void:
	session.clear()


func _has_staged_key(session: GDSQLStorageSession, table: GDSQLTableDefinition, key: Variant) -> bool:
	for operation in session.operations:
		if operation["type"] == &"insert" and operation["table"] == table:
			var row := operation["row"] as GDSQLRowRecord
			if row.get_value(table.primary_key) == key:
				return true
	return false


func _missing_row_result(
		table: GDSQLTableDefinition,
		key: Variant,
		operation: StringName,
) -> GDSQLStorageOperationResult:
	var result := GDSQLStorageOperationResult.new()
	result.add_diagnostic(
		GDSQLQueryDiagnostic.new(
			&"GDSQL_STORAGE_ROW_NOT_FOUND",
			"Cannot %s missing primary key '%s' in %s.%s." % [operation, key, table.database_name, table.name],
		),
	)
	return result


func _commit_error(code: StringName, message: String) -> GDSQLStorageCommitResult:
	var result := GDSQLStorageCommitResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
