class_name GDSQLForeignKeyConstraintsTest
extends GdUnitTestSuite

const TestDatabase = preload("res://tests/utils/gdsql_test_database.gd")

var _data_root: String
var _test_index := 0


func before_test() -> void:
	_test_index += 1
	_data_root = create_temp_dir("gdsql_foreign_keys_%d" % _test_index)


func test_insert_rejects_an_orphaned_reference_atomically() -> void:
	var database := _create_database()

	var inserted := database.insert(&"skills", {&"id": 10, &"hero_id": 99})

	assert_bool(inserted.is_successful()).is_false()
	assert_str(String(inserted.diagnostics.entries[0].code)).is_equal(
		"GDSQL_STORAGE_FOREIGN_KEY_VIOLATION",
	)
	assert_int(_count(database, &"skills")).is_equal(0)


func test_transaction_validates_its_final_state_in_any_statement_order() -> void:
	var database := _create_database()
	var statement_results: Array[GDSQLQueryResult] = []

	var committed := database.transaction(
		func(transaction: GDSQLTransaction) -> void:
			statement_results.append(
				transaction.execute(
					database.table(&"skills").insert().values(
						{&"id": 10, &"hero_id": 1},
					).build(),
				),
			)
			statement_results.append(
				transaction.execute(
					database.table(&"heroes").insert().values(
						{&"id": 1, &"code": "mage"},
					).build(),
				),
			),
	)

	assert_bool(committed.is_successful()).is_true()
	assert_bool(statement_results[0].is_successful()).is_true()
	assert_bool(statement_results[1].is_successful()).is_true()
	assert_int(_count(database, &"skills")).is_equal(1)


func test_delete_restricts_a_referenced_target() -> void:
	var database := _create_database_with_rows()

	var deleted := database.execute(
		database.table(&"heroes")
		.delete()
		.where(TestDatabase.id_equals(1))
		.build(),
	)

	assert_bool(deleted.is_successful()).is_false()
	assert_str(String(deleted.diagnostics.entries[0].code)).is_equal(
		"GDSQL_STORAGE_FOREIGN_KEY_VIOLATION",
	)
	assert_int(_count(database, &"heroes")).is_equal(1)


func test_transaction_can_delete_reference_before_its_target() -> void:
	var database := _create_database_with_rows()

	var committed := database.transaction(
		func(transaction: GDSQLTransaction) -> void:
			transaction.execute(
				database.table(&"heroes")
				.delete()
				.where(TestDatabase.id_equals(1))
				.build(),
			)
			transaction.execute(
				database.table(&"skills")
				.delete()
				.where(TestDatabase.id_equals(10))
				.build(),
			),
	)

	assert_bool(committed.is_successful()).is_true()
	assert_int(_count(database, &"heroes")).is_equal(0)
	assert_int(_count(database, &"skills")).is_equal(0)


func test_updates_cannot_create_orphans_on_either_side() -> void:
	var database := _create_database_with_rows()
	var child_update := database.execute(
		database.table(&"skills")
		.update()
		.set_value(&"hero_id", 99)
		.where(TestDatabase.id_equals(10))
		.build(),
	)
	var target_update := database.execute(
		database.table(&"heroes")
		.update()
		.set_value(&"code", "archmage")
		.where(TestDatabase.id_equals(1))
		.build(),
	)

	assert_bool(child_update.is_successful()).is_false()
	assert_bool(target_update.is_successful()).is_false()
	assert_str(String(child_update.diagnostics.entries[0].code)).is_equal(
		"GDSQL_STORAGE_FOREIGN_KEY_VIOLATION",
	)
	assert_str(String(target_update.diagnostics.entries[0].code)).is_equal(
		"GDSQL_STORAGE_FOREIGN_KEY_VIOLATION",
	)


func test_in_memory_runtime_enforces_the_same_constraints() -> void:
	var disk_database := _create_database()
	var context := GDSQLRuntimeFactory.create_in_memory(_data_root)
	var database := GDSQLDatabase.new(disk_database.database_name, context)

	var inserted := database.insert(&"skills", {&"id": 10, &"hero_id": 99})

	assert_bool(inserted.is_successful()).is_false()
	assert_str(String(inserted.diagnostics.entries[0].code)).is_equal(
		"GDSQL_STORAGE_FOREIGN_KEY_VIOLATION",
	)


func _create_database() -> GDSQLDatabase:
	var heroes := GDSQLTableDefinition.new(&"heroes", &"id")
	heroes.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true))
	heroes.add_column(GDSQLColumnDefinition.new(&"code", TYPE_STRING, false, true))
	var database := TestDatabase.create_database(_data_root, heroes)
	var skills := GDSQLTableDefinition.new(&"skills", &"id")
	skills.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true))
	skills.add_column(GDSQLColumnDefinition.new(&"hero_id", TYPE_INT, false))
	skills.add_column(GDSQLColumnDefinition.new(&"hero_code", TYPE_STRING, true))
	skills.add_foreign_key(
		GDSQLForeignKeyDefinition.new(
			&"skills_hero_id",
			&"hero_id",
			&"heroes",
			&"id",
		),
	)
	skills.add_foreign_key(
		GDSQLForeignKeyDefinition.new(
			&"skills_hero_code",
			&"hero_code",
			&"heroes",
			&"code",
		),
	)
	assert_bool(database.create_table(skills).is_successful()).is_true()
	return database


func _create_database_with_rows() -> GDSQLDatabase:
	var database := _create_database()
	assert_bool(
		database.insert(&"heroes", {&"id": 1, &"code": "mage"}).is_successful(),
	).is_true()
	assert_bool(
		database.insert(
			&"skills",
			{&"id": 10, &"hero_id": 1, &"hero_code": "mage"},
		).is_successful(),
	).is_true()
	return database


func _count(database: GDSQLDatabase, table_name: StringName) -> int:
	return database.execute(database.table(table_name).select().build()).get_returned_rows()
