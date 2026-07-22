class_name GDSQLInMemoryTableStorage
extends GDSQLTableStorage
## Stores authoritative table rows in memory while preserving storage-session
## visibility and commit semantics.
##
## Successful mutation commits mark the affected tables dirty. A checkpoint
## adapter can inspect those tables and clear each dirty version after copying
## it to a durable [GDSQLTableStorage].

var _tables: Dictionary = { }
var _metadata: Dictionary = { }
var _definitions: Dictionary = { }
var _versions: Dictionary = { }
var _dirty_versions: Dictionary = { }


func get_capabilities() -> GDSQLStorageCapabilities:
	return GDSQLStorageCapabilities.new(true, true)


func read_table(
		table: GDSQLTableDefinition,
		session: GDSQLStorageSession,
) -> GDSQLTableSnapshot:
	var snapshot := GDSQLTableSnapshot.new()
	snapshot.primary_key = table.primary_key
	snapshot.rows = _effective_rows(table, session)
	return snapshot


func find_by_primary_key(
		table: GDSQLTableDefinition,
		key: Variant,
		session: GDSQLStorageSession,
) -> GDSQLRowRecord:
	for row in _effective_rows(table, session):
		if row.get_value(table.primary_key) == key:
			return row
	return null


func find_by_index(
		table: GDSQLTableDefinition,
		index: GDSQLIndexDefinition,
		values: Array[Variant],
		session: GDSQLStorageSession,
) -> Array[GDSQLRowRecord]:
	var matching: Array[GDSQLRowRecord] = []
	var expected := _normalize_index_values(table, index, values)
	for row in _effective_rows(table, session):
		if _normalize_index_values(table, index, _index_values(row, index)) == expected:
			matching.append(row)
	return matching


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
		lower_bound = _normalize_index_values(table, index, [lower_bound])[0]
	if upper_bound != null:
		upper_bound = _normalize_index_values(table, index, [upper_bound])[0]
	for row in _effective_rows(table, session):
		var value: Variant = row.get_value(index.columns[0])
		if _value_in_range(value, lower_bound, upper_bound, include_lower, include_upper):
			matching.append(row)
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
		var metadata := _session_metadata(table, session)
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
	if find_by_primary_key(table, key, session) != null:
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_STORAGE_DUPLICATE_PRIMARY_KEY",
				"Primary key '%s' already exists in %s.%s." \
						% [key, table.database_name, table.name],
			),
		)
		return result
	var metadata := _session_metadata(table, session)
	metadata["row_count"] = int(metadata["row_count"]) + 1
	if primary_key != null and primary_key.auto_increment \
			and key is int and key >= int(metadata["next_auto_increment"]):
		metadata["next_auto_increment"] = key + 1
	session.operations.append(
		{ "type": &"insert", "table": table, "row": row.duplicate_record() },
	)
	session.dirty = true
	result.value = row
	return result


func stage_update(
		table: GDSQLTableDefinition,
		key: Variant,
		row: GDSQLRowRecord,
		session: GDSQLStorageSession,
) -> GDSQLStorageOperationResult:
	if find_by_primary_key(table, key, session) == null:
		return _missing_row_result(table, key, &"update")
	var result := GDSQLStorageOperationResult.new()
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


func stage_delete(
		table: GDSQLTableDefinition,
		key: Variant,
		session: GDSQLStorageSession,
) -> GDSQLStorageOperationResult:
	if find_by_primary_key(table, key, session) == null:
		return _missing_row_result(table, key, &"delete")
	var result := GDSQLStorageOperationResult.new()
	var metadata := _session_metadata(table, session)
	metadata["row_count"] = maxi(0, int(metadata["row_count"]) - 1)
	session.operations.append({ "type": &"delete", "table": table, "key": key })
	session.dirty = true
	result.value = true
	return result


func commit(session: GDSQLStorageSession) -> GDSQLStorageCommitResult:
	var touched := _touched_tables(session)
	var validation := _validate_session_constraints(session, touched)
	if not validation.is_successful():
		return validation
	for operation in session.operations:
		var table := operation["table"] as GDSQLTableDefinition
		var rows := _table_rows(table)
		var operation_type := operation["type"] as StringName
		var key: Variant = operation["key"] \
		if operation.has("key") \
		else (operation["row"] as GDSQLRowRecord).get_value(table.primary_key)
		if operation_type == &"delete":
			rows.erase(key)
		else:
			rows[key] = (operation["row"] as GDSQLRowRecord).duplicate_record()
	for table_key in session.table_metadata:
		var metadata: Dictionary = session.table_metadata[table_key]
		_metadata[table_key] = {
			"row_count": int(metadata["row_count"]),
			"next_auto_increment": int(metadata["next_auto_increment"]),
		}
	for table_key in touched:
		_definitions[table_key] = touched[table_key]
		var version := int(_versions.get(table_key, 0)) + 1
		_versions[table_key] = version
		_dirty_versions[table_key] = version
	session.clear()
	var result := GDSQLStorageCommitResult.new()
	result.value = true
	return result


func rollback(session: GDSQLStorageSession) -> void:
	session.clear()


## Replaces one authoritative in-memory table without marking it dirty. This is
## the loading boundary for fixtures, content caches, and buffered composition.
func load_table(
		table: GDSQLTableDefinition,
		rows: Array[GDSQLRowRecord],
) -> GDSQLStorageOperationResult:
	var loading := GDSQLInMemoryTableStorage.new()
	var session := GDSQLStorageSession.new()
	for row in rows:
		var staged := loading.stage_insert(table, row.duplicate_record(), session)
		if not staged.is_successful():
			loading.rollback(session)
			return staged
	var committed := loading.commit(session)
	if not committed.is_successful():
		var failed := GDSQLStorageOperationResult.new()
		failed.diagnostics.merge(committed.diagnostics)
		return failed
	var table_key := _table_key(table)
	_tables[table_key] = loading._tables.get(table_key, { }).duplicate(true)
	_metadata[table_key] = loading._metadata.get(
		table_key,
		{ "row_count": rows.size(), "next_auto_increment": 1 },
	).duplicate()
	_definitions[table_key] = table
	_versions[table_key] = int(_versions.get(table_key, 0)) + 1
	_dirty_versions.erase(table_key)
	var result := GDSQLStorageOperationResult.new()
	result.value = true
	return result


## Reports whether any committed table version awaits a checkpoint.
func is_dirty() -> bool:
	return not _dirty_versions.is_empty()


## Returns definitions for committed tables awaiting a checkpoint.
func get_dirty_tables() -> Array[GDSQLTableDefinition]:
	var tables: Array[GDSQLTableDefinition] = []
	for table_key in _dirty_versions:
		tables.append(_definitions[table_key])
	return tables


func get_table_version(table: GDSQLTableDefinition) -> int:
	return int(_versions.get(_table_key(table), 0))


## Clears a dirty marker only when the checkpointed version is still current.
func mark_checkpointed(table: GDSQLTableDefinition, version: int) -> void:
	var table_key := _table_key(table)
	if int(_dirty_versions.get(table_key, -1)) == version:
		_dirty_versions.erase(table_key)


func _table_rows(table: GDSQLTableDefinition) -> Dictionary:
	var table_key := _table_key(table)
	if not _tables.has(table_key):
		_tables[table_key] = { }
	return _tables[table_key]


func _effective_rows(
		table: GDSQLTableDefinition,
		session: GDSQLStorageSession,
) -> Array[GDSQLRowRecord]:
	var rows_by_key: Dictionary = { }
	for key in _table_rows(table):
		rows_by_key[key] = (_table_rows(table)[key] as GDSQLRowRecord).duplicate_record()
	if session != null:
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


func _session_metadata(
		table: GDSQLTableDefinition,
		session: GDSQLStorageSession,
) -> Dictionary:
	var table_key := _table_key(table)
	if not session.table_metadata.has(table_key):
		var current: Dictionary = _metadata.get(
			table_key,
			{ "row_count": _table_rows(table).size(), "next_auto_increment": 1 },
		)
		var metadata := current.duplicate()
		metadata["table"] = table
		session.table_metadata[table_key] = metadata
	return session.table_metadata[table_key]


func _touched_tables(session: GDSQLStorageSession) -> Dictionary:
	var tables: Dictionary = { }
	for operation in session.operations:
		var table := operation["table"] as GDSQLTableDefinition
		tables[_table_key(table)] = table
	return tables


func _validate_session_constraints(
		session: GDSQLStorageSession,
		tables: Dictionary,
) -> GDSQLStorageCommitResult:
	for table_value in tables.values():
		var table := table_value as GDSQLTableDefinition
		var rows := _effective_rows(table, session)
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
				if not column.accepts_value(row.get_value(column.name)):
					var expected := "Resource" \
					if column.data_type == TYPE_OBJECT \
					else "Variant type %s" % column.data_type
					return _commit_error(
						&"GDSQL_STORAGE_COLUMN_TYPE_MISMATCH",
						"Column '%s' expects %s." % [column.name, expected],
					)
		var primary := _validate_unique_column(table, table.primary_key, rows, true)
		if not primary.is_successful():
			return primary
		for column in table.columns:
			if column.unique and column.name != table.primary_key:
				var unique := _validate_unique_column(table, column.name, rows, false)
				if not unique.is_successful():
					return unique
		for index in table.indexes:
			if index.unique:
				var unique_index := _validate_unique_index(table, index, rows)
				if not unique_index.is_successful():
					return unique_index
	var result := GDSQLStorageCommitResult.new()
	result.value = true
	return result


func _validate_unique_column(
		table: GDSQLTableDefinition,
		column_name: StringName,
		rows: Array[GDSQLRowRecord],
		primary_key: bool,
) -> GDSQLStorageCommitResult:
	var seen: Array[Variant] = []
	for row in rows:
		var value: Variant = row.get_value(column_name)
		if value == null and not primary_key:
			continue
		if seen.has(value):
			return _commit_error(
				&"GDSQL_STORAGE_DUPLICATE_PRIMARY_KEY" \
				if primary_key \
				else &"GDSQL_STORAGE_DUPLICATE_UNIQUE_VALUE",
				"Value '%s' appears more than once in %s.%s." \
						% [value, table.database_name, table.name],
			)
		seen.append(value)
	var result := GDSQLStorageCommitResult.new()
	result.value = true
	return result


func _validate_unique_index(
		table: GDSQLTableDefinition,
		index: GDSQLIndexDefinition,
		rows: Array[GDSQLRowRecord],
) -> GDSQLStorageCommitResult:
	var seen: Array[Array] = []
	for row in rows:
		var values := _index_values(row, index)
		if values.has(null):
			continue
		if seen.has(values):
			return _commit_error(
				&"GDSQL_STORAGE_DUPLICATE_INDEX_VALUE",
				"Unique index '%s' value '%s' appears more than once in %s.%s." \
						% [index.name, values, table.database_name, table.name],
			)
		seen.append(values)
	var result := GDSQLStorageCommitResult.new()
	result.value = true
	return result


func _index_values(
		row: GDSQLRowRecord,
		index: GDSQLIndexDefinition,
) -> Array[Variant]:
	var values: Array[Variant] = []
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
		var comparison := _compare_values(value, lower_bound)
		if comparison < 0 or comparison == 0 and not include_lower:
			return false
	if upper_bound != null:
		var comparison := _compare_values(value, upper_bound)
		if comparison > 0 or comparison == 0 and not include_upper:
			return false
	return true


func _compare_values(left: Variant, right: Variant) -> int:
	if left == right:
		return 0
	if (left is int or left is float) and (right is int or right is float):
		return -1 if left < right else 1
	return -1 if String(left) < String(right) else 1


func _missing_row_result(
		table: GDSQLTableDefinition,
		key: Variant,
		operation: StringName,
) -> GDSQLStorageOperationResult:
	var result := GDSQLStorageOperationResult.new()
	result.add_diagnostic(
		GDSQLQueryDiagnostic.new(
			&"GDSQL_STORAGE_ROW_NOT_FOUND",
			"Cannot %s missing primary key '%s' in %s.%s." \
					% [operation, key, table.database_name, table.name],
		),
	)
	return result


func _table_key(table: GDSQLTableDefinition) -> String:
	return "%s.%s" % [table.database_name, table.name]


func _commit_error(code: StringName, message: String) -> GDSQLStorageCommitResult:
	var result := GDSQLStorageCommitResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
