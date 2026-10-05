@abstract
class_name GDSQLTableStorage
extends RefCounted

func get_capabilities() -> GDSQLStorageCapabilities:
	return GDSQLStorageCapabilities.new()


func read_table(
	table: GDSQLTableDefinition,
	session: GDSQLStorageSession,
	request: GDSQLStorageReadRequest = null,
) -> GDSQLTableSnapshot:
	return null


## Reads at most request.batch_size rows and returns an opaque continuation.
## Concrete backends own cursor interpretation and report whether physical I/O
## was actually bounded.
func read_batch(
	table: GDSQLTableDefinition,
	session: GDSQLStorageSession,
	request: GDSQLStorageReadRequest,
) -> GDSQLStorageReadBatch:
	var result := GDSQLStorageReadBatch.new()
	result.add_diagnostic(
		GDSQLQueryDiagnostic.new(
			&"GDSQL_STORAGE_BOUNDED_READ_UNSUPPORTED",
			"The selected storage backend does not implement bounded reads.",
		),
	)
	return result


func _validate_bounded_read_request(
	request: GDSQLStorageReadRequest,
	backend_id: StringName,
	table: GDSQLTableDefinition,
	result: GDSQLStorageReadBatch,
) -> bool:
	if request == null or not request.is_bounded():
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_STORAGE_BOUNDED_REQUEST_REQUIRED",
				"A bounded storage read requires a positive batch size.",
			),
		)
		return false
	if request.cursor == null:
		return true
	if not request.cursor.is_for_backend(backend_id):
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_STORAGE_CURSOR_BACKEND_MISMATCH",
				"The read cursor belongs to a different storage backend.",
			),
		)
		return false
	if not request.cursor.is_for_source(table.database_name, table.name):
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_STORAGE_CURSOR_SOURCE_MISMATCH",
				"The read cursor belongs to a different database table.",
			),
		)
		return false
	return true


func _bounded_read_offset_error(
	offset: int,
	row_count: int,
) -> GDSQLStorageReadBatch:
	var result := GDSQLStorageReadBatch.new()
	result.add_diagnostic(
		GDSQLQueryDiagnostic.new(
			&"GDSQL_STORAGE_CURSOR_OUT_OF_RANGE",
			"Read cursor offset %d exceeds the current row count %d." \
					% [offset, row_count],
		),
	)
	return result


func find_by_primary_key(
	table: GDSQLTableDefinition,
	key: Variant,
	session: GDSQLStorageSession,
	request: GDSQLStorageReadRequest = null,
) -> GDSQLRowRecord:
	return null


func find_by_index(
		table: GDSQLTableDefinition,
	index: GDSQLIndexDefinition,
	values: Array[Variant],
	session: GDSQLStorageSession,
	request: GDSQLStorageReadRequest = null,
) -> Array[GDSQLRowRecord]:
	return []


func find_by_index_range(
		table: GDSQLTableDefinition,
		index: GDSQLIndexDefinition,
		lower_bound: Variant,
		upper_bound: Variant,
	include_lower: bool,
	include_upper: bool,
	session: GDSQLStorageSession,
	request: GDSQLStorageReadRequest = null,
) -> Array[GDSQLRowRecord]:
	return []


func stage_insert(table: GDSQLTableDefinition, row: GDSQLRowRecord, session: GDSQLStorageSession) -> GDSQLStorageOperationResult:
	return null


func stage_update(table: GDSQLTableDefinition, key: Variant, row: GDSQLRowRecord, session: GDSQLStorageSession) -> GDSQLStorageOperationResult:
	return null


func stage_delete(table: GDSQLTableDefinition, key: Variant, session: GDSQLStorageSession) -> GDSQLStorageOperationResult:
	return null


## Stages removal of every row and resets generated-key state to its initial
## value. This is intentionally distinct from staging individual deletes.
func stage_truncate(
		table: GDSQLTableDefinition,
		session: GDSQLStorageSession,
) -> GDSQLStorageOperationResult:
	return null


## Stages the exact next generated integer key. Persistence adapters use this
## when transferring an authoritative table snapshot between backends.
func stage_next_auto_increment(
		table: GDSQLTableDefinition,
		next_value: int,
		session: GDSQLStorageSession,
) -> GDSQLStorageOperationResult:
	return null


func commit(session: GDSQLStorageSession) -> GDSQLStorageCommitResult:
	return null


func rollback(session: GDSQLStorageSession) -> void:
	pass
