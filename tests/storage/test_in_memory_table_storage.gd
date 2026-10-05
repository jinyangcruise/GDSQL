class_name GDSQLInMemoryTableStorageTest
extends GdUnitTestSuite

const TestDatabase = preload("res://tests/utils/gdsql_test_database.gd")
const REFERENCED_ICON_PATH := "res://addons/gdsql/editor/workspace/icons/key.svg"

var _data_root: String
var _test_index := 0


func before_test() -> void:
	_test_index += 1
	_data_root = create_temp_dir("gdsql_in_memory_%d" % _test_index)


func test_committed_rows_are_visible_and_rollback_discards_staged_rows() -> void:
	var table := _heroes_table()
	var storage := GDSQLInMemoryTableStorage.new()
	var committed := GDSQLStorageSession.new()
	storage.stage_insert(table, _hero(1, "Knight"), committed)
	assert_bool(storage.commit(committed).is_successful()).is_true()
	var rolled_back := GDSQLStorageSession.new()
	storage.stage_insert(table, _hero(2, "Mage"), rolled_back)
	assert_int(storage.read_table(table, rolled_back).rows.size()).is_equal(2)
	storage.rollback(rolled_back)

	assert_int(storage.read_table(table, null).rows.size()).is_equal(1)
	assert_bool(storage.is_dirty()).is_true()


func test_in_memory_storage_executes_crud_through_the_query_pipeline() -> void:
	var disk_database := TestDatabase.create_database(_data_root, _heroes_table())
	var context := GDSQLRuntimeFactory.create_in_memory(_data_root)
	var database := GDSQLDatabase.new(disk_database.database_name, context)

	assert_bool(database.insert(&"heroes", { &"id": 1, &"name": "Knight" }).is_successful()).is_true()
	var selected := database.execute(
		database.query().select().from_table(&"heroes").build(),
	)

	assert_bool(selected.is_successful()).is_true()
	assert_int(selected.get_returned_rows()).is_equal(1)
	assert_str(selected.rows[0].get_value(&"name")).is_equal("Knight")
	var updated := database.execute(
		database.table(&"heroes")
		.update()
		.set_value(&"name", "Mage")
		.where(TestDatabase.id_equals(1))
		.build(),
	)
	assert_bool(updated.is_successful()).is_true()
	assert_str(updated.rows[0].get_value(&"name")).is_equal("Mage")
	var deleted := database.execute(
		database.table(&"heroes")
		.delete()
		.where(TestDatabase.id_equals(1))
		.build(),
	)
	assert_bool(deleted.is_successful()).is_true()
	assert_int(
		database.execute(
			database.query().select().from_table(&"heroes").build(),
		).get_returned_rows(),
	).is_equal(0)
	assert_bool((context.storage as GDSQLInMemoryTableStorage).is_dirty()).is_true()


func test_checkpoint_copies_dirty_memory_state_to_configfile_storage() -> void:
	var disk_database := TestDatabase.create_database(_data_root, _heroes_table())
	var context := GDSQLRuntimeFactory.create_in_memory(_data_root)
	var database := GDSQLDatabase.new(disk_database.database_name, context)
	database.insert(&"heroes", { &"id": 1, &"name": "Knight" })
	var memory := context.storage as GDSQLInMemoryTableStorage
	var durable := GDSQLConfigFileTableStorage.new(
		GDSQLDatabasePathResolver.new(_data_root),
		GDSQLConfigFileCache.new(),
		GDSQLGodotVariantCodec.new(),
	)
	var coordinator := GDSQLPersistenceCoordinator.new()
	coordinator.register(
		&"runtime",
		GDSQLInMemoryCheckpointTarget.new(memory, durable),
		GDSQLCheckpointPolicy.manual(),
	)

	var checkpoint := coordinator.checkpoint(&"runtime")

	var selected := disk_database.execute(
		disk_database.query().select().from_table(&"heroes").build(),
	)

	assert_bool(checkpoint.is_successful()).is_true()
	assert_array(checkpoint.checkpointed_databases).contains_exactly([&"runtime"])
	assert_bool(memory.is_dirty()).is_false()
	assert_int(selected.get_returned_rows()).is_equal(1)
	assert_str(selected.rows[0].get_value(&"name")).is_equal("Knight")


func test_hydration_and_checkpoint_preserve_truncated_generated_key_state() -> void:
	var disk_database := TestDatabase.create_database(
		_data_root,
		_auto_increment_heroes_table(),
	)
	assert_bool(
		disk_database.execute(
			disk_database.table(&"heroes")
			.insert()
			.values({&"name": "Knight"})
			.values({&"name": "Mage"})
			.build(),
		).is_successful(),
	).is_true()
	assert_bool(
		disk_database.execute(
			disk_database.table(&"heroes")
			.delete()
			.where(TestDatabase.id_equals(2))
			.build(),
		).is_successful(),
	).is_true()
	var opened := GDSQLRuntimeFactory.open_registration(
		GDSQLDatabaseRegistration.new(
			&"runtime",
			disk_database.database_name,
			_data_root,
			GDSQLStorageBackendIds.IN_MEMORY,
		),
	)
	assert_bool(opened.is_successful()).is_true()
	var database := opened.get_database()
	var context := database.context
	var memory := context.storage as GDSQLInMemoryTableStorage
	var durable := GDSQLConfigFileTableStorage.new(
		GDSQLDatabasePathResolver.new(_data_root),
		GDSQLConfigFileCache.new(),
		GDSQLGodotVariantCodec.new(),
	)
	var hydrated_insert := database.insert(&"heroes", {&"name": "Ranger"})
	assert_bool(database.truncate_table(&"heroes").is_successful()).is_true()
	var inserted := database.insert(&"heroes", {&"name": "Rogue"})
	var checkpoint := GDSQLInMemoryCheckpointTarget.new(memory, durable).checkpoint()
	var reopened := GDSQLDatabase.open(
		disk_database.database_name,
		_data_root,
	).get_database()
	var next_insert := reopened.insert(&"heroes", {&"name": "Cleric"})

	assert_int(hydrated_insert.rows[0].get_value(&"id")).is_equal(3)
	assert_int(inserted.rows[0].get_value(&"id")).is_equal(1)
	assert_bool(checkpoint.is_successful()).is_true()
	assert_int(next_insert.rows[0].get_value(&"id")).is_equal(2)


func test_hydration_keeps_referenced_assets_inert_in_memory() -> void:
	var icon := load(REFERENCED_ICON_PATH) as Resource
	var table := GDSQLTableDefinition.new(&"assets", &"id")
	table.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true))
	table.add_column(GDSQLColumnDefinition.new(&"name", TYPE_STRING, false))
	var icon_column := GDSQLColumnDefinition.new(&"icon", TYPE_OBJECT, false)
	icon_column.resource_type = GDSQLResourceTypeConstraint.from_resource(icon)
	icon_column.resource_ownership = GDSQLResourceOwnership.Mode.REFERENCED
	table.add_column(icon_column)
	var disk_database := TestDatabase.create_database(_data_root, table)
	assert_bool(
		disk_database.insert(
			&"assets",
			{&"id": 1, &"name": "Key", &"icon": icon},
		).is_successful(),
	).is_true()
	var opened := GDSQLRuntimeFactory.open_registration(
		GDSQLDatabaseRegistration.new(
			&"runtime",
			disk_database.database_name,
			_data_root,
			GDSQLStorageBackendIds.IN_MEMORY,
		),
	)

	assert_bool(opened.is_successful()).is_true()
	var memory := opened.get_database().context.storage as GDSQLInMemoryTableStorage
	var stored := memory.read_table(
		table,
		null,
		GDSQLStorageReadRequest.all(true),
	)
	assert_object(stored.rows[0].get_value(&"icon")) \
			.is_instanceof(GDSQLResourceReference)
	var changed_row := stored.rows[0].duplicate_record()
	changed_row.set_value(&"name", "Updated key")
	var session := GDSQLStorageSession.new()
	assert_bool(memory.stage_update(table, 1, changed_row, session).is_successful()).is_true()
	assert_bool(memory.commit(session).is_successful()).is_true()
	var durable := GDSQLConfigFileTableStorage.new(
		GDSQLDatabasePathResolver.new(_data_root),
		GDSQLConfigFileCache.new(),
		GDSQLGodotVariantCodec.new(),
	)
	assert_bool(GDSQLInMemoryCheckpointTarget.new(memory, durable).checkpoint().is_successful()) \
			.is_true()
	var checkpointed := durable.read_table(
		table,
		null,
		GDSQLStorageReadRequest.all(true),
	)
	assert_str(checkpointed.rows[0].get_value(&"name")).is_equal("Updated key")
	assert_object(checkpointed.rows[0].get_value(&"icon")) \
			.is_instanceof(GDSQLResourceReference)


func test_in_memory_bounded_reads_continue_without_exposing_unrequested_columns() -> void:
	var table := _heroes_table()
	var storage := GDSQLInMemoryTableStorage.new()
	var session := GDSQLStorageSession.new()
	for index in 5:
		storage.stage_insert(table, _hero(index + 1, "Hero %d" % (index + 1)), session)
	assert_bool(storage.commit(session).is_successful()).is_true()
	var base_request := GDSQLStorageReadRequest.for_columns([&"name"], true)

	var first := storage.read_batch(table, null, base_request.bounded(2))
	var second := storage.read_batch(
		table,
		null,
		base_request.bounded(2, first.get_next_cursor()),
	)
	var third := storage.read_batch(
		table,
		null,
		base_request.bounded(2, second.get_next_cursor()),
	)

	assert_bool(first.is_successful()).is_true()
	assert_int(first.rows.size()).is_equal(2)
	assert_int(second.rows.size()).is_equal(2)
	assert_int(third.rows.size()).is_equal(1)
	assert_bool(first.has_more()).is_true()
	assert_bool(second.has_more()).is_true()
	assert_bool(third.has_more()).is_false()
	assert_bool(first.rows[0].has_column(&"name")).is_true()
	assert_bool(first.rows[0].has_column(&"id")).is_false()
	assert_int(first.statistics.rows_scanned).is_equal(5)
	assert_int(first.statistics.rows_returned).is_equal(2)
	assert_bool(first.statistics.physical_read_bounded).is_false()
	var names: Array[String] = []
	for batch in [first, second, third]:
		for row in batch.rows:
			names.append(row.get_value(&"name"))
	names.sort()
	assert_array(names).contains_exactly([
		"Hero 1",
		"Hero 2",
		"Hero 3",
		"Hero 4",
		"Hero 5",
	])


func test_configfile_bounded_reads_return_compatible_batches() -> void:
	var table := _heroes_table()
	var database := TestDatabase.create_database(_data_root, table)
	TestDatabase.insert_named_heroes(
		database,
		["Knight", "Mage", "Ranger", "Rogue", "Cleric"],
	)
	var storage := database.context.storage as GDSQLConfigFileTableStorage
	var request := GDSQLStorageReadRequest.all(true)

	var first := storage.read_batch(table, null, request.bounded(3))
	var second := storage.read_batch(
		table,
		null,
		request.bounded(3, first.get_next_cursor()),
	)

	assert_bool(first.is_successful()).is_true()
	assert_int(first.rows.size()).is_equal(3)
	assert_int(second.rows.size()).is_equal(2)
	assert_bool(first.has_more()).is_true()
	assert_bool(second.has_more()).is_false()
	assert_int(first.statistics.rows_scanned).is_equal(5)
	assert_int(first.statistics.rows_returned).is_equal(3)
	assert_int(first.statistics.bytes_read).is_equal(-1)
	assert_int(first.statistics.pages_read).is_equal(-1)
	assert_bool(first.statistics.physical_read_bounded).is_false()
	var staged_session := GDSQLStorageSession.new()
	assert_bool(
		storage.stage_insert(table, _hero(6, "Paladin"), staged_session).is_successful(),
	).is_true()
	var staged_batch := storage.read_batch(
		table,
		staged_session,
		GDSQLStorageReadRequest.for_columns([&"name"], true).bounded(10),
	)
	assert_bool(staged_batch.is_successful()).is_true()
	assert_int(staged_batch.rows.size()).is_equal(6)
	assert_bool(staged_batch.rows[0].has_column(&"id")).is_false()


func test_bounded_read_rejects_a_cursor_from_another_backend() -> void:
	var table := _heroes_table()
	var storage := GDSQLInMemoryTableStorage.new()
	var request := GDSQLStorageReadRequest.all().bounded(
		2,
		GDSQLStorageReadCursor.new(
			GDSQLStorageBackendIds.CONFIG_FILE,
			table.database_name,
			table.name,
			2,
		),
	)

	var batch := storage.read_batch(table, null, request)

	assert_bool(batch.is_successful()).is_false()
	assert_str(String(batch.diagnostics.entries[0].code)).is_equal(
		"GDSQL_STORAGE_CURSOR_BACKEND_MISMATCH",
	)
	var wrong_source := GDSQLStorageReadRequest.all().bounded(
		2,
		GDSQLStorageReadCursor.new(
			GDSQLStorageBackendIds.IN_MEMORY,
			table.database_name,
			&"other_table",
			2,
		),
	)
	var source_batch := storage.read_batch(table, null, wrong_source)
	assert_bool(source_batch.is_successful()).is_false()
	assert_str(String(source_batch.diagnostics.entries[0].code)).is_equal(
		"GDSQL_STORAGE_CURSOR_SOURCE_MISMATCH",
	)


func _heroes_table() -> GDSQLTableDefinition:
	var table := GDSQLTableDefinition.new(&"heroes", &"id")
	table.database_name = &"game_config"
	table.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true))
	table.add_column(GDSQLColumnDefinition.new(&"name", TYPE_STRING, false))
	return table


func _auto_increment_heroes_table() -> GDSQLTableDefinition:
	var table := GDSQLTableDefinition.new(&"heroes", &"id")
	table.database_name = &"game_config"
	table.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true, true))
	table.add_column(GDSQLColumnDefinition.new(&"name", TYPE_STRING, false))
	return table


func _hero(id: int, name: String) -> GDSQLRowRecord:
	return GDSQLRowRecord.new({ &"id": id, &"name": name })
