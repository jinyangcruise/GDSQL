class_name GDSQLBoundedScanExecutionTest
extends GdUnitTestSuite

const TestDatabase = preload("res://tests/utils/gdsql_test_database.gd")


class RepeatingCursorStorage:
	extends GDSQLTableStorage

	var read_count := 0


	func get_capabilities() -> GDSQLStorageCapabilities:
		return GDSQLStorageCapabilities.new(false, false, true)


	func read_batch(
		table: GDSQLTableDefinition,
		_session: GDSQLStorageSession,
		_request: GDSQLStorageReadRequest,
	) -> GDSQLStorageReadBatch:
		read_count += 1
		var batch := GDSQLStorageReadBatch.new()
		batch.rows.append(
			GDSQLRowRecord.new({&"id": read_count, &"name": "Repeated"}),
		)
		batch.next_cursor = GDSQLStorageReadCursor.new(
			GDSQLStorageBackendIds.IN_MEMORY,
			table.database_name,
			table.name,
			1,
		)
		batch.statistics.rows_scanned = 1
		batch.statistics.rows_returned = 1
		batch.value = batch.rows
		return batch


class SnapshotStorage:
	extends GDSQLTableStorage

	var rows: Array[GDSQLRowRecord] = []


	func read_table(
		_table: GDSQLTableDefinition,
		_session: GDSQLStorageSession,
		_request: GDSQLStorageReadRequest = null,
	) -> GDSQLTableSnapshot:
		var snapshot := GDSQLTableSnapshot.new()
		snapshot.rows = rows
		snapshot.row_count = rows.size()
		return snapshot


var _data_root: String
var _test_index := 0


func before_test() -> void:
	_test_index += 1
	_data_root = create_temp_dir("gdsql_bounded_scan_%d" % _test_index)


func test_scan_consumes_multiple_batches_before_relational_operations() -> void:
	var durable := TestDatabase.create_heroes_database(_data_root)
	var context := GDSQLRuntimeFactory.create_in_memory(_data_root)
	var database := GDSQLDatabase.new(durable.database_name, context)
	var table := context.catalog.get_table(durable.database_name, &"heroes")
	var records: Array[GDSQLRowRecord] = []
	for index in GDSQLDefaultQueryExecutor.DEFAULT_SCAN_BATCH_SIZE + 1:
		records.append(
			GDSQLRowRecord.new(
				{&"id": index + 1, &"name": "Hero %03d" % (index + 1)},
			),
		)
	assert_bool(
		(context.storage as GDSQLInMemoryTableStorage).load_table(
			table,
			records,
		).is_successful(),
	).is_true()

	var selected := database.execute(
		database.table(&"heroes")
		.select()
		.where(
			GDSQLComparisonExpression.new(
				GDSQLColumnExpression.new(&"id"),
				GDSQLComparisonExpression.ComparisonOperator.GREATER_THAN,
				GDSQLLiteralExpression.new(250),
			),
		)
		.order_by_column(&"id", GDSQLOrderClause.SortDirection.DESCENDING)
		.offset(1)
		.limit(2)
		.build(),
	)

	assert_bool(selected.is_successful()).is_true()
	assert_int(selected.get_returned_rows()).is_equal(2)
	assert_int(selected.rows[0].get_value(&"id")).is_equal(256)
	assert_int(selected.rows[1].get_value(&"id")).is_equal(255)
	assert_int(selected.statistics["storage_batches"]).is_equal(2)
	assert_int(selected.statistics["storage_rows_scanned"]).is_equal(514)
	assert_int(selected.statistics["storage_rows_returned"]).is_equal(257)
	assert_int(selected.statistics["storage_bytes_read"]).is_equal(-1)
	assert_int(selected.statistics["storage_pages_read"]).is_equal(-1)
	assert_bool(selected.statistics["storage_physical_read_bounded"]).is_false()
	assert_bool(selected.statistics.get("scan_window_pushed", false)).is_false()

	var page := database.execute(
		database.table(&"heroes").select().offset(255).limit(1).build(),
	)

	assert_bool(page.is_successful()).is_true()
	assert_int(page.get_returned_rows()).is_equal(1)
	assert_int(page.rows[0].get_value(&"id")).is_equal(256)
	assert_bool(page.statistics["scan_window_pushed"]).is_true()
	assert_int(page.statistics["scan_rows_pruned"]).is_equal(255)
	assert_int(page.statistics["storage_batches"]).is_equal(1)
	assert_int(page.statistics["storage_rows_returned"]).is_equal(256)


func test_scan_rejects_a_repeated_storage_continuation() -> void:
	var durable := TestDatabase.create_heroes_database(_data_root)
	var context := GDSQLRuntimeFactory.create_in_memory(_data_root)
	var storage := RepeatingCursorStorage.new()
	context.storage = storage
	context.execution_context.storage = storage
	var database := GDSQLDatabase.new(durable.database_name, context)

	var selected := database.execute(
		database.table(&"heroes").select().build(),
	)

	assert_bool(selected.is_successful()).is_false()
	assert_int(storage.read_count).is_equal(2)
	assert_str(String(selected.diagnostics.entries[0].code)).is_equal(
		"GDSQL_STORAGE_CURSOR_DID_NOT_ADVANCE",
	)


func test_safe_window_applies_to_snapshot_compatibility_storage() -> void:
	var durable := TestDatabase.create_heroes_database(_data_root)
	var context := GDSQLRuntimeFactory.create_in_memory(_data_root)
	var storage := SnapshotStorage.new()
	for index in 4:
		storage.rows.append(
			GDSQLRowRecord.new(
				{&"id": index + 1, &"name": "Hero %d" % (index + 1)},
			),
		)
	context.storage = storage
	context.execution_context.storage = storage
	var database := GDSQLDatabase.new(durable.database_name, context)

	var selected := database.execute(
		database.table(&"heroes").select().offset(1).limit(2).build(),
	)

	assert_bool(selected.is_successful()).is_true()
	assert_int(selected.get_returned_rows()).is_equal(2)
	assert_int(selected.rows[0].get_value(&"id")).is_equal(2)
	assert_int(selected.rows[1].get_value(&"id")).is_equal(3)
	assert_int(selected.statistics["storage_snapshot_fallbacks"]).is_equal(1)
	assert_int(selected.statistics["storage_rows_scanned"]).is_equal(4)
	assert_int(selected.statistics["scan_rows_pruned"]).is_equal(2)
