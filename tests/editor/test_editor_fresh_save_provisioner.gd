class_name GDSQLEditorFreshSaveProvisionerTest
extends GdUnitTestSuite

const TestDatabase = preload("res://tests/utils/gdsql_test_database.gd")

var _test_root: String
var _test_index := 0


func before_test() -> void:
	_test_index += 1
	_test_root = create_temp_dir("gdsql_fresh_database_%d" % _test_index)


func test_provisions_schema_without_rows_and_adopts_verified_baseline() -> void:
	var source := _create_source(_test_root.path_join("source"))
	TestDatabase.insert_basic_heroes(source)
	var target := GDSQLDatabase.create(
		&"game_state",
		_test_root.path_join("target"),
	).get_database()
	var history: Array[GDSQLMigrationDefinition] = []
	var source_definition := source.context.catalog.get_database(&"game_state")
	var state := GDSQLMigrationSchemaState.from_history(
		&"game_state",
		&"game_state",
		history,
		GDSQLSchemaFingerprint.compute(source_definition),
	)

	var result := GDSQLEditorFreshSaveProvisioner.new().provision(
		source_definition,
		target,
		history,
		state,
	)

	assert_bool(result.is_successful()).is_true()
	assert_object(result.get_value()).is_instanceof(GDSQLMigrationBaseline)
	var target_definition := target.context.catalog.get_database(&"game_state")
	assert_str(GDSQLSchemaFingerprint.compute(target_definition)).is_equal(
		state.schema_fingerprint,
	)
	assert_int(target_definition.tables.size()).is_equal(2)
	assert_int(
		target.execute(target.table(&"heroes").select().build()).get_returned_rows(),
	).is_equal(0)
	assert_int(
		target.execute(target.table(&"equipment").select().build()).get_returned_rows(),
	).is_equal(0)
	assert_object(
		target_definition.get_table(&"equipment").get_foreign_key(&"equipment_hero"),
	).is_not_null()
	var ledger := GDSQLConfigFileMigrationLedger.new(
		GDSQLDatabasePathResolver.new(_test_root.path_join("target")),
	).load(&"game_state").get_value() as GDSQLMigrationLedgerSnapshot
	assert_object(ledger.baseline).is_not_null()
	assert_int(ledger.revision()).is_equal(1)


func test_rejects_untrusted_template_before_mutating_target() -> void:
	var source := _create_source(_test_root.path_join("source"))
	var target := GDSQLDatabase.create(
		&"game_state",
		_test_root.path_join("target"),
	).get_database()
	var history: Array[GDSQLMigrationDefinition] = []
	var state := GDSQLMigrationSchemaState.from_history(
		&"game_state",
		&"game_state",
		history,
		"a".repeat(64),
	)

	var result := GDSQLEditorFreshSaveProvisioner.new().provision(
		source.context.catalog.get_database(&"game_state"),
		target,
		history,
		state,
	)

	assert_bool(result.is_successful()).is_false()
	assert_str(String(result.diagnostics.entries[0].code)).is_equal(
		"GDSQL_FRESH_DATABASE_TEMPLATE_OUTDATED",
	)
	assert_array(
		target.context.catalog.get_database(&"game_state").tables,
	).is_empty()


func _create_source(data_root: String) -> GDSQLDatabase:
	var heroes := GDSQLTableDefinition.new(&"heroes", &"id")
	heroes.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true))
	heroes.add_column(GDSQLColumnDefinition.new(&"name", TYPE_STRING, false))
	var equipment := GDSQLTableDefinition.new(&"equipment", &"id")
	equipment.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true))
	equipment.add_column(GDSQLColumnDefinition.new(&"hero_id", TYPE_INT, false))
	equipment.add_foreign_key(
		GDSQLForeignKeyDefinition.new(
			&"equipment_hero",
			&"hero_id",
			&"heroes",
			&"id",
		),
	)
	return TestDatabase.create_database_with_tables(
		data_root,
		[heroes, equipment],
		&"game_state",
	)
