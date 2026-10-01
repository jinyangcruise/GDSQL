class_name GDSQLMigrationsTest
extends GdUnitTestSuite

const TestDatabase = preload("res://tests/utils/gdsql_test_database.gd")

var _data_root: String
var _test_index := 0


class FailingAppendLedger:
	extends GDSQLMigrationLedger

	var snapshot := GDSQLMigrationLedgerSnapshot.new()


	func load(_database_name: StringName) -> GDSQLOperationResult:
		var result := GDSQLOperationResult.new()
		result.value = snapshot
		return result


	func append(
			_database_name: StringName,
			_record: GDSQLAppliedMigration,
			_expected_ledger_revision: int,
	) -> GDSQLOperationResult:
		var result := GDSQLOperationResult.new()
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_TEST_LEDGER_APPEND_FAILED",
				"Forced ledger append failure.",
			),
		)
		return result


	func adopt_baseline(
			_database_name: StringName,
			_baseline: GDSQLMigrationBaseline,
			_expected_ledger_revision: int,
	) -> GDSQLOperationResult:
		var result := GDSQLOperationResult.new()
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_TEST_BASELINE_ADOPTION_FAILED",
				"Forced baseline adoption failure.",
			),
		)
		return result


class ConfigMigrationHarness:
	extends RefCounted

	var catalog: GDSQLCatalogService
	var administration: GDSQLCatalogAdministrationService
	var ledger: GDSQLMigrationLedger
	var recovery: GDSQLMigrationRecoveryStore
	var runner: GDSQLMigrationRunner


	func _init(data_root: String) -> void:
		var resolver := GDSQLDatabasePathResolver.new(data_root)
		var cache := GDSQLConfigFileCache.new()
		var codec := GDSQLGodotVariantCodec.new()
		catalog = GDSQLConfigFileCatalogService.new(resolver, codec)
		administration = GDSQLConfigFileCatalogAdministrationService.new(
			resolver,
			catalog,
			cache,
			codec,
		)
		ledger = GDSQLConfigFileMigrationLedger.new(resolver)
		recovery = GDSQLConfigFileMigrationRecoveryStore.new(resolver, cache)
		runner = GDSQLMigrationRunner.new(
			catalog,
			administration,
			ledger,
			recovery,
		)


	func preview(
			database_name: StringName,
			history: Array[GDSQLMigrationDefinition],
	) -> GDSQLMigrationStepPlan:
		var loaded := ledger.load(database_name)
		assert(loaded.is_successful())
		var planned := GDSQLMigrationPlanner.new().plan(
			history,
			loaded.get_value(),
		)
		assert(planned.is_successful())
		var previewed := GDSQLMigrationStepPlanner.new(administration).preview_next(
			database_name,
			planned.get_value(),
		)
		assert(previewed.is_successful())
		return previewed.get_value() as GDSQLMigrationStepPlan


func before_test() -> void:
	_test_index += 1
	_data_root = create_temp_dir("gdsql_migrations_%d" % _test_index)


func test_checksum_is_stable_and_detects_authored_history_changes() -> void:
	var first := _migration("202609280001_add_level")
	var second := _migration("202609280001_add_level")

	assert_str(first.checksum).is_equal(second.checksum)
	assert_int(first.checksum.length()).is_equal(64)
	assert_bool(first.is_valid()).is_true()

	var first_step := first.steps[0] as GDSQLSchemaMigrationStep
	first_step.alterations[0].column.name = &"rank"

	assert_bool(first.has_valid_checksum()).is_false()
	assert_bool(first.is_valid()).is_false()


func test_planner_returns_only_the_unapplied_ordered_suffix() -> void:
	var first := _migration("202609280001_add_level")
	var second := _migration(
		"202609280002_drop_legacy",
		GDSQLTableAlteration.drop_column(&"legacy"),
	)
	var ledger := GDSQLMigrationLedgerSnapshot.new(
		[
			GDSQLAppliedMigration.new(
				first.migration_id,
				first.checksum,
				1,
				_valid_fingerprint("a"),
			),
		],
	)

	var result := GDSQLMigrationPlanner.new().plan([first, second], ledger)

	assert_bool(result.is_successful()).is_true()
	var plan := result.get_value() as GDSQLMigrationPlan
	assert_int(plan.applied_count).is_equal(1)
	assert_array(plan.pending).contains_exactly([second])
	assert_bool(plan.destructive).is_true()


func test_planner_treats_a_verified_baseline_as_the_applied_prefix() -> void:
	var first := _migration("202609280001_existing_level")
	var second := _migration("202609280002_add_rank")
	var history: Array[GDSQLMigrationDefinition] = [first, second]
	var baseline := GDSQLMigrationBaseline.new(
		first.migration_id,
		first.checksum,
		GDSQLMigrationHistoryChecksum.compute(history, 1),
		1,
		_valid_fingerprint("a"),
	)

	var result := GDSQLMigrationPlanner.new().plan(
		history,
		GDSQLMigrationLedgerSnapshot.new([], baseline),
	)

	assert_bool(result.is_successful()).is_true()
	var plan := result.get_value() as GDSQLMigrationPlan
	assert_int(plan.applied_count).is_equal(1)
	assert_int(plan.ledger_revision).is_equal(1)
	assert_array(plan.pending).contains_exactly([second])


func test_planner_rejects_changes_before_an_adopted_history_head() -> void:
	var original_first := _migration("202609280001_existing_level")
	var second := _migration("202609280002_existing_rank")
	var original_history: Array[GDSQLMigrationDefinition] = [original_first, second]
	var baseline := GDSQLMigrationBaseline.new(
		second.migration_id,
		second.checksum,
		GDSQLMigrationHistoryChecksum.compute(original_history, 2),
		1,
		_valid_fingerprint("a"),
	)
	var changed_first := GDSQLMigrationDefinition.new(
		original_first.migration_id,
		"Changed before the adopted head",
		original_first.steps,
	)
	var changed_history: Array[GDSQLMigrationDefinition] = [changed_first, second]

	var result := GDSQLMigrationPlanner.new().plan(
		changed_history,
		GDSQLMigrationLedgerSnapshot.new([], baseline),
	)

	assert_str(_first_code(result)).is_equal(
		"GDSQL_MIGRATION_BASELINE_HISTORY_CHANGED",
	)


func test_planner_rejects_changed_divergent_and_missing_history() -> void:
	var original := _migration("202609280001_add_level")
	var changed := GDSQLMigrationDefinition.new(
		original.migration_id,
		"Changed after application",
		original.steps,
	)
	var applied := GDSQLAppliedMigration.new(
		original.migration_id,
		original.checksum,
		1,
		_valid_fingerprint("a"),
	)
	var planner := GDSQLMigrationPlanner.new()

	var checksum_result := planner.plan(
		[changed],
		GDSQLMigrationLedgerSnapshot.new([applied]),
	)
	var divergent_result := planner.plan(
		[_migration("202609280000_other")],
		GDSQLMigrationLedgerSnapshot.new([applied]),
	)
	var missing_result := planner.plan(
		[],
		GDSQLMigrationLedgerSnapshot.new([applied]),
	)

	assert_str(_first_code(checksum_result)).is_equal("GDSQL_MIGRATION_CHECKSUM_MISMATCH")
	assert_str(_first_code(divergent_result)).is_equal("GDSQL_MIGRATION_HISTORY_DIVERGED")
	assert_str(_first_code(missing_result)).is_equal("GDSQL_MIGRATION_HISTORY_MISSING")


func test_config_file_ledger_round_trips_and_rejects_stale_append() -> void:
	var table := GDSQLTableDefinition.new(&"heroes", &"id")
	table.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true))
	var database := TestDatabase.create_database(_data_root, table)
	var ledger := GDSQLConfigFileMigrationLedger.new(
		GDSQLDatabasePathResolver.new(_data_root),
	)
	var first_definition := _migration("202609280001_add_level")
	var second_definition := _migration("202609280002_add_rank")
	var schema_fingerprint := GDSQLSchemaFingerprint.compute(
		database.context.catalog.get_database(database.database_name),
	)
	var first := GDSQLAppliedMigration.new(
		first_definition.migration_id,
		first_definition.checksum,
		1,
		schema_fingerprint,
	)
	var second := GDSQLAppliedMigration.new(
		second_definition.migration_id,
		second_definition.checksum,
		2,
		schema_fingerprint,
	)

	assert_bool(ledger.append(database.database_name, first, 0).is_successful()).is_true()
	var stale := ledger.append(database.database_name, second, 0)
	assert_str(_first_code(stale)).is_equal("GDSQL_MIGRATION_LEDGER_STALE")
	assert_bool(ledger.append(database.database_name, second, 1).is_successful()).is_true()

	var loaded := ledger.load(database.database_name)
	assert_bool(loaded.is_successful()).is_true()
	var snapshot := loaded.get_value() as GDSQLMigrationLedgerSnapshot
	assert_int(snapshot.records.size()).is_equal(2)
	assert_str(snapshot.records[0].migration_id).is_equal(first.migration_id)
	assert_str(snapshot.records[1].schema_fingerprint).is_equal(schema_fingerprint)


func test_config_file_ledger_round_trips_baseline_and_uses_ledger_revision() -> void:
	var table := GDSQLTableDefinition.new(&"heroes", &"id")
	table.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true))
	var database := TestDatabase.create_database(_data_root, table)
	var ledger := GDSQLConfigFileMigrationLedger.new(
		GDSQLDatabasePathResolver.new(_data_root),
	)
	var adopted_definition := _migration("202609280001_existing")
	var next_definition := _migration("202609280002_next")
	var history: Array[GDSQLMigrationDefinition] = [
		adopted_definition,
		next_definition,
	]
	var schema_fingerprint := GDSQLSchemaFingerprint.compute(
		database.context.catalog.get_database(database.database_name),
	)
	var baseline := GDSQLMigrationBaseline.new(
		adopted_definition.migration_id,
		adopted_definition.checksum,
		GDSQLMigrationHistoryChecksum.compute(history, 1),
		1,
		schema_fingerprint,
	)

	assert_bool(
		ledger.adopt_baseline(database.database_name, baseline, 0).is_successful(),
	).is_true()
	var duplicate := ledger.adopt_baseline(database.database_name, baseline, 1)
	assert_str(_first_code(duplicate)).is_equal(
		"GDSQL_MIGRATION_BASELINE_ALREADY_ESTABLISHED",
	)
	var next_record := GDSQLAppliedMigration.new(
		next_definition.migration_id,
		next_definition.checksum,
		2,
		schema_fingerprint,
	)
	var stale := ledger.append(database.database_name, next_record, 0)
	assert_str(_first_code(stale)).is_equal("GDSQL_MIGRATION_LEDGER_STALE")
	assert_bool(
		ledger.append(database.database_name, next_record, 1).is_successful(),
	).is_true()

	var snapshot := ledger.load(database.database_name).get_value() \
			as GDSQLMigrationLedgerSnapshot
	assert_object(snapshot.baseline).is_not_null()
	assert_str(snapshot.baseline.history_checksum).is_equal(baseline.history_checksum)
	assert_int(snapshot.records.size()).is_equal(1)
	assert_int(snapshot.revision()).is_equal(2)
	assert_str(snapshot.last_id()).is_equal(next_definition.migration_id)


func test_step_planner_previews_next_migration_without_mutation() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	TestDatabase.insert_basic_heroes(database)
	var migration := _migration("202609280001_add_level")
	var history_result := GDSQLMigrationPlanner.new().plan(
		[migration],
		GDSQLMigrationLedgerSnapshot.new(),
	)
	var planner := GDSQLMigrationStepPlanner.new(
		database.context.catalog_administration,
	)

	var result := planner.preview_next(database.database_name, history_result.get_value())

	assert_bool(result.is_successful()).is_true()
	var plan := result.get_value() as GDSQLMigrationStepPlan
	assert_str(plan.migration.migration_id).is_equal(migration.migration_id)
	assert_int(plan.expected_ledger_revision).is_equal(0)
	assert_int(plan.affected_rows()).is_equal(2)
	assert_bool(plan.requires_confirmation()).is_false()
	assert_array(plan.summaries()).has_size(1)
	assert_object(
		database.context.catalog.get_table(database.database_name, &"heroes") \
				.get_column(&"level"),
	).is_null()


func test_runner_creates_table_and_records_schema_fingerprint() -> void:
	var database := GDSQLDatabase.create(
		TestDatabase.DEFAULT_DATABASE_NAME,
		_data_root,
	).get_database()
	var table := _inventory_table()
	var migration := _create_table_migration(
		"202609280001_create_inventory",
		table,
	)

	var preview := database.preview_migrations([migration])

	assert_bool(preview.is_successful()).is_true()
	assert_object(
		database.context.catalog.get_table(database.database_name, &"inventory"),
	).is_null()
	assert_array(preview.next_plan.summaries()).contains_exactly(
		["Create table 'inventory'."],
	)
	var applied := database.apply_migration(preview.next_plan)
	assert_bool(applied.is_successful()).is_true()
	var reopened := GDSQLDatabase.open(database.database_name, _data_root).get_database()
	var created := reopened.context.catalog.get_table(
		database.database_name,
		&"inventory",
	)
	assert_object(created).is_not_null()
	assert_str(created.primary_key).is_equal("id")
	var ledger := GDSQLConfigFileMigrationLedger.new(
		GDSQLDatabasePathResolver.new(_data_root),
	).load(database.database_name).get_value() as GDSQLMigrationLedgerSnapshot
	assert_int(ledger.records.size()).is_equal(1)
	assert_str(ledger.records[0].migration_id).is_equal(migration.migration_id)


func test_create_table_plan_is_stale_when_table_appears_after_preview() -> void:
	var database := GDSQLDatabase.create(
		TestDatabase.DEFAULT_DATABASE_NAME,
		_data_root,
	).get_database()
	var table := _inventory_table()
	var migration := _create_table_migration(
		"202609280001_create_inventory",
		table,
	)
	var preview := database.preview_migrations([migration])
	assert_bool(preview.is_successful()).is_true()
	assert_bool(database.create_table(_inventory_table()).is_successful()).is_true()

	var applied := database.apply_migration(preview.next_plan)

	assert_bool(applied.is_successful()).is_false()
	assert_str(_first_code(applied)).is_equal("GDSQL_CATALOG_CHANGE_PLAN_STALE")
	var ledger := GDSQLConfigFileMigrationLedger.new(
		GDSQLDatabasePathResolver.new(_data_root),
	).load(database.database_name).get_value() as GDSQLMigrationLedgerSnapshot
	assert_bool(ledger.records.is_empty()).is_true()


func test_create_table_migration_restores_backup_when_ledger_append_fails() -> void:
	var database := GDSQLDatabase.create(
		TestDatabase.DEFAULT_DATABASE_NAME,
		_data_root,
	).get_database()
	var harness := ConfigMigrationHarness.new(_data_root)
	var migration := _create_table_migration(
		"202609280001_create_inventory",
		_inventory_table(),
	)
	var history := GDSQLMigrationPlanner.new().plan(
		[migration],
		GDSQLMigrationLedgerSnapshot.new(),
	)
	var preview := GDSQLMigrationStepPlanner.new(
		harness.administration,
	).preview_next(database.database_name, history.get_value())
	var runner := GDSQLMigrationRunner.new(
		harness.catalog,
		harness.administration,
		FailingAppendLedger.new(),
		harness.recovery,
	)

	var result := runner.apply(preview.get_value())

	assert_bool(result.is_successful()).is_false()
	assert_str(_first_code(result)).is_equal("GDSQL_TEST_LEDGER_APPEND_FAILED")
	assert_bool(result.recovered).is_true()
	var reopened := GDSQLDatabase.open(database.database_name, _data_root).get_database()
	assert_object(
		reopened.context.catalog.get_table(database.database_name, &"inventory"),
	).is_null()


func test_runner_renames_table_and_preserves_stored_rows() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	TestDatabase.insert_basic_heroes(database)
	var migration := _rename_table_migration(
		"202609280001_rename_heroes",
		&"heroes",
		&"characters",
	)

	var preview := database.preview_migrations([migration])

	assert_bool(preview.is_successful()).is_true()
	assert_int(preview.next_plan.affected_rows()).is_equal(2)
	assert_bool(preview.next_plan.requires_confirmation()).is_false()
	assert_array(preview.next_plan.summaries()).contains_exactly(
		["Rename table 'heroes' to 'characters'."],
	)
	var applied := database.apply_migration(preview.next_plan)
	assert_bool(applied.is_successful()).is_true()
	var reopened := GDSQLDatabase.open(database.database_name, _data_root).get_database()
	assert_object(
		reopened.context.catalog.get_table(database.database_name, &"heroes"),
	).is_null()
	assert_object(
		reopened.context.catalog.get_table(database.database_name, &"characters"),
	).is_not_null()
	var rows := reopened.execute(
		reopened.query().select().from_table(&"characters").build(),
	)
	assert_int(rows.rows.size()).is_equal(2)
	assert_str(rows.rows[0].get_value(&"name")).is_equal("Knight")


func test_runner_drops_table_and_records_destructive_migration() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	TestDatabase.insert_basic_heroes(database)
	var migration := _drop_table_migration(
		"202609280001_drop_heroes",
		&"heroes",
	)

	var preview := database.preview_migrations([migration])

	assert_bool(preview.is_successful()).is_true()
	assert_int(preview.next_plan.affected_rows()).is_equal(2)
	assert_bool(preview.next_plan.requires_confirmation()).is_true()
	assert_array(preview.next_plan.summaries()).contains_exactly(
		["Drop table 'heroes' and its 2 row(s)."],
	)
	var applied := database.apply_migration(preview.next_plan)
	assert_bool(applied.is_successful()).is_true()
	var reopened := GDSQLDatabase.open(database.database_name, _data_root).get_database()
	assert_object(
		reopened.context.catalog.get_table(database.database_name, &"heroes"),
	).is_null()
	var ledger := GDSQLConfigFileMigrationLedger.new(
		GDSQLDatabasePathResolver.new(_data_root),
	).load(database.database_name).get_value() as GDSQLMigrationLedgerSnapshot
	assert_int(ledger.records.size()).is_equal(1)
	assert_str(ledger.records[0].migration_id).is_equal(migration.migration_id)


func test_drop_table_migration_restores_rows_when_ledger_append_fails() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	TestDatabase.insert_basic_heroes(database)
	var harness := ConfigMigrationHarness.new(_data_root)
	var migration := _drop_table_migration(
		"202609280001_drop_heroes",
		&"heroes",
	)
	var history := GDSQLMigrationPlanner.new().plan(
		[migration],
		GDSQLMigrationLedgerSnapshot.new(),
	)
	var preview := GDSQLMigrationStepPlanner.new(
		harness.administration,
	).preview_next(database.database_name, history.get_value())
	var runner := GDSQLMigrationRunner.new(
		harness.catalog,
		harness.administration,
		FailingAppendLedger.new(),
		harness.recovery,
	)

	var result := runner.apply(preview.get_value())

	assert_bool(result.is_successful()).is_false()
	assert_str(_first_code(result)).is_equal("GDSQL_TEST_LEDGER_APPEND_FAILED")
	assert_bool(result.recovered).is_true()
	var reopened := GDSQLDatabase.open(database.database_name, _data_root).get_database()
	assert_object(
		reopened.context.catalog.get_table(database.database_name, &"heroes"),
	).is_not_null()
	var rows := reopened.execute(
		reopened.query().select().from_table(&"heroes").build(),
	)
	assert_int(rows.rows.size()).is_equal(2)


func test_catalog_migration_preview_retains_stale_schema_protection() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	var migration := _migration("202609280001_add_level")
	var history_result := GDSQLMigrationPlanner.new().plan(
		[migration],
		GDSQLMigrationLedgerSnapshot.new(),
	)
	var planner := GDSQLMigrationStepPlanner.new(
		database.context.catalog_administration,
	)
	var preview := planner.preview_next(
		database.database_name,
		history_result.get_value(),
	)
	var plan := preview.get_value() as GDSQLMigrationStepPlan
	var unrelated: Array[GDSQLTableAlteration] = [
		GDSQLTableAlteration.add_column(
			GDSQLColumnDefinition.new(&"rank", TYPE_INT, false, false, false, 1),
		),
	]
	assert_bool(database.alter_table(&"heroes", unrelated).is_successful()).is_true()

	var apply_result := database.context.apply_change_plan(plan.change_plan)

	assert_bool(apply_result.is_successful()).is_false()
	assert_str(_first_code(apply_result)).is_equal("GDSQL_CATALOG_CHANGE_PLAN_STALE")


func test_step_planner_rejects_multi_step_preview_without_mutation() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	var steps: Array[GDSQLSchemaMigrationStep] = [
		GDSQLSchemaMigrationStep.new(
			&"heroes",
			[
				GDSQLTableAlteration.add_column(
					GDSQLColumnDefinition.new(
						&"level",
						TYPE_INT,
						false,
						false,
						false,
						1,
					),
				),
			],
		),
		GDSQLSchemaMigrationStep.new(
			&"heroes",
			[GDSQLTableAlteration.set_column_unique(&"name", true)],
		),
	]
	var migration := GDSQLMigrationDefinition.new(
		"202609280001_multiple_steps",
		"Unsupported initial dry run",
		steps,
	)
	var history_result := GDSQLMigrationPlanner.new().plan(
		[migration],
		GDSQLMigrationLedgerSnapshot.new(),
	)
	var planner := GDSQLMigrationStepPlanner.new(
		database.context.catalog_administration,
	)

	var result := planner.preview_next(database.database_name, history_result.get_value())

	assert_bool(result.is_successful()).is_false()
	assert_str(_first_code(result)).is_equal(
		"GDSQL_MIGRATION_MULTI_STEP_PREVIEW_UNSUPPORTED",
	)
	assert_object(
		database.context.catalog.get_table(database.database_name, &"heroes") \
				.get_column(&"level"),
	).is_null()


func test_config_file_recovery_restores_database_rows_schema_and_ledger() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	TestDatabase.insert_basic_heroes(database)
	var resolver := GDSQLDatabasePathResolver.new(_data_root)
	var cache := GDSQLConfigFileCache.new()
	var recovery := GDSQLConfigFileMigrationRecoveryStore.new(resolver, cache)
	var ledger := GDSQLConfigFileMigrationLedger.new(resolver)
	var previous_definition := _migration("202609280000_previous")
	var previous_record := GDSQLAppliedMigration.new(
		previous_definition.migration_id,
		previous_definition.checksum,
		1,
		GDSQLSchemaFingerprint.compute(
			database.context.catalog.get_database(database.database_name),
		),
	)
	assert_bool(
		ledger.append(database.database_name, previous_record, 0).is_successful(),
	).is_true()

	var created := recovery.create_backup(
		database.database_name,
		"202609280001_add_level",
	)

	assert_bool(created.is_successful()).is_true()
	var backup := created.get_value() as GDSQLMigrationBackup
	assert_bool(backup.is_valid()).is_true()
	var alterations: Array[GDSQLTableAlteration] = [
		GDSQLTableAlteration.add_column(
			GDSQLColumnDefinition.new(&"level", TYPE_INT, false, false, false, 1),
		),
	]
	assert_bool(database.alter_table(&"heroes", alterations).is_successful()).is_true()
	assert_bool(
		database.insert(
			&"heroes",
			{ &"id": 3, &"name": "Rogue", &"level": 3 },
		).is_successful(),
	).is_true()
	var applied_definition := _migration("202609280001_add_level")
	var applied_fingerprint := GDSQLSchemaFingerprint.compute(
		database.context.catalog.get_database(database.database_name),
	)
	assert_bool(
		ledger.append(
			database.database_name,
			GDSQLAppliedMigration.new(
				applied_definition.migration_id,
				applied_definition.checksum,
				2,
				applied_fingerprint,
			),
			1,
		).is_successful(),
	).is_true()
	var table_path := resolver.resolve_table_path(database.database_name, &"heroes")
	assert_bool(cache.get_or_load(table_path).has_section("3")).is_true()
	var reopened_recovery := GDSQLConfigFileMigrationRecoveryStore.new(resolver, cache)
	var loaded := reopened_recovery.load_backup(
		database.database_name,
		backup.migration_id,
	)
	assert_bool(loaded.is_successful()).is_true()

	var restored := reopened_recovery.restore(loaded.get_value())

	assert_bool(restored.is_successful()).is_true()
	assert_bool(cache.get_or_load(table_path).has_section("3")).is_false()
	var reopened := GDSQLDatabase.open(database.database_name, _data_root).get_database()
	assert_object(
		reopened.context.catalog.get_table(database.database_name, &"heroes") \
				.get_column(&"level"),
	).is_null()
	var rows := reopened.execute(
		reopened.query().select().from_table(&"heroes").build(),
	)
	assert_int(rows.rows.size()).is_equal(2)
	var restored_ledger := ledger.load(database.database_name).get_value() \
			as GDSQLMigrationLedgerSnapshot
	assert_int(restored_ledger.records.size()).is_equal(1)
	assert_str(restored_ledger.records[0].migration_id).is_equal(
		previous_record.migration_id,
	)
	assert_bool(
		reopened_recovery.discard(database.database_name, backup.migration_id) \
				.is_successful(),
	).is_true()
	var missing := reopened_recovery.load_backup(
		database.database_name,
		backup.migration_id,
	)
	assert_str(_first_code(missing)).is_equal("GDSQL_MIGRATION_BACKUP_NOT_FOUND")


func test_config_file_recovery_rejects_a_corrupted_snapshot_without_mutation() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	var resolver := GDSQLDatabasePathResolver.new(_data_root)
	var recovery := GDSQLConfigFileMigrationRecoveryStore.new(
		resolver,
		GDSQLConfigFileCache.new(),
	)
	var created := recovery.create_backup(
		database.database_name,
		"202609280001_add_level",
	)
	var backup := created.get_value() as GDSQLMigrationBackup
	var alterations: Array[GDSQLTableAlteration] = [
		GDSQLTableAlteration.add_column(
			GDSQLColumnDefinition.new(&"level", TYPE_INT, false, false, false, 1),
		),
	]
	assert_bool(database.alter_table(&"heroes", alterations).is_successful()).is_true()
	var snapshot_table_path := resolver.resolve_migration_backup_path(
		database.database_name,
		backup.migration_id,
	).path_join("snapshot/tables/heroes.cfg")
	var corrupted := ConfigFile.new()
	assert_int(corrupted.load(snapshot_table_path)).is_equal(OK)
	corrupted.set_value("tampered", "value", true)
	assert_int(corrupted.save(snapshot_table_path)).is_equal(OK)

	var restored := recovery.restore(backup)

	assert_bool(restored.is_successful()).is_false()
	assert_str(_first_code(restored)).is_equal(
		"GDSQL_MIGRATION_BACKUP_FINGERPRINT_MISMATCH",
	)
	assert_object(
		database.context.catalog.get_table(database.database_name, &"heroes") \
				.get_column(&"level"),
	).is_not_null()


func test_runner_applies_catalog_change_and_records_schema_fingerprint() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	TestDatabase.insert_basic_heroes(database)
	var harness := ConfigMigrationHarness.new(_data_root)
	var migration := _migration("202609280001_add_level")
	var plan := harness.preview(database.database_name, [migration])

	var result := harness.runner.apply(plan)

	assert_bool(result.is_successful()).is_true()
	assert_object(result.applied_migration).is_not_null()
	assert_bool(result.applied_migration.is_valid()).is_true()
	assert_bool(result.recovered).is_false()
	assert_bool(result.backup_retained).is_false()
	var reopened := GDSQLDatabase.open(database.database_name, _data_root).get_database()
	assert_object(
		reopened.context.catalog.get_table(database.database_name, &"heroes") \
				.get_column(&"level"),
	).is_not_null()
	var rows := reopened.execute(
		reopened.query().select().from_table(&"heroes").build(),
	)
	assert_int(rows.rows.size()).is_equal(2)
	for row in rows.rows:
		assert_int(row.get_value(&"level")).is_equal(1)
	var ledger := harness.ledger.load(database.database_name).get_value() \
			as GDSQLMigrationLedgerSnapshot
	assert_int(ledger.records.size()).is_equal(1)
	assert_str(ledger.records[0].schema_fingerprint).is_equal(
		GDSQLSchemaFingerprint.compute(
			harness.catalog.get_database(database.database_name),
		),
	)
	var missing_backup := harness.recovery.load_backup(
		database.database_name,
		migration.migration_id,
	)
	assert_str(_first_code(missing_backup)).is_equal(
		"GDSQL_MIGRATION_BACKUP_NOT_FOUND",
	)


func test_runner_restores_backup_when_ledger_append_fails() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	TestDatabase.insert_basic_heroes(database)
	var harness := ConfigMigrationHarness.new(_data_root)
	var migration := _migration("202609280001_add_level")
	var history := GDSQLMigrationPlanner.new().plan(
		[migration],
		GDSQLMigrationLedgerSnapshot.new(),
	)
	var preview := GDSQLMigrationStepPlanner.new(
		harness.administration,
	).preview_next(database.database_name, history.get_value())
	var runner := GDSQLMigrationRunner.new(
		harness.catalog,
		harness.administration,
		FailingAppendLedger.new(),
		harness.recovery,
	)

	var result := runner.apply(preview.get_value())

	assert_bool(result.is_successful()).is_false()
	assert_str(_first_code(result)).is_equal("GDSQL_TEST_LEDGER_APPEND_FAILED")
	assert_bool(result.recovered).is_true()
	assert_bool(result.backup_retained).is_false()
	var reopened := GDSQLDatabase.open(database.database_name, _data_root).get_database()
	assert_object(
		reopened.context.catalog.get_table(database.database_name, &"heroes") \
				.get_column(&"level"),
	).is_null()
	var rows := reopened.execute(
		reopened.query().select().from_table(&"heroes").build(),
	)
	assert_int(rows.rows.size()).is_equal(2)


func test_runner_restores_data_update_when_ledger_append_fails() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	TestDatabase.insert_basic_heroes(database)
	var assignments: Array[GDSQLColumnAssignment] = [
		GDSQLColumnAssignment.new(&"name", GDSQLLiteralExpression.new("Wizard")),
	]
	var migration := GDSQLMigrationDefinition.new(
		"202609280001_rename_mage",
		"Rename the mage",
		[
			GDSQLDataMigrationStep.new(
				&"heroes",
				assignments,
				GDSQLColumnExpression.new(&"id").equals(2),
			),
		],
	)
	var preview := database.preview_migrations([migration])
	var recovery := GDSQLConfigFileMigrationRecoveryStore.new(
		GDSQLDatabasePathResolver.new(_data_root),
		GDSQLConfigFileCache.new(),
	)
	var runner := GDSQLMigrationRunner.new(
		database.context.catalog,
		database.context.catalog_administration,
		FailingAppendLedger.new(),
		recovery,
		database.context.validator,
		database.context.planner,
		database.context.executor,
		database.context.execution_context,
	)

	var result := runner.apply(preview.next_plan)

	assert_bool(result.is_successful()).is_false()
	assert_str(_first_code(result)).is_equal("GDSQL_TEST_LEDGER_APPEND_FAILED")
	assert_bool(result.recovered).is_true()
	assert_bool(result.backup_retained).is_false()
	var reopened := GDSQLDatabase.open(database.database_name, _data_root).get_database()
	var rows := reopened.execute(
		reopened.query().table(&"heroes").select().order_by_column(&"id").build(),
	)
	assert_str(rows.rows[1].get_value(&"name")).is_equal("Mage")


func test_runner_restores_every_table_when_data_batch_ledger_append_fails() -> void:
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
		"202609280001_multi_table_data",
		"Update two tables atomically",
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
	var preview := database.preview_migrations([migration])
	var recovery := GDSQLConfigFileMigrationRecoveryStore.new(
		GDSQLDatabasePathResolver.new(_data_root),
		GDSQLConfigFileCache.new(),
	)
	var runner := GDSQLMigrationRunner.new(
		database.context.catalog,
		database.context.catalog_administration,
		FailingAppendLedger.new(),
		recovery,
		database.context.validator,
		database.context.planner,
		database.context.executor,
		database.context.execution_context,
	)

	var result := runner.apply(preview.next_plan)

	assert_bool(result.is_successful()).is_false()
	assert_str(_first_code(result)).is_equal("GDSQL_TEST_LEDGER_APPEND_FAILED")
	assert_bool(result.recovered).is_true()
	var reopened := GDSQLDatabase.open(database.database_name, _data_root).get_database()
	var hero_rows := reopened.execute(
		reopened.query().table(&"heroes").select().order_by_column(&"id").build(),
	)
	var quest_rows := reopened.execute(
		reopened.query().table(&"quests").select().build(),
	)
	assert_str(hero_rows.rows[1].get_value(&"name")).is_equal("Mage")
	assert_str(quest_rows.rows[0].get_value(&"status")).is_equal("locked")


func test_runner_restores_preexisting_state_when_catalog_plan_is_stale() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	var harness := ConfigMigrationHarness.new(_data_root)
	var migration := _migration("202609280001_add_level")
	var plan := harness.preview(database.database_name, [migration])
	var unrelated: Array[GDSQLTableAlteration] = [
		GDSQLTableAlteration.add_column(
			GDSQLColumnDefinition.new(&"rank", TYPE_INT, false, false, false, 1),
		),
	]
	assert_bool(database.alter_table(&"heroes", unrelated).is_successful()).is_true()

	var result := harness.runner.apply(plan)

	assert_bool(result.is_successful()).is_false()
	assert_str(_first_code(result)).is_equal("GDSQL_CATALOG_CHANGE_PLAN_STALE")
	assert_bool(result.recovered).is_true()
	var reopened := GDSQLDatabase.open(database.database_name, _data_root).get_database()
	var table := reopened.context.catalog.get_table(database.database_name, &"heroes")
	assert_object(table.get_column(&"rank")).is_not_null()
	assert_object(table.get_column(&"level")).is_null()


func test_runner_rejects_schema_drift_before_creating_a_backup() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	var harness := ConfigMigrationHarness.new(_data_root)
	var first := _migration("202609280001_add_level")
	assert_bool(
		harness.runner.apply(
			harness.preview(database.database_name, [first]),
		).is_successful(),
	).is_true()
	var drift: Array[GDSQLTableAlteration] = [
		GDSQLTableAlteration.add_column(
			GDSQLColumnDefinition.new(&"rank", TYPE_INT, false, false, false, 1),
		),
	]
	assert_bool(database.alter_table(&"heroes", drift).is_successful()).is_true()
	var second := _migration(
		"202609280002_add_mana",
		GDSQLTableAlteration.add_column(
			GDSQLColumnDefinition.new(&"mana", TYPE_INT, false, false, false, 0),
		),
	)
	var plan := harness.preview(database.database_name, [first, second])

	var result := harness.runner.apply(plan)

	assert_bool(result.is_successful()).is_false()
	assert_str(_first_code(result)).is_equal("GDSQL_MIGRATION_SCHEMA_DRIFT")
	assert_object(result.backup).is_null()
	var table := harness.catalog.get_table(database.database_name, &"heroes")
	assert_object(table.get_column(&"rank")).is_not_null()
	assert_object(table.get_column(&"mana")).is_null()


func _migration(
		migration_id: String,
		alteration: GDSQLTableAlteration = null,
) -> GDSQLMigrationDefinition:
	if alteration == null:
		alteration = GDSQLTableAlteration.add_column(
			GDSQLColumnDefinition.new(&"level", TYPE_INT, false, false, false, 1),
		)
	var alterations: Array[GDSQLTableAlteration] = [alteration]
	var steps: Array[GDSQLSchemaMigrationStep] = [
		GDSQLSchemaMigrationStep.new(&"heroes", alterations),
	]
	return GDSQLMigrationDefinition.new(migration_id, "Migration %s" % migration_id, steps)


func _create_table_migration(
		migration_id: String,
		table: GDSQLTableDefinition,
) -> GDSQLMigrationDefinition:
	var steps: Array[GDSQLSchemaMigrationStep] = [
		GDSQLSchemaMigrationStep.create_table(table),
	]
	return GDSQLMigrationDefinition.new(
		migration_id,
		"Migration %s" % migration_id,
		steps,
	)


func _rename_table_migration(
		migration_id: String,
		current_name: StringName,
		new_name: StringName,
) -> GDSQLMigrationDefinition:
	var steps: Array[GDSQLSchemaMigrationStep] = [
		GDSQLSchemaMigrationStep.rename_table(current_name, new_name),
	]
	return GDSQLMigrationDefinition.new(
		migration_id,
		"Migration %s" % migration_id,
		steps,
	)


func _drop_table_migration(
		migration_id: String,
		table_name: StringName,
) -> GDSQLMigrationDefinition:
	var steps: Array[GDSQLSchemaMigrationStep] = [
		GDSQLSchemaMigrationStep.drop_table(table_name),
	]
	return GDSQLMigrationDefinition.new(
		migration_id,
		"Migration %s" % migration_id,
		steps,
	)


func _inventory_table() -> GDSQLTableDefinition:
	var table := GDSQLTableDefinition.new(&"inventory", &"id")
	table.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true, true))
	table.add_column(GDSQLColumnDefinition.new(&"item_id", TYPE_STRING_NAME, false))
	return table


func _first_code(result: GDSQLOperationResult) -> String:
	return String(result.diagnostics.entries[0].code)


func _valid_fingerprint(character: String) -> String:
	return character.repeat(64)
