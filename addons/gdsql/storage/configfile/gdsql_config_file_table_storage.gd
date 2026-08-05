class_name GDSQLConfigFileTableStorage
extends GDSQLTableStorage

const TABLE_METADATA_SECTION := "__gdsql_metadata__"
const INDEX_SECTION_PREFIX := "__gdsql_index__:"

var path_resolver: GDSQLDatabasePathResolver
var config_cache: GDSQLConfigFileCache
var codec: GDSQLGodotVariantCodec


func _init(
		_path_resolver: GDSQLDatabasePathResolver,
		_config_cache: GDSQLConfigFileCache,
		_codec: GDSQLGodotVariantCodec,
) -> void:
	path_resolver = _path_resolver
	config_cache = _config_cache
	codec = _codec


func get_capabilities() -> GDSQLStorageCapabilities:
	return GDSQLStorageCapabilities.new(true, true)


func read_table(table: GDSQLTableDefinition, session: GDSQLStorageSession) -> GDSQLTableSnapshot:
	var snapshot := GDSQLTableSnapshot.new()
	snapshot.primary_key = table.primary_key
	if session != null and session.dirty:
		snapshot.rows = _build_effective_rows(table, session)
	else:
		snapshot.rows = _read_persisted_rows(table)
	return snapshot


func find_by_primary_key(
		table: GDSQLTableDefinition,
		key: Variant,
		session: GDSQLStorageSession,
) -> GDSQLRowRecord:
	if session != null and session.dirty:
		return _find_effective_row(table, key, session)
	var path := path_resolver.resolve_table_path(table.database_name, table.name)
	var config := config_cache.get_or_load(path)
	var section := str(key)
	if config == null or _is_reserved_section(section) or not config.has_section(section):
		return null
	return _read_row(config, section)


func find_by_index(
		table: GDSQLTableDefinition,
		index: GDSQLIndexDefinition,
		values: Array[Variant],
		session: GDSQLStorageSession,
) -> Array[GDSQLRowRecord]:
	if session != null and session.dirty:
		return _filter_effective_rows(table, index, values, session)
	var config := config_cache.get_or_load(
		path_resolver.resolve_table_path(table.database_name, table.name),
	)
	if config == null:
		return []
	var normalized_values := _normalize_index_values(table, index, values)
	var section := _index_section(index, normalized_values)
	if config.has_section(section) and _decode_index_values(
		config.get_value(section, "values", []),
	) == normalized_values:
		return _rows_for_sections(
			config,
			config.get_value(section, "rows", PackedStringArray()),
		)
	return []


func find_by_index_range(
		table: GDSQLTableDefinition,
		index: GDSQLIndexDefinition,
		lower_bound: Variant,
		upper_bound: Variant,
		include_lower: bool,
		include_upper: bool,
		session: GDSQLStorageSession,
) -> Array[GDSQLRowRecord]:
	var matching: Array[GDSQLRowRecord] = []
	if index.columns.size() != 1:
		return matching
	if lower_bound != null:
		lower_bound = _normalize_index_values(
			table,
			index,
			[lower_bound],
		)[0]
	if upper_bound != null:
		upper_bound = _normalize_index_values(
			table,
			index,
			[upper_bound],
		)[0]
	if session != null and session.dirty:
		for row in _build_effective_rows(table, session):
			var value: Variant = row.get_value(index.columns[0])
			if _value_in_range(value, lower_bound, upper_bound, include_lower, include_upper):
				matching.append(row)
		return matching
	var config := config_cache.get_or_load(
		path_resolver.resolve_table_path(table.database_name, table.name),
	)
	if config == null:
		return matching
	for section in config.get_sections():
		if not section.begins_with(_index_prefix(index)):
			continue
		var values := _decode_index_values(config.get_value(section, "values", []))
		if not values.is_empty() and _value_in_range(
			values[0],
			lower_bound,
			upper_bound,
			include_lower,
			include_upper,
		):
			matching.append_array(
				_rows_for_sections(
					config,
					config.get_value(section, "rows", PackedStringArray()),
				),
			)
	return matching


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
	if _is_reserved_section(str(key)):
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
	var touched_tables: Dictionary = { }
	for operation in session.operations:
		var table := operation["table"] as GDSQLTableDefinition
		touched_tables[_table_key(table)] = table
	for table_key in touched_tables:
		var table := touched_tables[table_key] as GDSQLTableDefinition
		var path := path_resolver.resolve_table_path(table.database_name, table.name)
		var config := config_cache.get_or_load(path)
		if config == null:
			return _commit_error(
				&"GDSQL_STORAGE_TABLE_UNREADABLE",
				"Could not load table file: %s" % path,
			)
		_rebuild_indexes(config, table)
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


func _read_persisted_rows(
		table: GDSQLTableDefinition,
) -> Array[GDSQLRowRecord]:
	var rows: Array[GDSQLRowRecord] = []
	var path := path_resolver.resolve_table_path(table.database_name, table.name)
	var config := config_cache.get_or_load(path)
	if config == null:
		return rows
	for section in config.get_sections():
		if _is_reserved_section(section):
			continue
		rows.append(_read_row(config, section))
	return rows


func _validate_session_constraints(
		session: GDSQLStorageSession,
) -> GDSQLStorageCommitResult:
	var tables: Dictionary = { }
	for operation in session.operations:
		var table := operation["table"] as GDSQLTableDefinition
		tables[_table_key(table)] = table
	for table_value in tables.values():
		var table := table_value as GDSQLTableDefinition
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
		for index in table.indexes:
			if not index.unique:
				continue
			var index_result := _validate_unique_index(table, index, rows)
			if not index_result.is_successful():
				return index_result
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
		if _is_reserved_section(section):
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
	for row in _read_persisted_rows(table):
		rows_by_key[row.get_value(table.primary_key)] = row
	for operation in session.operations:
		var operation_table := operation["table"] as GDSQLTableDefinition
		if _table_key(operation_table) != _table_key(table):
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


func _validate_unique_index(
		table: GDSQLTableDefinition,
		index: GDSQLIndexDefinition,
		rows: Array[GDSQLRowRecord],
) -> GDSQLStorageCommitResult:
	var seen_values: Array[Array] = []
	for row in rows:
		var values: Array = []
		var contains_null := false
		for column_name in index.columns:
			var value: Variant = row.get_value(column_name)
			values.append(value)
			contains_null = contains_null or value == null
		if contains_null:
			continue
		if seen_values.has(values):
			return _commit_error(
				&"GDSQL_STORAGE_DUPLICATE_INDEX_VALUE",
				"Unique index '%s' value '%s' appears more than once in %s.%s." \
						% [index.name, values, table.database_name, table.name],
			)
		seen_values.append(values)
	var result := GDSQLStorageCommitResult.new()
	result.value = true
	return result


func _rebuild_indexes(config: ConfigFile, table: GDSQLTableDefinition) -> void:
	for section in config.get_sections():
		if section.begins_with(INDEX_SECTION_PREFIX):
			config.erase_section(section)
	for index in table.indexes:
		for row_section in _get_row_sections(config):
			var row := _read_row(config, row_section)
			var values := _normalize_index_values(
				table,
				index,
				_index_values(row, index),
			)
			var section := _index_section(index, values)
			if not config.has_section(section):
				var encoded_values: Array = []
				for value in values:
					encoded_values.append(codec.encode(value))
				config.set_value(section, "values", encoded_values)
				config.set_value(
					section,
					"rows",
					PackedStringArray([row_section]),
				)
				continue
			var row_sections: PackedStringArray = config.get_value(
				section,
				"rows",
				PackedStringArray(),
			)
			row_sections.append(row_section)
			config.set_value(section, "rows", row_sections)


func _decode_index_values(encoded_values: Array) -> Array[Variant]:
	var values: Array[Variant] = []
	for value in encoded_values:
		values.append(codec.decode(value))
	return values


func _index_values(row: GDSQLRowRecord, index: GDSQLIndexDefinition) -> Array:
	var values: Array = []
	for column_name in index.columns:
		values.append(row.get_value(column_name))
	return values


func _normalize_index_values(
		table: GDSQLTableDefinition,
		index: GDSQLIndexDefinition,
		values: Array,
) -> Array[Variant]:
	var normalized: Array[Variant] = []
	for value_index in values.size():
		var value: Variant = values[value_index]
		var column := table.get_column(index.columns[value_index])
		if value != null and column != null:
			match column.data_type:
				TYPE_INT:
					value = int(value)
				TYPE_FLOAT:
					value = float(value)
				TYPE_STRING:
					value = String(value)
				TYPE_STRING_NAME:
					value = StringName(value)
		normalized.append(value)
	return normalized


func _filter_effective_rows(
		table: GDSQLTableDefinition,
		index: GDSQLIndexDefinition,
		values: Array[Variant],
		session: GDSQLStorageSession,
) -> Array[GDSQLRowRecord]:
	var matching: Array[GDSQLRowRecord] = []
	var normalized_values := _normalize_index_values(table, index, values)
	for row in _build_effective_rows(table, session):
		if _normalize_index_values(
			table,
			index,
			_index_values(row, index),
		) == normalized_values:
			matching.append(row)
	return matching


func _find_effective_row(
		table: GDSQLTableDefinition,
		key: Variant,
		session: GDSQLStorageSession,
) -> GDSQLRowRecord:
	for row in _build_effective_rows(table, session):
		if row.get_value(table.primary_key) == key:
			return row
	return null


func _rows_for_sections(
		config: ConfigFile,
		sections: PackedStringArray,
) -> Array[GDSQLRowRecord]:
	var rows: Array[GDSQLRowRecord] = []
	for section in sections:
		if config.has_section(section) and not _is_reserved_section(section):
			rows.append(_read_row(config, section))
	return rows


func _read_row(config: ConfigFile, section: String) -> GDSQLRowRecord:
	var values: Dictionary = { }
	for key in config.get_section_keys(section):
		values[StringName(key)] = codec.decode(config.get_value(section, key))
	return GDSQLRowRecord.new(values)


func _get_row_sections(config: ConfigFile) -> PackedStringArray:
	var sections := PackedStringArray()
	for section in config.get_sections():
		if not _is_reserved_section(section):
			sections.append(section)
	return sections


func _is_reserved_section(section: String) -> bool:
	return section == TABLE_METADATA_SECTION or section.begins_with(INDEX_SECTION_PREFIX)


func _index_prefix(index: GDSQLIndexDefinition) -> String:
	return "%s%s:" % [INDEX_SECTION_PREFIX, index.name]


func _index_section(index: GDSQLIndexDefinition, values: Array) -> String:
	return "%s%s" % [_index_prefix(index), var_to_bytes(values).hex_encode()]


func _value_in_range(
		value: Variant,
		lower_bound: Variant,
		upper_bound: Variant,
		include_lower: bool,
		include_upper: bool,
) -> bool:
	if value == null:
		return false
	if lower_bound != null:
		var lower_comparison := _compare_values(value, lower_bound)
		if lower_comparison < 0 or lower_comparison == 0 and not include_lower:
			return false
	if upper_bound != null:
		var upper_comparison := _compare_values(value, upper_bound)
		if upper_comparison > 0 or upper_comparison == 0 and not include_upper:
			return false
	return true


func _compare_values(left: Variant, right: Variant) -> int:
	if left == right:
		return 0
	if (left is int or left is float) and (right is int or right is float):
		return -1 if left < right else 1
	if String(left) == String(right):
		return 0
	return -1 if String(left) < String(right) else 1


func _has_staged_key(session: GDSQLStorageSession, table: GDSQLTableDefinition, key: Variant) -> bool:
	for operation in session.operations:
		var operation_table := operation["table"] as GDSQLTableDefinition
		if operation["type"] == &"insert" \
				and _table_key(operation_table) == _table_key(table):
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
