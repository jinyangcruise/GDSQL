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
		database.insert(&"heroes", {&"id": 3, &"name": "Rogue", &"rank": 4}) \
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
