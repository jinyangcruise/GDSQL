class_name GDSQLInMemoryCheckpointTarget
extends GDSQLCheckpointTarget
## Copies authoritative dirty tables from in-memory storage into an injected
## durable table-storage backend.

var _memory: GDSQLInMemoryTableStorage
var _durable: GDSQLTableStorage


func _init(
		memory: GDSQLInMemoryTableStorage,
		durable: GDSQLTableStorage,
) -> void:
	assert(memory != null)
	assert(durable != null)
	_memory = memory
	_durable = durable


func is_dirty() -> bool:
	return _memory.is_dirty()


func checkpoint() -> GDSQLCheckpointResult:
	var result := GDSQLCheckpointResult.new()
	var versions: Dictionary = { }
	var session := GDSQLStorageSession.new()
	for table in _memory.get_dirty_tables():
		versions[table] = _memory.get_table_version(table)
		var staged := _stage_table(table, session)
		result.diagnostics.merge(staged.diagnostics)
		if not staged.is_successful():
			_durable.rollback(session)
			return result
	var committed := _durable.commit(session)
	result.diagnostics.merge(committed.diagnostics)
	if not committed.is_successful():
		_durable.rollback(session)
		return result
	for table in versions:
		_memory.mark_checkpointed(table, versions[table])
	result.value = true
	return result


func _stage_table(
		table: GDSQLTableDefinition,
		session: GDSQLStorageSession,
) -> GDSQLStorageOperationResult:
	var source := _rows_by_key(_memory.read_table(table, null), table)
	var destination := _rows_by_key(_durable.read_table(table, session), table)
	for key in destination:
		if not source.has(key):
			var deleted := _durable.stage_delete(table, key, session)
			if not deleted.is_successful():
				return deleted
	for key in source:
		var row := source[key] as GDSQLRowRecord
		var staged: GDSQLStorageOperationResult
		if not destination.has(key):
			staged = _durable.stage_insert(table, row.duplicate_record(), session)
		elif not _rows_equal(row, destination[key]):
			staged = _durable.stage_update(table, key, row.duplicate_record(), session)
		else:
			continue
		if not staged.is_successful():
			return staged
	var result := GDSQLStorageOperationResult.new()
	result.value = true
	return result


func _rows_by_key(
		snapshot: GDSQLTableSnapshot,
		table: GDSQLTableDefinition,
) -> Dictionary:
	var rows: Dictionary = { }
	for row in snapshot.rows:
		rows[row.get_value(table.primary_key)] = row
	return rows


func _rows_equal(left: GDSQLRowRecord, right: GDSQLRowRecord) -> bool:
	return left.values == right.values
