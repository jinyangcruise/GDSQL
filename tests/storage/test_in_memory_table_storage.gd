class_name GDSQLInMemoryTableStorageTest
extends GdUnitTestSuite

const TestDatabase = preload("res://tests/utils/gdsql_test_database.gd")

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


func _heroes_table() -> GDSQLTableDefinition:
	var table := GDSQLTableDefinition.new(&"heroes", &"id")
	table.database_name = &"game_config"
	table.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true))
	table.add_column(GDSQLColumnDefinition.new(&"name", TYPE_STRING, false))
	return table


func _hero(id: int, name: String) -> GDSQLRowRecord:
	return GDSQLRowRecord.new({ &"id": id, &"name": name })
