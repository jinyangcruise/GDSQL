class_name GDSQLTransactionsTest
extends GdUnitTestSuite

const TestDatabase = preload("res://tests/utils/gdsql_test_database.gd")

var _data_root: String
var _test_index := 0


func before_test() -> void:
	_test_index += 1
	_data_root = create_temp_dir("gdsql_transactions_%d" % _test_index)


func test_successful_callback_commits_all_statements() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	var statement_results: Array[GDSQLQueryResult] = []

	var result := database.transaction(
		func(transaction: GDSQLTransaction) -> void:
			statement_results.append(
				transaction.execute(_insert_hero(database, 1, "Knight")),
			)
			statement_results.append(
				transaction.execute(_insert_hero(database, 2, "Mage")),
			),
	)

	assert_bool(result.is_successful()).is_true()
	assert_int(statement_results.size()).is_equal(2)
	assert_bool(statement_results[0].is_successful()).is_true()
	assert_bool(statement_results[1].is_successful()).is_true()
	var reopened := GDSQLDatabase.open(&"game_config", _data_root).get_database()
	assert_int(_select_all(reopened).get_returned_rows()).is_equal(2)


func test_successful_callback_commits_all_statements_separated_returns() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	var cap := {
		"r1": null,
		"r2": null,
	}

	var result := database.transaction(
		func(transaction: GDSQLTransaction) -> void:
			cap.r1 = transaction.execute(_insert_hero(database, 1, "Knight"))
			cap.r2 = transaction.execute(_insert_hero(database, 2, "Mage"))
	)

	assert_bool(result.is_successful()).is_true()
	assert_bool(cap.r1.is_successful()).is_true()
	assert_bool(cap.r2.is_successful()).is_true()
	var reopened := GDSQLDatabase.open(&"game_config", _data_root).get_database()
	assert_int(_select_all(reopened).get_returned_rows()).is_equal(2)


func test_failed_statement_rolls_back_every_staged_change() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	var statement_results: Array[GDSQLQueryResult] = []

	var result := database.transaction(
		func(transaction: GDSQLTransaction) -> void:
			statement_results.append(
				transaction.execute(_insert_hero(database, 1, "Knight")),
			)
			statement_results.append(
				transaction.execute(_insert_hero(database, 1, "Mage")),
			)
			statement_results.append(
				transaction.execute(_select_all_spec(database)),
			),
	)

	assert_bool(result.is_successful()).is_false()
	assert_bool(statement_results[0].is_successful()).is_true()
	assert_str(String(statement_results[1].diagnostics.entries[0].code)).is_equal(
		"GDSQL_STORAGE_DUPLICATE_PRIMARY_KEY",
	)
	assert_str(String(statement_results[2].diagnostics.entries[0].code)).is_equal(
		"GDSQL_TRANSACTION_ABORTED",
	)
	assert_int(_select_all(database).get_returned_rows()).is_equal(0)


func test_reads_and_updates_observe_earlier_staged_writes() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	var statement_results: Array[GDSQLQueryResult] = []

	var result := database.transaction(
		func(transaction: GDSQLTransaction) -> void:
			statement_results.append(
				transaction.execute(_insert_hero(database, 1, "Knight")),
			)
			statement_results.append(
				transaction.execute(
					database.table(&"heroes")
					.update()
					.set_value(&"name", "Paladin")
					.where(TestDatabase.id_equals(1))
					.build(),
				),
			)
			statement_results.append(
				transaction.execute(
					database.table(&"heroes")
					.select()
					.where(TestDatabase.id_equals(1))
					.build(),
				),
			),
	)

	assert_bool(result.is_successful()).is_true()
	assert_int(statement_results[1].get_affected_rows()).is_equal(1)
	assert_int(statement_results[2].get_returned_rows()).is_equal(1)
	assert_str(statement_results[2].rows[0].get_value(&"name")).is_equal(
		"Paladin",
	)
	assert_str(_select_all(database).rows[0].get_value(&"name")).is_equal(
		"Paladin",
	)


func test_commit_constraint_failure_rolls_back_all_statements() -> void:
	var table := GDSQLTableDefinition.new(&"accounts", &"id")
	table.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true))
	table.add_column(GDSQLColumnDefinition.new(&"email", TYPE_STRING, false, true))
	var database := TestDatabase.create_database(_data_root, table)
	var statement_results: Array[GDSQLQueryResult] = []

	var result := database.transaction(
		func(transaction: GDSQLTransaction) -> void:
			statement_results.append(
				transaction.execute(
					database.table(&"accounts").insert().values(
						{ &"id": 1, &"email": "shared@example.test" },
					).build(),
				),
			)
			statement_results.append(
				transaction.execute(
					database.table(&"accounts").insert().values(
						{ &"id": 2, &"email": "shared@example.test" },
					).build(),
				),
			),
	)

	assert_bool(statement_results[0].is_successful()).is_true()
	assert_bool(statement_results[1].is_successful()).is_true()
	assert_bool(result.is_successful()).is_false()
	assert_str(String(result.diagnostics.entries[0].code)).is_equal(
		"GDSQL_STORAGE_DUPLICATE_UNIQUE_VALUE",
	)
	assert_int(
		database.execute(
			database.table(&"accounts").select().build(),
		).get_returned_rows(),
	).is_equal(0)


func test_transaction_scope_cannot_be_reused_after_callback() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	var captured: Array[GDSQLTransaction] = []
	var result := database.transaction(
		func(transaction: GDSQLTransaction) -> void:
			captured.append(transaction),
	)

	assert_bool(result.is_successful()).is_true()
	var closed_result := captured[0].execute(_select_all_spec(database))
	assert_bool(closed_result.is_successful()).is_false()
	assert_str(String(closed_result.diagnostics.entries[0].code)).is_equal(
		"GDSQL_TRANSACTION_CLOSED",
	)


func _insert_hero(
		database: GDSQLDatabase,
		id: int,
		name: String,
) -> GDSQLInsertQuerySpec:
	return database.table(&"heroes").insert().values(
		{ &"id": id, &"name": name },
	).build()


func _select_all_spec(database: GDSQLDatabase) -> GDSQLSelectQuerySpec:
	return database.table(&"heroes").select().build()


func _select_all(database: GDSQLDatabase) -> GDSQLQueryResult:
	return database.execute(_select_all_spec(database))
