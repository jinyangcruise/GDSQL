class_name GDSQLEditorRowBatch
extends RefCounted
## Validated canonical row mutations executed through one database transaction.

enum Operation { UPDATE, DELETE }

var database_name: StringName
var table_name: StringName
var operation: Operation
var row_count: int:
	get:
		return _queries.size()
var _queries: Array[GDSQLQuerySpec] = []
var _history_before_rows: Array[GDSQLRowRecord] = []
var _history_after_rows: Array[GDSQLRowRecord] = []


static func build_updates(
		table: GDSQLTableDefinition,
		updates: Array[Dictionary],
) -> GDSQLOperationResult:
	var result := _validate_request(table, updates.size(), "update")
	if not result.is_successful():
		return result
	var queries: Array[GDSQLQuerySpec] = []
	var identities: Array[Variant] = []
	for index in updates.size():
		var update := updates[index]
		if not update.has("primary_key"):
			result.add_diagnostic(
				_error(
					&"GDSQL_EDITOR_ROW_BATCH_IDENTITY_REQUIRED",
					"Update %d has no primary-key identity." % (index + 1),
				),
			)
			continue
		var identity: Variant = update.get("primary_key")
		if identities.has(identity):
			result.add_diagnostic(
				_error(
					&"GDSQL_EDITOR_ROW_BATCH_DUPLICATE_IDENTITY",
					"Primary key '%s' occurs more than once in the update batch." % identity,
				),
			)
			continue
		identities.append(identity)
		var query := _build_update_query(
			table,
			identity,
			update.get("values", { }),
			result,
			index,
		)
		if query != null:
			queries.append(query)
	if result.is_successful():
		var batch := GDSQLEditorRowBatch.new(
			table,
			Operation.UPDATE,
			queries,
		)
		batch._configure_update_history(table, updates)
		result.value = batch
	return result


static func build_deletes(
		table: GDSQLTableDefinition,
		primary_keys: Array[Variant],
) -> GDSQLOperationResult:
	var result := _validate_request(table, primary_keys.size(), "delete")
	if not result.is_successful():
		return result
	var queries: Array[GDSQLQuerySpec] = []
	var identities: Array[Variant] = []
	for identity in primary_keys:
		if identities.has(identity):
			result.add_diagnostic(
				_error(
					&"GDSQL_EDITOR_ROW_BATCH_DUPLICATE_IDENTITY",
					"Primary key '%s' occurs more than once in the delete batch." % identity,
				),
			)
			continue
		identities.append(identity)
		queries.append(
			GDSQLQuery.new(table.database_name) \
					.table(table.name) \
					.delete() \
					.where(GDSQLExpr.column(table.primary_key).equals(identity)) \
					.build(),
		)
	if result.is_successful():
		result.value = GDSQLEditorRowBatch.new(
			table,
			Operation.DELETE,
			queries,
		)
	return result


static func _build_update_query(
		table: GDSQLTableDefinition,
		identity: Variant,
		values: Dictionary,
		result: GDSQLOperationResult,
		update_index: int,
) -> GDSQLUpdateQuerySpec:
	var builder := GDSQLQuery.new(table.database_name).table(table.name).update()
	var assignment_count := 0
	for raw_column_name in values:
		var column_name := StringName(raw_column_name)
		var column := table.get_column(column_name)
		if column == null:
			result.add_diagnostic(
				_error(
					&"GDSQL_EDITOR_ROW_BATCH_COLUMN_NOT_FOUND",
					"Update %d references unknown column '%s'." % [
						update_index + 1,
						column_name,
					],
				),
			)
			continue
		if column.name == table.primary_key \
				or column.auto_increment \
				or column.generation != GDSQLColumnDefinition.Generation.NONE:
			result.add_diagnostic(
				_error(
					&"GDSQL_EDITOR_ROW_BATCH_COLUMN_READ_ONLY",
					"Column '%s' cannot be changed through row editing." % column_name,
				),
			)
			continue
		var value: Variant = values[raw_column_name]
		if not column.accepts_value(value):
			result.add_diagnostic(
				_error(
					&"GDSQL_EDITOR_ROW_BATCH_VALUE_INVALID",
					"Column '%s' expects %s." % [
						column_name,
						column.display_type_name(),
					],
				),
			)
			continue
		builder.set_value(column_name, value)
		assignment_count += 1
	if assignment_count == 0 and result.is_successful():
		result.add_diagnostic(
			_error(
				&"GDSQL_EDITOR_ROW_BATCH_UPDATE_EMPTY",
				"Update %d contains no mutable values." % (update_index + 1),
			),
		)
		return null
	if not result.is_successful():
		return null
	return builder.where(
		GDSQLExpr.column(table.primary_key).equals(identity),
	).build()


static func _validate_request(
		table: GDSQLTableDefinition,
		requested_rows: int,
		operation_name: String,
) -> GDSQLOperationResult:
	if table == null:
		return _failed(
			&"GDSQL_EDITOR_ROW_BATCH_TABLE_REQUIRED",
			"A table definition is required to build a row batch.",
		)
	if requested_rows <= 0:
		return _failed(
			&"GDSQL_EDITOR_ROW_BATCH_EMPTY",
			"At least one row is required for a batch %s." % operation_name,
		)
	return GDSQLOperationResult.new()


static func _failed(code: StringName, message: String) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.add_diagnostic(_error(code, message))
	return result


static func _error(code: StringName, message: String) -> GDSQLQueryDiagnostic:
	return GDSQLQueryDiagnostic.new(code, message)


func _init(
		table: GDSQLTableDefinition = null,
		batch_operation: Operation = Operation.UPDATE,
		canonical_queries: Array[GDSQLQuerySpec] = [],
) -> void:
	if table != null:
		database_name = table.database_name
		table_name = table.name
	operation = batch_operation
	_queries = canonical_queries.duplicate()


func get_queries() -> Array[GDSQLQuerySpec]:
	return _queries.duplicate()


func create_history_entry(
		registration_name: StringName,
) -> GDSQLEditorMutationHistoryEntry:
	if operation != Operation.UPDATE \
			or _history_before_rows.is_empty() \
			or _history_before_rows.size() != _history_after_rows.size():
		return null
	return GDSQLEditorMutationHistoryEntry.new(
		registration_name,
		database_name,
		table_name,
		GDSQLEditorMutationHistoryEntry.Operation.UPDATE,
		_history_before_rows,
		_history_after_rows,
	)


func execute(database: GDSQLDatabase) -> GDSQLOperationResult:
	if database == null:
		return _failed(
			&"GDSQL_EDITOR_ROW_BATCH_DATABASE_REQUIRED",
			"A database is required to execute a row batch.",
		)
	if _queries.is_empty():
		return _failed(
			&"GDSQL_EDITOR_ROW_BATCH_EMPTY",
			"An empty row batch cannot be executed.",
		)
	if database.database_name != database_name:
		return _failed(
			&"GDSQL_EDITOR_ROW_BATCH_DATABASE_MISMATCH",
			"The row batch targets database '%s', not '%s'." % [
				database_name,
				database.database_name,
			],
		)
	var result := database.transaction(
		func(transaction: GDSQLTransaction) -> void:
			for query in _queries:
				transaction.execute(query)
	)
	if result.is_successful():
		result.value = self
	return result


func _configure_update_history(
		table: GDSQLTableDefinition,
		updates: Array[Dictionary],
) -> void:
	_history_before_rows.clear()
	_history_after_rows.clear()
	for update in updates:
		var before_values: Dictionary = update.get("before_values", { })
		var after_values: Dictionary = update.get("values", { })
		if before_values.size() != after_values.size():
			_history_before_rows.clear()
			_history_after_rows.clear()
			return
		var before_snapshot := { table.primary_key: update.get("primary_key") }
		var after_snapshot := before_snapshot.duplicate()
		for column_name in after_values:
			if not before_values.has(column_name) \
					or typeof(before_values[column_name]) == TYPE_OBJECT \
					or typeof(after_values[column_name]) == TYPE_OBJECT:
				_history_before_rows.clear()
				_history_after_rows.clear()
				return
			before_snapshot[column_name] = before_values[column_name]
			after_snapshot[column_name] = after_values[column_name]
		_history_before_rows.append(GDSQLRowRecord.new(before_snapshot))
		_history_after_rows.append(GDSQLRowRecord.new(after_snapshot))
