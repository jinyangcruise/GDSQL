class_name GDSQLConfigFileTableDataTransactionTest
extends GdUnitTestSuite

const TestDatabase = preload("res://tests/utils/gdsql_test_database.gd")

var _data_root: String
var _test_index := 0


class FailSecondActivationTransaction:
	extends GDSQLConfigFileTableDataTransaction

	var activation_count := 0


	func _rename(source: String, destination: String) -> Error:
		if source.ends_with(BUILDING_SUFFIX) and destination.ends_with(".cfg"):
			activation_count += 1
			if activation_count == 2:
				return ERR_CANT_CREATE
		return super._rename(source, destination)


func before_test() -> void:
	_test_index += 1
	_data_root = create_temp_dir("gdsql_table_data_transaction_%d" % _test_index)


func test_storage_commit_activates_multiple_table_snapshots_together() -> void:
	var database := TestDatabase.create_database_with_tables(
		_data_root,
		[_heroes_table(), _quests_table()],
	)
	var heroes := database.context.catalog.get_table(database.database_name, &"heroes")
	var quests := database.context.catalog.get_table(database.database_name, &"quests")
	var storage := database.context.storage as GDSQLConfigFileTableStorage
	var session := GDSQLStorageSession.new()
	assert_bool(storage.stage_insert(heroes, _hero(1, "Knight"), session).is_successful()) \
			.is_true()
	assert_bool(storage.stage_insert(quests, _quest(1, "First quest"), session).is_successful()) \
			.is_true()

	var committed := storage.commit(session)

	assert_bool(committed.is_successful()).is_true()
	var reopened := GDSQLDatabase.open(database.database_name, _data_root).get_database()
	assert_str(_first_value(reopened, &"heroes", &"name")).is_equal("Knight")
	assert_str(_first_value(reopened, &"quests", &"title")).is_equal("First quest")
	_assert_no_recovery_artifacts(database.database_name, [&"heroes", &"quests"])


func test_failed_multi_table_activation_restores_every_previous_file() -> void:
	var database := TestDatabase.create_database_with_tables(
		_data_root,
		[_heroes_table(), _quests_table()],
	)
	assert_bool(database.insert(&"heroes", {&"id": 1, &"name": "Knight"}).is_successful()) \
			.is_true()
	assert_bool(database.insert(&"quests", {&"id": 1, &"title": "First quest"}).is_successful()) \
			.is_true()
	var resolver := GDSQLDatabasePathResolver.new(_data_root)
	var cache := GDSQLConfigFileCache.new()
	var transaction := FailSecondActivationTransaction.new(resolver, cache)
	var storage := GDSQLConfigFileTableStorage.new(
		resolver,
		cache,
		GDSQLGodotVariantCodec.new(),
		transaction,
	)
	var heroes := database.context.catalog.get_table(database.database_name, &"heroes")
	var quests := database.context.catalog.get_table(database.database_name, &"quests")
	var session := GDSQLStorageSession.new()
	assert_bool(storage.stage_update(heroes, 1, _hero(1, "Mage"), session).is_successful()) \
			.is_true()
	assert_bool(storage.stage_update(quests, 1, _quest(1, "Changed quest"), session).is_successful()) \
			.is_true()

	var committed := storage.commit(session)

	assert_bool(committed.is_successful()).is_false()
	assert_str(String(committed.diagnostics.entries[-1].code)).is_equal(
		"GDSQL_STORAGE_TRANSACTION_ACTIVATION_FAILED",
	)
	var reopened := GDSQLDatabase.open(database.database_name, _data_root).get_database()
	assert_str(_first_value(reopened, &"heroes", &"name")).is_equal("Knight")
	assert_str(_first_value(reopened, &"quests", &"title")).is_equal("First quest")
	_assert_no_recovery_artifacts(database.database_name, [&"heroes", &"quests"])


func test_reopen_rolls_back_a_preparing_table_data_commit() -> void:
	var database := TestDatabase.create_database_with_tables(
		_data_root,
		[_heroes_table(), _quests_table()],
	)
	assert_bool(database.insert(&"heroes", {&"id": 1, &"name": "Knight"}).is_successful()) \
			.is_true()
	assert_bool(database.insert(&"quests", {&"id": 1, &"title": "First quest"}).is_successful()) \
			.is_true()
	var resolver := GDSQLDatabasePathResolver.new(_data_root)
	var database_name := database.database_name
	var table_names: Array[StringName] = [&"heroes", &"quests"]
	for table_name in table_names:
		var active_path := resolver.resolve_table_path(database_name, table_name)
		var replacement := ConfigFile.new()
		assert_int(replacement.load(active_path)).is_equal(OK)
		var value_key := "name" if table_name == &"heroes" else "title"
		replacement.set_value("1", value_key, "Interrupted replacement")
		assert_int(
			replacement.save(
				active_path + GDSQLConfigFileTableDataTransaction.BUILDING_SUFFIX,
			),
		).is_equal(OK)
	var marker_root := resolver.resolve_table_data_transaction_root(database_name)
	assert_int(
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(marker_root)),
	).is_equal(OK)
	var marker := ConfigFile.new()
	marker.set_value(
		GDSQLConfigFileTableDataTransaction.TRANSACTION_SECTION,
		"format",
		GDSQLConfigFileTableDataTransaction.FORMAT_VERSION,
	)
	marker.set_value(
		GDSQLConfigFileTableDataTransaction.TRANSACTION_SECTION,
		"database",
		String(database_name),
	)
	marker.set_value(
		GDSQLConfigFileTableDataTransaction.TRANSACTION_SECTION,
		"tables",
		PackedStringArray(table_names),
	)
	var marker_path := marker_root.path_join(
		GDSQLConfigFileTableDataTransaction.MARKER_FILE \
				+ GDSQLConfigFileTableDataTransaction.PREPARING_SUFFIX,
	)
	assert_int(marker.save(marker_path)).is_equal(OK)
	for table_name in table_names:
		var active_path := resolver.resolve_table_path(database_name, table_name)
		assert_int(
			_rename_file(
				active_path,
				active_path + GDSQLConfigFileTableDataTransaction.PREVIOUS_SUFFIX,
			),
		).is_equal(OK)
	var first_path := resolver.resolve_table_path(database_name, table_names[0])
	assert_int(
		_rename_file(
			first_path + GDSQLConfigFileTableDataTransaction.BUILDING_SUFFIX,
			first_path,
		),
	).is_equal(OK)

	var reopened := GDSQLDatabase.open(database_name, _data_root).get_database()

	assert_object(reopened).is_not_null()
	assert_str(_first_value(reopened, &"heroes", &"name")).is_equal("Knight")
	assert_str(_first_value(reopened, &"quests", &"title")).is_equal("First quest")
	_assert_no_recovery_artifacts(database_name, table_names)


func test_reopen_finishes_cleanup_after_the_commit_point() -> void:
	var database := TestDatabase.create_database_with_tables(
		_data_root,
		[_heroes_table(), _quests_table()],
	)
	assert_bool(database.insert(&"heroes", {&"id": 1, &"name": "Knight"}).is_successful()) \
			.is_true()
	assert_bool(database.insert(&"quests", {&"id": 1, &"title": "First quest"}).is_successful()) \
			.is_true()
	var resolver := GDSQLDatabasePathResolver.new(_data_root)
	var database_name := database.database_name
	var table_names: Array[StringName] = [&"heroes", &"quests"]
	for table_name in table_names:
		var active_path := resolver.resolve_table_path(database_name, table_name)
		var replacement := ConfigFile.new()
		assert_int(replacement.load(active_path)).is_equal(OK)
		var value_key := "name" if table_name == &"heroes" else "title"
		replacement.set_value("1", value_key, "Committed replacement")
		var building_path := active_path \
				+ GDSQLConfigFileTableDataTransaction.BUILDING_SUFFIX
		assert_int(replacement.save(building_path)).is_equal(OK)
		assert_int(
			_rename_file(
				active_path,
				active_path + GDSQLConfigFileTableDataTransaction.PREVIOUS_SUFFIX,
			),
		).is_equal(OK)
		assert_int(_rename_file(building_path, active_path)).is_equal(OK)
	var marker_root := resolver.resolve_table_data_transaction_root(database_name)
	assert_int(
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(marker_root)),
	).is_equal(OK)
	var marker := ConfigFile.new()
	marker.set_value(
		GDSQLConfigFileTableDataTransaction.TRANSACTION_SECTION,
		"format",
		GDSQLConfigFileTableDataTransaction.FORMAT_VERSION,
	)
	marker.set_value(
		GDSQLConfigFileTableDataTransaction.TRANSACTION_SECTION,
		"database",
		String(database_name),
	)
	marker.set_value(
		GDSQLConfigFileTableDataTransaction.TRANSACTION_SECTION,
		"tables",
		PackedStringArray(table_names),
	)
	assert_int(
		marker.save(
			marker_root.path_join(
				GDSQLConfigFileTableDataTransaction.MARKER_FILE \
						+ GDSQLConfigFileTableDataTransaction.COMMITTED_SUFFIX,
			),
		),
	).is_equal(OK)

	var reopened := GDSQLDatabase.open(database_name, _data_root).get_database()

	assert_object(reopened).is_not_null()
	assert_str(_first_value(reopened, &"heroes", &"name")).is_equal(
		"Committed replacement",
	)
	assert_str(_first_value(reopened, &"quests", &"title")).is_equal(
		"Committed replacement",
	)
	_assert_no_recovery_artifacts(database_name, table_names)


func _heroes_table() -> GDSQLTableDefinition:
	var table := GDSQLTableDefinition.new(&"heroes", &"id")
	table.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true))
	table.add_column(GDSQLColumnDefinition.new(&"name", TYPE_STRING, false))
	return table


func _quests_table() -> GDSQLTableDefinition:
	var table := GDSQLTableDefinition.new(&"quests", &"id")
	table.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true))
	table.add_column(GDSQLColumnDefinition.new(&"title", TYPE_STRING, false))
	return table


func _hero(identity: int, name: String) -> GDSQLRowRecord:
	return GDSQLRowRecord.new({&"id": identity, &"name": name})


func _quest(identity: int, title: String) -> GDSQLRowRecord:
	return GDSQLRowRecord.new({&"id": identity, &"title": title})


func _first_value(
		database: GDSQLDatabase,
		table_name: StringName,
		column_name: StringName,
) -> String:
	var selected := database.execute(database.table(table_name).select().build())
	assert_bool(selected.is_successful()).is_true()
	assert_int(selected.rows.size()).is_equal(1)
	return String(selected.rows[0].get_value(column_name))


func _assert_no_recovery_artifacts(
		database_name: StringName,
		table_names: Array[StringName],
) -> void:
	var resolver := GDSQLDatabasePathResolver.new(_data_root)
	for table_name in table_names:
		var path := resolver.resolve_table_path(database_name, table_name)
		assert_bool(
			FileAccess.file_exists(
				path + GDSQLConfigFileTableDataTransaction.BUILDING_SUFFIX,
			),
		).is_false()
		assert_bool(
			FileAccess.file_exists(
				path + GDSQLConfigFileTableDataTransaction.PREVIOUS_SUFFIX,
			),
		).is_false()
	var marker_root := resolver.resolve_table_data_transaction_root(database_name)
	assert_bool(
		FileAccess.file_exists(
			marker_root.path_join(
				GDSQLConfigFileTableDataTransaction.MARKER_FILE \
						+ GDSQLConfigFileTableDataTransaction.PREPARING_SUFFIX,
			),
		),
	).is_false()
	assert_bool(
		FileAccess.file_exists(
			marker_root.path_join(
				GDSQLConfigFileTableDataTransaction.MARKER_FILE \
						+ GDSQLConfigFileTableDataTransaction.COMMITTED_SUFFIX,
			),
		),
	).is_false()


func _rename_file(source: String, destination: String) -> Error:
	return DirAccess.rename_absolute(
		ProjectSettings.globalize_path(source),
		ProjectSettings.globalize_path(destination),
	)
