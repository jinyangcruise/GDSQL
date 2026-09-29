class_name GDSQLMigrationsTest
extends GdUnitTestSuite

const TestDatabase = preload("res://tests/utils/gdsql_test_database.gd")

var _data_root: String
var _test_index := 0


func before_test() -> void:
	_test_index += 1
	_data_root = create_temp_dir("gdsql_migrations_%d" % _test_index)


func test_checksum_is_stable_and_detects_authored_history_changes() -> void:
	var first := _migration("202609280001_add_level")
	var second := _migration("202609280001_add_level")

	assert_str(first.checksum).is_equal(second.checksum)
	assert_int(first.checksum.length()).is_equal(64)
	assert_bool(first.is_valid()).is_true()

	first.steps[0].alterations[0].column.name = &"rank"

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
				"schema-first",
			),
		],
	)

	var result := GDSQLMigrationPlanner.new().plan([first, second], ledger)

	assert_bool(result.is_successful()).is_true()
	var plan := result.get_value() as GDSQLMigrationPlan
	assert_int(plan.applied_count).is_equal(1)
	assert_array(plan.pending).contains_exactly([second])
	assert_bool(plan.destructive).is_true()


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
		"schema-first",
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
	var first := GDSQLAppliedMigration.new(
		first_definition.migration_id,
		first_definition.checksum,
		1,
		"schema-first",
	)
	var second := GDSQLAppliedMigration.new(
		second_definition.migration_id,
		second_definition.checksum,
		2,
		"schema-second",
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
	assert_str(snapshot.records[1].schema_fingerprint).is_equal("schema-second")


func test_catalog_planner_previews_next_migration_without_mutation() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	TestDatabase.insert_basic_heroes(database)
	var migration := _migration("202609280001_add_level")
	var history_result := GDSQLMigrationPlanner.new().plan(
		[migration],
		GDSQLMigrationLedgerSnapshot.new(),
	)
	var planner := GDSQLMigrationCatalogPlanner.new(
		database.context.catalog_administration,
	)

	var result := planner.preview_next(database.database_name, history_result.get_value())

	assert_bool(result.is_successful()).is_true()
	var plan := result.get_value() as GDSQLMigrationCatalogPlan
	assert_str(plan.migration.migration_id).is_equal(migration.migration_id)
	assert_int(plan.expected_ledger_count).is_equal(0)
	assert_int(plan.affected_rows()).is_equal(2)
	assert_bool(plan.requires_confirmation()).is_false()
	assert_array(plan.summaries()).has_size(1)
	assert_object(
		database.context.catalog.get_table(database.database_name, &"heroes") \
				.get_column(&"level"),
	).is_null()


func test_catalog_migration_preview_retains_stale_schema_protection() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	var migration := _migration("202609280001_add_level")
	var history_result := GDSQLMigrationPlanner.new().plan(
		[migration],
		GDSQLMigrationLedgerSnapshot.new(),
	)
	var planner := GDSQLMigrationCatalogPlanner.new(
		database.context.catalog_administration,
	)
	var preview := planner.preview_next(
		database.database_name,
		history_result.get_value(),
	)
	var plan := preview.get_value() as GDSQLMigrationCatalogPlan
	var unrelated: Array[GDSQLTableAlteration] = [
		GDSQLTableAlteration.add_column(
			GDSQLColumnDefinition.new(&"rank", TYPE_INT, false, false, false, 1),
		),
	]
	assert_bool(database.alter_table(&"heroes", unrelated).is_successful()).is_true()

	var apply_result := database.context.apply_change_plan(plan.change_plan)

	assert_bool(apply_result.is_successful()).is_false()
	assert_str(_first_code(apply_result)).is_equal("GDSQL_CATALOG_CHANGE_PLAN_STALE")


func test_catalog_planner_rejects_multi_step_preview_without_mutation() -> void:
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
	var planner := GDSQLMigrationCatalogPlanner.new(
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
		"before-backup",
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
			{&"id": 3, &"name": "Rogue", &"level": 3},
		).is_successful(),
	).is_true()
	var applied_definition := _migration("202609280001_add_level")
	assert_bool(
		ledger.append(
			database.database_name,
			GDSQLAppliedMigration.new(
				applied_definition.migration_id,
				applied_definition.checksum,
				2,
				"after-migration",
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


func _first_code(result: GDSQLOperationResult) -> String:
	return String(result.diagnostics.entries[0].code)
