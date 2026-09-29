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
