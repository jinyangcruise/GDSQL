class_name GDSQLMigrationServiceTest
extends GdUnitTestSuite

const TestDatabase = preload("res://tests/utils/gdsql_test_database.gd")

var _data_root: String
var _test_index := 0


func before_test() -> void:
	_test_index += 1
	_data_root = create_temp_dir("gdsql_migration_service_%d" % _test_index)


func test_database_api_previews_applies_and_reports_up_to_date_history() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	TestDatabase.insert_basic_heroes(database)
	var migration := _migration("202609290001_add_level")
	var history: Array[GDSQLMigrationDefinition] = [migration]

	var preview := database.preview_migrations(history)

	assert_bool(preview.is_successful()).is_true()
	assert_bool(preview.is_up_to_date()).is_false()
	assert_object(preview.next_plan).is_not_null()
	assert_int(preview.next_plan.affected_rows()).is_equal(2)
	var applied := database.apply_migration(preview.next_plan)
	assert_bool(applied.is_successful()).is_true()
	assert_str(applied.applied_migration.migration_id).is_equal(
		migration.migration_id,
	)
	var complete := database.preview_migrations(history)
	assert_bool(complete.is_successful()).is_true()
	assert_bool(complete.is_up_to_date()).is_true()
	assert_object(complete.next_plan).is_null()
	assert_object(
		database.context.catalog.get_table(database.database_name, &"heroes") \
				.get_column(&"level"),
	).is_not_null()


func test_database_api_previews_and_applies_a_typed_row_update() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	TestDatabase.insert_basic_heroes(database)
	var assignments: Array[GDSQLColumnAssignment] = [
		GDSQLColumnAssignment.new(&"name", GDSQLLiteralExpression.new("Wizard")),
	]
	var migration := GDSQLMigrationDefinition.new(
		"202609290001_rename_mage",
		"Rename the mage",
		[
			GDSQLDataMigrationStep.new(
				&"heroes",
				assignments,
				GDSQLColumnExpression.new(&"id").equals(2),
			),
		],
	)
	var history: Array[GDSQLMigrationDefinition] = [migration]

	var preview := database.preview_migrations(history)

	assert_bool(preview.is_successful()).is_true()
	assert_bool(preview.next_plan.is_data_update()).is_true()
	assert_int(preview.next_plan.affected_rows()).is_equal(1)
	assert_bool(preview.requires_confirmation()).is_true()
	assert_array(preview.next_plan.summaries()).contains_exactly(
		["Update 1 row(s) in table 'heroes'."],
	)
	var applied := database.apply_migration(preview.next_plan)
	assert_bool(applied.is_successful()).is_true()
	var rows := database.execute(
		database.query().table(&"heroes").select().order_by_column(&"id").build(),
	)
	assert_str(rows.rows[0].get_value(&"name")).is_equal("Knight")
	assert_str(rows.rows[1].get_value(&"name")).is_equal("Wizard")
	var complete := database.preview_migrations(history)
	assert_bool(complete.is_successful()).is_true()
	assert_bool(complete.is_up_to_date()).is_true()


func test_database_api_applies_distinct_table_updates_as_one_migration() -> void:
	var heroes := GDSQLTableDefinition.new(&"heroes", &"id")
	heroes.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true))
	heroes.add_column(GDSQLColumnDefinition.new(&"name", TYPE_STRING, false))
	var quests := GDSQLTableDefinition.new(&"quests", &"id")
	quests.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true))
	quests.add_column(GDSQLColumnDefinition.new(&"status", TYPE_STRING, false))
	var database := TestDatabase.create_database_with_tables(
		_data_root,
		[heroes, quests],
	)
	TestDatabase.insert_basic_heroes(database)
	TestDatabase.insert_rows(
		database,
		[{ &"id": 1, &"status": "locked" }],
		&"quests",
	)
	var migration := GDSQLMigrationDefinition.new(
		"202609290001_unlock_content",
		"Update related authored content",
		[
			GDSQLDataMigrationStep.new(
				&"heroes",
				[
					GDSQLColumnAssignment.new(
						&"name",
						GDSQLLiteralExpression.new("Wizard"),
					),
				],
				GDSQLColumnExpression.new(&"id").equals(2),
			),
			GDSQLDataMigrationStep.new(
				&"quests",
				[
					GDSQLColumnAssignment.new(
						&"status",
						GDSQLLiteralExpression.new("available"),
					),
				],
				GDSQLColumnExpression.new(&"id").equals(1),
			),
		],
	)
	var history: Array[GDSQLMigrationDefinition] = [migration]

	var preview := database.preview_migrations(history)

	assert_bool(preview.is_successful()).is_true()
	assert_int(preview.next_plan.data_steps.size()).is_equal(2)
	assert_int(preview.next_plan.affected_rows()).is_equal(2)
	assert_array(preview.next_plan.summaries()).contains_exactly(
		[
			"Update 1 row(s) in table 'heroes'.",
			"Update 1 row(s) in table 'quests'.",
		],
	)
	assert_bool(database.apply_migration(preview.next_plan).is_successful()).is_true()
	var hero_rows := database.execute(
		database.query().table(&"heroes").select() \
				.where(GDSQLColumnExpression.new(&"id").equals(2)).build(),
	)
	var quest_rows := database.execute(
		database.query().table(&"quests").select().build(),
	)
	assert_str(hero_rows.rows[0].get_value(&"name")).is_equal("Wizard")
	assert_str(quest_rows.rows[0].get_value(&"status")).is_equal("available")
	assert_bool(database.preview_migrations(history).is_up_to_date()).is_true()
	var ledger := GDSQLConfigFileMigrationLedger.new(
		GDSQLDatabasePathResolver.new(_data_root),
	).load(database.database_name).get_value() as GDSQLMigrationLedgerSnapshot
	assert_int(ledger.records.size()).is_equal(1)


func test_database_api_applies_repeated_table_data_steps_in_order() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	TestDatabase.insert_basic_heroes(database)
	var migration := GDSQLMigrationDefinition.new(
		"202609290001_repeated_heroes",
		"Ambiguous sequential updates",
		[
			_data_name_step("Knight", 1),
			_data_name_step("Wizard", 2),
		],
	)

	var preview := database.preview_migrations([migration])

	assert_bool(preview.is_successful()).is_true()
	assert_array(preview.next_plan.data_step_affected_rows).contains_exactly([1, 1])
	assert_bool(database.apply_migration(preview.next_plan).is_successful()).is_true()
	var rows := database.execute(
		database.query().table(&"heroes").select().order_by_column(&"id").build(),
	)
	assert_str(rows.rows[0].get_value(&"name")).is_equal("Knight")
	assert_str(rows.rows[1].get_value(&"name")).is_equal("Wizard")


func test_database_api_rejects_a_plan_for_another_database() -> void:
	var source := TestDatabase.create_heroes_database(_data_root)
	var other_table := GDSQLTableDefinition.new(&"heroes", &"id")
	other_table.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true))
	other_table.add_column(GDSQLColumnDefinition.new(&"name", TYPE_STRING, false))
	var target := TestDatabase.create_database(
		_data_root,
		other_table,
		&"other_database",
	)
	var history: Array[GDSQLMigrationDefinition] = [
		_migration("202609290001_add_level"),
	]
	var preview := source.preview_migrations(history)

	var result := target.apply_migration(preview.next_plan)

	assert_bool(result.is_successful()).is_false()
	assert_str(_first_code(result)).is_equal(
		"GDSQL_MIGRATION_PLAN_DATABASE_MISMATCH",
	)


func test_database_api_adopts_verified_baseline_then_previews_only_new_history() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	var existing := _migration("202609290001_existing_schema")
	var next := GDSQLMigrationDefinition.new(
		"202609290002_add_rank",
		"Add rank",
		[
			GDSQLSchemaMigrationStep.new(
				&"heroes",
				[_add_int_column(&"rank")],
			),
		],
	)
	var history: Array[GDSQLMigrationDefinition] = [existing, next]
	var fingerprint := GDSQLSchemaFingerprint.compute(
		database.context.catalog.get_database(database.database_name),
	)
	var state := GDSQLMigrationSchemaState.from_history(
		&"heroes",
		database.database_name,
		history,
		fingerprint,
		1,
	)

	var adopted := database.adopt_migration_baseline(
		history,
		state,
	)

	assert_bool(adopted.is_successful()).is_true()
	var baseline := adopted.get_value() as GDSQLMigrationBaseline
	assert_str(baseline.through_migration_id).is_equal(existing.migration_id)
	assert_bool(baseline.is_valid()).is_true()
	var preview := database.preview_migrations(history)
	assert_bool(preview.is_successful()).is_true()
	assert_str(preview.next_plan.migration.migration_id).is_equal(next.migration_id)
	assert_int(preview.next_plan.expected_ledger_revision).is_equal(1)
	assert_bool(database.apply_migration(preview.next_plan).is_successful()).is_true()
	assert_bool(database.preview_migrations(history).is_up_to_date()).is_true()
	assert_object(
		database.context.catalog.get_table(database.database_name, &"heroes") \
				.get_column(&"rank"),
	).is_not_null()


func test_database_api_adopts_an_empty_history_origin_before_first_migration() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	var migration := _migration("202609290001_add_level")
	var history: Array[GDSQLMigrationDefinition] = [migration]
	var fingerprint := GDSQLSchemaFingerprint.compute(
		database.context.catalog.get_database(database.database_name),
	)
	var origin := GDSQLMigrationSchemaState.from_history(
		&"heroes",
		database.database_name,
		history,
		fingerprint,
		0,
	)

	assert_bool(
		database.adopt_migration_baseline(history, origin).is_successful(),
	).is_true()
	var preview := database.preview_migrations(history)
	assert_bool(preview.is_successful()).is_true()
	assert_str(preview.next_plan.migration.migration_id).is_equal(
		migration.migration_id,
	)
	assert_int(preview.next_plan.expected_ledger_revision).is_equal(1)


func test_database_api_rejects_unverified_or_repeated_baseline_adoption() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	var migration := _migration("202609290001_existing_schema")
	var history: Array[GDSQLMigrationDefinition] = [migration]
	var fingerprint := GDSQLSchemaFingerprint.compute(
		database.context.catalog.get_database(database.database_name),
	)
	var mismatch_state := GDSQLMigrationSchemaState.from_history(
		&"heroes",
		database.database_name,
		history,
		"b".repeat(64),
	)

	var mismatch := database.adopt_migration_baseline(
		history,
		mismatch_state,
	)
	assert_str(_first_code(mismatch)).is_equal(
		"GDSQL_MIGRATION_BASELINE_SCHEMA_MISMATCH",
	)
	assert_bool(
		database.adopt_migration_baseline(
			history,
			GDSQLMigrationSchemaState.from_history(
				&"heroes",
				database.database_name,
				history,
				fingerprint,
			),
		).is_successful(),
	).is_true()
	var repeated := database.adopt_migration_baseline(
		history,
		GDSQLMigrationSchemaState.from_history(
			&"heroes",
			database.database_name,
			history,
			fingerprint,
		),
	)
	assert_str(_first_code(repeated)).is_equal(
		"GDSQL_MIGRATION_BASELINE_ALREADY_ESTABLISHED",
	)


func test_database_api_detects_schema_drift_from_an_adopted_baseline() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	var migration := _migration("202609290001_existing_schema")
	var history: Array[GDSQLMigrationDefinition] = [migration]
	var fingerprint := GDSQLSchemaFingerprint.compute(
		database.context.catalog.get_database(database.database_name),
	)
	assert_bool(
		database.adopt_migration_baseline(
			history,
			GDSQLMigrationSchemaState.from_history(
				&"heroes",
				database.database_name,
				history,
				fingerprint,
			),
		).is_successful(),
	).is_true()
	assert_bool(
		database.alter_table(&"heroes", [_add_int_column(&"rank")]).is_successful(),
	).is_true()

	var preview := database.preview_migrations(history)

	assert_bool(preview.is_successful()).is_false()
	assert_str(_first_code(preview)).is_equal("GDSQL_MIGRATION_SCHEMA_DRIFT")


func test_in_memory_context_reports_migration_service_unavailable() -> void:
	var durable := TestDatabase.create_heroes_database(_data_root)
	var context := GDSQLRuntimeFactory.create_in_memory(_data_root)
	var database := GDSQLDatabase.new(durable.database_name, context)
	var history: Array[GDSQLMigrationDefinition] = [
		_migration("202609290001_add_level"),
	]

	var result := database.preview_migrations(history)

	assert_bool(result.is_successful()).is_false()
	assert_str(_first_code(result)).is_equal(
		"GDSQL_MIGRATION_SERVICE_UNAVAILABLE",
	)


func test_interrupted_uncommitted_migration_restores_verified_backup() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	TestDatabase.insert_basic_heroes(database)
	var migration_id := "202609290001_add_level"
	var recovery := _recovery_store()
	assert_bool(
		recovery.create_backup(database.database_name, migration_id).is_successful(),
	).is_true()
	var alterations: Array[GDSQLTableAlteration] = [_add_int_column(&"rank")]
	assert_bool(
		database.alter_table(&"heroes", alterations).is_successful(),
	).is_true()
	assert_bool(
		database.insert(&"heroes", { &"id": 3, &"name": "Rogue", &"rank": 4 }) \
				.is_successful(),
	).is_true()

	var result := database.recover_interrupted_migration(migration_id)

	assert_bool(result.is_successful()).is_true()
	assert_bool(result.restored_database()).is_true()
	assert_bool(result.backup_retained).is_false()
	assert_object(
		database.context.catalog.get_table(database.database_name, &"heroes") \
				.get_column(&"rank"),
	).is_null()
	var rows := database.execute(
		database.query().select().from_table(&"heroes").build(),
	)
	assert_int(rows.rows.size()).is_equal(2)


func test_startup_recovery_discovers_only_authored_migration_backups() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	var migration := _migration("202609290001_add_level")
	var history: Array[GDSQLMigrationDefinition] = [migration]
	var recovery := _recovery_store()
	assert_bool(
		recovery.create_backup(
			database.database_name,
			migration.migration_id,
		).is_successful(),
	).is_true()
	var alterations: Array[GDSQLTableAlteration] = [_add_int_column(&"rank")]
	assert_bool(
		database.alter_table(&"heroes", alterations).is_successful(),
	).is_true()

	var recovered := database.recover_pending_migrations(history)

	assert_bool(recovered.is_successful()).is_true()
	assert_array(recovered.get_value()).contains_exactly([migration.migration_id])
	assert_object(
		database.context.catalog.get_table(database.database_name, &"heroes") \
				.get_column(&"rank"),
	).is_null()
	assert_array(recovery.list_backups(database.database_name).get_value()).is_empty()


func test_interrupted_cleanup_discards_backup_for_committed_migration() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	var migration := _migration("202609290001_add_level")
	var history: Array[GDSQLMigrationDefinition] = [migration]
	var preview := database.preview_migrations(history)
	assert_bool(database.apply_migration(preview.next_plan).is_successful()).is_true()
	var recovery := _recovery_store()
	assert_bool(
		recovery.create_backup(
			database.database_name,
			migration.migration_id,
		).is_successful(),
	).is_true()
	var alterations: Array[GDSQLTableAlteration] = [_add_int_column(&"rank")]
	assert_bool(
		database.alter_table(&"heroes", alterations).is_successful(),
	).is_true()

	var result := database.recover_interrupted_migration(migration.migration_id)

	assert_bool(result.is_successful()).is_true()
	assert_bool(result.restored_database()).is_false()
	assert_int(result.status).is_equal(
		GDSQLMigrationRecoveryResult.Status.COMMITTED_BACKUP_DISCARDED,
	)
	assert_bool(result.backup_retained).is_false()
	var table := database.context.catalog.get_table(database.database_name, &"heroes")
	assert_object(table.get_column(&"level")).is_not_null()
	assert_object(table.get_column(&"rank")).is_not_null()
	var missing := recovery.load_backup(
		database.database_name,
		migration.migration_id,
	)
	assert_str(_first_code(missing)).is_equal("GDSQL_MIGRATION_BACKUP_NOT_FOUND")


func _migration(migration_id: String) -> GDSQLMigrationDefinition:
	var alterations: Array[GDSQLTableAlteration] = [_add_int_column(&"level")]
	var steps: Array[GDSQLSchemaMigrationStep] = [
		GDSQLSchemaMigrationStep.new(&"heroes", alterations),
	]
	return GDSQLMigrationDefinition.new(
		migration_id,
		"Migration %s" % migration_id,
		steps,
	)


func _data_name_step(value: String, id: int) -> GDSQLDataMigrationStep:
	return GDSQLDataMigrationStep.new(
		&"heroes",
		[
			GDSQLColumnAssignment.new(
				&"name",
				GDSQLLiteralExpression.new(value),
			),
		],
		GDSQLColumnExpression.new(&"id").equals(id),
	)


func _add_int_column(column_name: StringName) -> GDSQLTableAlteration:
	return GDSQLTableAlteration.add_column(
		GDSQLColumnDefinition.new(
			column_name,
			TYPE_INT,
			false,
			false,
			false,
			1,
		),
	)


func _recovery_store() -> GDSQLConfigFileMigrationRecoveryStore:
	return GDSQLConfigFileMigrationRecoveryStore.new(
		GDSQLDatabasePathResolver.new(_data_root),
		GDSQLConfigFileCache.new(),
	)


func _first_code(result: GDSQLOperationResult) -> String:
	return String(result.diagnostics.entries[0].code)
