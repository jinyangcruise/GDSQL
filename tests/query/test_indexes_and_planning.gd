class_name GDSQLIndexesAndPlanningTest
extends GdUnitTestSuite

const TestDatabase = preload("res://tests/utils/gdsql_test_database.gd")

var _data_root: String
var _test_index := 0


func before_test() -> void:
	_test_index += 1
	_data_root = create_temp_dir("gdsql_indexes_%d" % _test_index)


func test_catalog_persists_indexes_and_enforces_composite_uniqueness() -> void:
	var database := _create_indexed_database()
	var reopened := GDSQLDatabase.open(&"game_config", _data_root).get_database()
	var table := reopened.context.catalog.get_table(&"game_config", &"heroes")

	assert_int(table.indexes.size()).is_equal(3)
	assert_array(table.get_index(&"hero_identity").get_columns()).contains_exactly(
		[&"name", &"level"],
	)
	assert_bool(table.get_index(&"hero_identity").is_unique()).is_true()

	TestDatabase.insert_rows(database, [{&"id": 1, &"name": "Mage", &"level": 4}])
	var duplicate := database.insert(
		&"heroes",
		{&"id": 2, &"name": "Mage", &"level": 4},
	)
	assert_bool(duplicate.is_successful()).is_false()
	assert_str(String(duplicate.diagnostics.entries[0].code)).is_equal(
		"GDSQL_STORAGE_DUPLICATE_INDEX_VALUE",
	)


func test_exact_index_lookup_is_planned_and_executed() -> void:
	var database := _create_indexed_database()
	_seed_heroes(database)
	var scan_planning := database.context.prepare(
		database.table(&"heroes").select().build(),
	)
	assert_object(scan_planning.plan.root).is_instanceof(GDSQLTableScanPlan)
	var primary_key_planning := database.context.prepare(
		database.table(&"heroes").select().where(TestDatabase.id_equals(2)).build(),
	)
	assert_object(
		(primary_key_planning.plan.root as GDSQLFilterPlan).input,
	).is_instanceof(GDSQLPrimaryKeyLookupPlan)
	var query := database.table(&"heroes").select().where(
		GDSQLComparisonExpression.new(
			GDSQLColumnExpression.new(&"name"),
			GDSQLComparisonExpression.ComparisonOperator.EQUAL,
			GDSQLLiteralExpression.new("Mage"),
		),
	).build()

	var planning := database.context.prepare(query)
	assert_bool(planning.is_successful()).is_true()
	assert_object(planning.plan.root).is_instanceof(GDSQLFilterPlan)
	assert_object((planning.plan.root as GDSQLFilterPlan).input).is_instanceof(
		GDSQLIndexLookupPlan,
	)

	var result := database.execute(query)
	assert_bool(result.is_successful()).is_true()
	assert_int(result.get_returned_rows()).is_equal(2)
	for row in result.rows:
		assert_str(row.get_value(&"name")).is_equal("Mage")


func test_range_lookup_tracks_committed_mutations() -> void:
	var database := _create_indexed_database()
	_seed_heroes(database)
	var range_query := database.table(&"heroes").select().where(
		GDSQLComparisonExpression.new(
			GDSQLColumnExpression.new(&"level"),
			GDSQLComparisonExpression.ComparisonOperator.GREATER_THAN_OR_EQUAL,
			GDSQLLiteralExpression.new(4),
		),
	).build()

	var planning := database.context.prepare(range_query)
	assert_object((planning.plan.root as GDSQLFilterPlan).input).is_instanceof(
		GDSQLRangeLookupPlan,
	)
	assert_int(database.execute(range_query).get_returned_rows()).is_equal(2)

	var update := database.table(&"heroes").update() \
		.set_value(&"level", 5) \
		.where(TestDatabase.id_equals(1)) \
		.build()
	assert_bool(database.execute(update).is_successful()).is_true()
	assert_int(database.execute(range_query).get_returned_rows()).is_equal(3)


func _create_indexed_database() -> GDSQLDatabase:
	var table := GDSQLTableDefinition.new(&"heroes", &"id")
	table.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true))
	table.add_column(GDSQLColumnDefinition.new(&"name", TYPE_STRING, false))
	table.add_column(GDSQLColumnDefinition.new(&"level", TYPE_INT, false))
	table.add_index(GDSQLIndexDefinition.new(&"heroes_by_name", [&"name"]))
	table.add_index(GDSQLIndexDefinition.new(&"heroes_by_level", [&"level"]))
	table.add_index(
		GDSQLIndexDefinition.new(&"hero_identity", [&"name", &"level"], true),
	)
	return TestDatabase.create_database(_data_root, table)


func _seed_heroes(database: GDSQLDatabase) -> void:
	TestDatabase.insert_rows(
		database,
		[
			{&"id": 1, &"name": "Knight", &"level": 2},
			{&"id": 2, &"name": "Mage", &"level": 4},
			{&"id": 3, &"name": "Mage", &"level": 6},
		],
	)
