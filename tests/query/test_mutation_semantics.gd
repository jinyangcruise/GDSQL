class_name GDSQLMutationSemanticsTest
extends GdUnitTestSuite

const TestDatabase = preload("res://tests/utils/gdsql_test_database.gd")
const TestResource = preload("res://tests/fixtures/gdsql_test_resource.gd")

var _data_root: String
var _test_index := 0


func before_test() -> void:
	_test_index += 1
	_data_root = create_temp_dir("gdsql_mutation_semantics_%d" % _test_index)


func test_multi_row_insert_rejects_duplicate_unique_values_atomically() -> void:
	var database := _create_accounts_database()
	var result := database.execute(
		database.table(&"accounts")
		.insert()
		.values({ &"id": 1, &"email": "mage@example.test" })
		.values({ &"id": 2, &"email": "mage@example.test" })
		.build(),
	)

	assert_bool(result.is_successful()).is_false()
	assert_str(String(result.diagnostics.entries[0].code)).is_equal(
		"GDSQL_STORAGE_DUPLICATE_UNIQUE_VALUE",
	)
	assert_int(_select_all(database).get_returned_rows()).is_equal(0)


func test_insert_rejects_a_unique_value_already_in_storage() -> void:
	var database := _create_accounts_database()
	TestDatabase.insert_rows(
		database,
		[{ &"id": 1, &"email": "mage@example.test" }],
		&"accounts",
	)

	var result := database.insert(
		&"accounts",
		{ &"id": 2, &"email": "mage@example.test" },
	)

	assert_bool(result.is_successful()).is_false()
	assert_str(String(result.diagnostics.entries[0].code)).is_equal(
		"GDSQL_STORAGE_DUPLICATE_UNIQUE_VALUE",
	)
	assert_int(_select_all(database).get_returned_rows()).is_equal(1)


func test_multi_row_update_rolls_back_when_final_state_is_not_unique() -> void:
	var database := _create_accounts_database()
	TestDatabase.insert_rows(
		database,
		[
			{ &"id": 1, &"email": "mage@example.test" },
			{ &"id": 2, &"email": "knight@example.test" },
		],
		&"accounts",
	)

	var result := database.execute(
		database.table(&"accounts")
		.update()
		.set_value(&"email", "shared@example.test")
		.build(),
	)

	assert_bool(result.is_successful()).is_false()
	assert_str(String(result.diagnostics.entries[0].code)).is_equal(
		"GDSQL_STORAGE_DUPLICATE_UNIQUE_VALUE",
	)
	var rows := _select_all(database)
	assert_bool(rows.is_successful()).is_true()
	assert_str(rows.rows[0].get_value(&"email")).is_equal("mage@example.test")
	assert_str(rows.rows[1].get_value(&"email")).is_equal("knight@example.test")


func test_nullable_unique_column_allows_multiple_null_values() -> void:
	var table := GDSQLTableDefinition.new(&"accounts", &"id")
	table.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true))
	table.add_column(GDSQLColumnDefinition.new(&"nickname", TYPE_STRING, true, true))
	var database := TestDatabase.create_database(_data_root, table)

	var result := database.execute(
		database.table(&"accounts")
		.insert()
		.values({ &"id": 1, &"nickname": null })
		.values({ &"id": 2, &"nickname": null })
		.build(),
	)

	assert_bool(result.is_successful()).is_true()
	assert_int(result.get_affected_rows()).is_equal(2)


func test_insert_applies_static_and_explicit_null_defaults() -> void:
	var table := GDSQLTableDefinition.new(&"profiles", &"id")
	table.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true))
	table.add_column(
		GDSQLColumnDefinition.new(
			&"status",
			TYPE_STRING,
			false,
			false,
			false,
			"active",
		),
	)
	table.add_column(
		GDSQLColumnDefinition.new(
			&"nickname",
			TYPE_STRING,
			true,
		).set_default(null),
	)
	var database := TestDatabase.create_database(_data_root, table)

	var result := database.insert(&"profiles", { &"id": 1 })

	assert_bool(result.is_successful()).is_true()
	assert_str(result.rows[0].get_value(&"status")).is_equal("active")
	assert_bool(result.rows[0].has_column(&"nickname")).is_true()
	assert_object(result.rows[0].get_value(&"nickname")).is_null()
	var reopened := GDSQLDatabase.open(&"game_config", _data_root).get_database()
	var stored := reopened.execute(
		reopened.table(&"profiles").select().build(),
	)
	assert_bool(stored.rows[0].has_column(&"nickname")).is_true()
	assert_object(stored.rows[0].get_value(&"nickname")).is_null()


func test_auto_increment_generates_batch_ids_and_updates_table_metadata() -> void:
	var database := _create_auto_increment_accounts_database()

	var result := database.execute(
		database.table(&"accounts")
		.insert()
		.values({ &"email": "mage@example.test" })
		.values({ &"email": "knight@example.test" })
		.build(),
	)

	assert_bool(result.is_successful()).is_true()
	assert_int(result.rows[0].get_value(&"id")).is_equal(1)
	assert_int(result.rows[1].get_value(&"id")).is_equal(2)
	var metadata := _load_accounts_metadata()
	assert_int(metadata["row_count"]).is_equal(2)
	assert_int(metadata["next_auto_increment"]).is_equal(3)


func test_auto_increment_advances_past_explicit_ids_and_does_not_reuse_deleted_ids() -> void:
	var database := _create_auto_increment_accounts_database()
	assert_bool(
		database.insert(
			&"accounts",
			{ &"id": 10, &"email": "mage@example.test" },
		).is_successful(),
	).is_true()
	var generated := database.insert(
		&"accounts",
		{ &"email": "knight@example.test" },
	)
	assert_int(generated.rows[0].get_value(&"id")).is_equal(11)
	assert_bool(
		database.execute(
			database.table(&"accounts")
			.delete()
			.where(TestDatabase.id_equals(11))
			.build(),
		).is_successful(),
	).is_true()

	var after_delete := database.insert(
		&"accounts",
		{ &"email": "rogue@example.test" },
	)

	assert_bool(after_delete.is_successful()).is_true()
	assert_int(after_delete.rows[0].get_value(&"id")).is_equal(12)
	var metadata := _load_accounts_metadata()
	assert_int(metadata["row_count"]).is_equal(2)
	assert_int(metadata["next_auto_increment"]).is_equal(13)


func test_failed_batch_does_not_advance_auto_increment_sequence() -> void:
	var database := _create_auto_increment_accounts_database()
	var failed := database.execute(
		database.table(&"accounts")
		.insert()
		.values({ &"email": "shared@example.test" })
		.values({ &"email": "shared@example.test" })
		.build(),
	)
	assert_bool(failed.is_successful()).is_false()

	var successful := database.insert(
		&"accounts",
		{ &"email": "mage@example.test" },
	)

	assert_bool(successful.is_successful()).is_true()
	assert_int(successful.rows[0].get_value(&"id")).is_equal(1)


func test_timestamp_helpers_generate_created_at_and_updated_at() -> void:
	var table := GDSQLTableDefinition.new(&"accounts", &"id")
	table.add_column(
		GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true, true),
	)
	table.add_column(GDSQLColumnDefinition.new(&"email", TYPE_STRING, false))
	table.add_timestamps()
	var database := TestDatabase.create_database(_data_root, table)
	var inserted := database.insert(
		&"accounts",
		{ &"email": "mage@example.test" },
	)
	var created_at: int = inserted.rows[0].get_value(&"created_at")
	var initial_updated_at: int = inserted.rows[0].get_value(&"updated_at")

	var updated := database.execute(
		database.table(&"accounts")
		.update()
		.set_value(&"email", "archmage@example.test")
		.build(),
	)

	assert_bool(updated.is_successful()).is_true()
	assert_int(updated.rows[0].get_value(&"created_at")).is_equal(created_at)
	assert_int(updated.rows[0].get_value(&"updated_at")).is_greater_equal(
		initial_updated_at,
	)
	var reopened := GDSQLDatabase.open(&"game_config", _data_root).get_database()
	var stored := reopened.execute(
		reopened.table(&"accounts").select().build(),
	)
	assert_int(stored.rows[0].get_value(&"created_at")).is_equal(created_at)
	assert_int(stored.rows[0].get_value(&"updated_at")).is_equal(
		updated.rows[0].get_value(&"updated_at"),
	)


func test_generated_timestamps_cannot_be_assigned_directly() -> void:
	var table := GDSQLTableDefinition.new(&"accounts", &"id")
	table.add_column(
		GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true, true),
	)
	table.add_column(GDSQLColumnDefinition.new(&"email", TYPE_STRING, false, true))
	table.add_timestamps()
	var database := TestDatabase.create_database(_data_root, table)
	var insert_result := database.insert(
		&"accounts",
		{
			&"email": "mage@example.test",
			&"created_at": 0,
		},
	)

	assert_bool(insert_result.is_successful()).is_false()
	assert_str(String(insert_result.diagnostics.entries[0].code)).is_equal(
		"GDSQL_VALIDATION_GENERATED_COLUMN_INSERT",
	)
	var update_result := database.execute(
		database.table(&"accounts")
		.update()
		.set_value(&"updated_at", 0)
		.build(),
	)

	assert_bool(update_result.is_successful()).is_false()
	assert_str(String(update_result.diagnostics.entries[0].code)).is_equal(
		"GDSQL_VALIDATION_GENERATED_COLUMN_UPDATE",
	)


func test_object_columns_accept_resources_and_reject_nodes() -> void:
	var custom_resource := TestResource.new()
	custom_resource.label = "custom"
	var table := GDSQLTableDefinition.new(&"assets", &"id")
	table.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true))
	table.add_column(
		GDSQLColumnDefinition.new(
			&"payload",
			TYPE_OBJECT,
			false,
		).set_default(custom_resource),
	)
	var database := TestDatabase.create_database(_data_root, table)
	assert_bool(database.insert(&"assets", {&"id": 1}).is_successful()).is_true()
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color.RED, Color.BLUE])
	assert_bool(
		database.insert(
			&"assets",
			{&"id": 2, &"payload": gradient},
		).is_successful(),
	).is_true()
	var node := Node.new()
	var rejected := database.insert(
		&"assets",
		{&"id": 3, &"payload": node},
	)
	node.free()

	assert_bool(rejected.is_successful()).is_false()
	assert_str(String(rejected.diagnostics.entries[0].code)).is_equal(
		"GDSQL_VALIDATION_TYPE_MISMATCH",
	)
	var reopened := GDSQLDatabase.open(&"game_config", _data_root).get_database()
	var stored := reopened.execute(
		reopened.table(&"assets").select().order_by_column(&"id").build(),
	)
	var stored_custom: Resource = stored.rows[0].get_value(&"payload")
	var stored_gradient: Resource = stored.rows[1].get_value(&"payload")
	assert_object(stored_custom).is_instanceof(TestResource)
	assert_str(stored_custom.get("label")).is_equal("custom")
	assert_object(stored_gradient).is_instanceof(Gradient)
	assert_array(Array(stored_gradient.get("colors"))).is_equal(
		Array([Color.RED, Color.BLUE]),
	)


func _create_accounts_database() -> GDSQLDatabase:
	var table := GDSQLTableDefinition.new(&"accounts", &"id")
	table.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true))
	table.add_column(GDSQLColumnDefinition.new(&"email", TYPE_STRING, false, true))
	return TestDatabase.create_database(_data_root, table)


func _create_auto_increment_accounts_database() -> GDSQLDatabase:
	var table := GDSQLTableDefinition.new(&"accounts", &"id")
	table.add_column(
		GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true, true),
	)
	table.add_column(GDSQLColumnDefinition.new(&"email", TYPE_STRING, false, true))
	return TestDatabase.create_database(_data_root, table)


func _load_accounts_metadata() -> Dictionary:
	var config := ConfigFile.new()
	assert_int(
		config.load(
			_data_root.path_join("game_config/tables/accounts.cfg"),
		),
	).is_equal(OK)
	return {
		"row_count": config.get_value("__gdsql_metadata__", "row_count"),
		"next_auto_increment": config.get_value(
			"__gdsql_metadata__",
			"next_auto_increment",
		),
	}


func _select_all(database: GDSQLDatabase) -> GDSQLQueryResult:
	return database.execute(
		database.table(&"accounts").select().order_by_column(&"id").build(),
	)
