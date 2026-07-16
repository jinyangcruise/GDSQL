class_name GDSQLConfigFileTableStorage
extends GDSQLTableStorage

const TABLE_METADATA_SECTION := "__gdsql_metadata__"

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
		if section == TABLE_METADATA_SECTION:
			continue
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
	var primary_key := table.get_primary_key()
	if primary_key != null and primary_key.auto_increment \
			and not row.has_column(table.primary_key):
		var metadata := _get_session_table_metadata(table, session)
		row.set_value(table.primary_key, metadata["next_auto_increment"])
		metadata["next_auto_increment"] = int(metadata["next_auto_increment"]) + 1
	if table.primary_key == &"" or not row.has_column(table.primary_key):
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_STORAGE_PRIMARY_KEY_REQUIRED",
				"Insert requires the table primary key.",
			),
		)
		return result
	var key: Variant = row.get_value(table.primary_key)
	if str(key) == TABLE_METADATA_SECTION:
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_STORAGE_RESERVED_PRIMARY_KEY",
				"Primary key value '%s' is reserved for table metadata." % key,
			),
		)
		return result
	if find_by_primary_key(table, key, session) != null or _has_staged_key(session, table, key):
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_STORAGE_DUPLICATE_PRIMARY_KEY",
				"Primary key '%s' already exists in %s.%s." % [key, table.database_name, table.name],
			),
		)
		return result
	var metadata := _get_session_table_metadata(table, session)
	metadata["row_count"] = int(metadata["row_count"]) + 1
	if primary_key != null and primary_key.auto_increment \
			and key is int and key >= int(metadata["next_auto_increment"]):
		metadata["next_auto_increment"] = key + 1
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
	var metadata := _get_session_table_metadata(table, session)
	metadata["row_count"] = maxi(0, int(metadata["row_count"]) - 1)
	session.operations.append({ "type": &"delete", "table": table, "key": key })
	session.dirty = true
	result.value = true
	return result


func commit(session: GDSQLStorageSession) -> GDSQLStorageCommitResult:
	var constraint_result := _validate_session_constraints(session)
	if not constraint_result.is_successful():
		return constraint_result
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
	for table_key in session.table_metadata:
		var metadata: Dictionary = session.table_metadata[table_key]
		var table := metadata["table"] as GDSQLTableDefinition
		var path := path_resolver.resolve_table_path(table.database_name, table.name)
		var config := config_cache.get_or_load(path)
		if config == null:
			return _commit_error(
				&"GDSQL_STORAGE_TABLE_UNREADABLE",
				"Could not load table file: %s" % path,
			)
		config.set_value(
			TABLE_METADATA_SECTION,
			"row_count",
			int(metadata["row_count"]),
		)
		config.set_value(
			TABLE_METADATA_SECTION,
			"next_auto_increment",
			int(metadata["next_auto_increment"]),
		)
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


func _validate_session_constraints(
		session: GDSQLStorageSession,
) -> GDSQLStorageCommitResult:
	var tables: Array[GDSQLTableDefinition] = []
	for operation in session.operations:
		var table := operation["table"] as GDSQLTableDefinition
		if not tables.has(table):
			tables.append(table)
	for table in tables:
		var rows := _build_effective_rows(table, session)
		var values_result := _validate_row_values(table, rows)
		if not values_result.is_successful():
			return values_result
		var primary_result := _validate_unique_column(
			table,
			table.primary_key,
			rows,
			true,
		)
		if not primary_result.is_successful():
			return primary_result
		for column in table.columns:
			if not column.unique or column.name == table.primary_key:
				continue
			var unique_result := _validate_unique_column(
				table,
				column.name,
				rows,
				false,
			)
			if not unique_result.is_successful():
				return unique_result
	var result := GDSQLStorageCommitResult.new()
	result.value = true
	return result


func _get_session_table_metadata(
		table: GDSQLTableDefinition,
		session: GDSQLStorageSession,
) -> Dictionary:
	var table_key := _table_key(table)
	if not session.table_metadata.has(table_key):
		var metadata := _load_table_metadata(table)
		metadata["table"] = table
		session.table_metadata[table_key] = metadata
	return session.table_metadata[table_key]


func _load_table_metadata(table: GDSQLTableDefinition) -> Dictionary:
	var path := path_resolver.resolve_table_path(table.database_name, table.name)
	var config := config_cache.get_or_load(path)
	if config == null:
		return {
			"row_count": 0,
			"next_auto_increment": 1,
		}
	if config.has_section(TABLE_METADATA_SECTION):
		return {
			"row_count": int(
				config.get_value(TABLE_METADATA_SECTION, "row_count", 0),
			),
			"next_auto_increment": int(
				config.get_value(
					TABLE_METADATA_SECTION,
					"next_auto_increment",
					1,
				),
			),
		}
	var row_count := 0
	var next_auto_increment := 1
	for section in config.get_sections():
		if section == TABLE_METADATA_SECTION:
			continue
		row_count += 1
		if config.has_section_key(section, String(table.primary_key)):
			var key: Variant = codec.decode(
				config.get_value(section, String(table.primary_key)),
			)
			if key is int:
				next_auto_increment = maxi(next_auto_increment, key + 1)
	return {
		"row_count": row_count,
		"next_auto_increment": next_auto_increment,
	}


func _table_key(table: GDSQLTableDefinition) -> String:
	return "%s.%s" % [table.database_name, table.name]


func _build_effective_rows(
		table: GDSQLTableDefinition,
		session: GDSQLStorageSession,
) -> Array[GDSQLRowRecord]:
	var rows_by_key: Dictionary = { }
	for row in read_table(table, session).rows:
		rows_by_key[row.get_value(table.primary_key)] = row
	for operation in session.operations:
		if operation["table"] != table:
			continue
		var key: Variant = operation["key"] \
				if operation.has("key") \
				else (operation["row"] as GDSQLRowRecord).get_value(table.primary_key)
		if operation["type"] == &"delete":
			rows_by_key.erase(key)
		else:
			rows_by_key[key] = (operation["row"] as GDSQLRowRecord).duplicate_record()
	var rows: Array[GDSQLRowRecord] = []
	for row in rows_by_key.values():
		rows.append(row)
	return rows


func _validate_row_values(
		table: GDSQLTableDefinition,
		rows: Array[GDSQLRowRecord],
) -> GDSQLStorageCommitResult:
	for row in rows:
		for column in table.columns:
			if not row.has_column(column.name):
				if column.nullable:
					continue
				return _commit_error(
					&"GDSQL_STORAGE_REQUIRED_COLUMN_MISSING",
					"Column '%s' is required in %s.%s." \
							% [column.name, table.database_name, table.name],
				)
			var value: Variant = row.get_value(column.name)
			if not column.accepts_value(value):
				var expected := "Resource" \
						if column.data_type == TYPE_OBJECT \
						else "Variant type %s" % column.data_type
				return _commit_error(
					&"GDSQL_STORAGE_COLUMN_TYPE_MISMATCH",
					"Column '%s' expects %s." % [column.name, expected],
				)
	var result := GDSQLStorageCommitResult.new()
	result.value = true
	return result


func _validate_unique_column(
		table: GDSQLTableDefinition,
		column_name: StringName,
		rows: Array[GDSQLRowRecord],
		primary_key: bool,
) -> GDSQLStorageCommitResult:
	var seen_values: Array[Variant] = []
	for row in rows:
		var value: Variant = row.get_value(column_name)
		if value == null and not primary_key:
			continue
		if seen_values.has(value):
			var code := &"GDSQL_STORAGE_DUPLICATE_PRIMARY_KEY" \
					if primary_key \
					else &"GDSQL_STORAGE_DUPLICATE_UNIQUE_VALUE"
			var label := "Primary key" if primary_key else "Unique column '%s' value" % column_name
			return _commit_error(
				code,
				"%s '%s' appears more than once in %s.%s." \
						% [label, value, table.database_name, table.name],
			)
		seen_values.append(value)
	var result := GDSQLStorageCommitResult.new()
	result.value = true
	return result


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
