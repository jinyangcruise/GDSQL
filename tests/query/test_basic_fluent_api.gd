class_name GDSQLBasicFluentApiTest
extends GdUnitTestSuite

var _data_root: String
var _test_index := 0


func before_test() -> void:
	_test_index += 1
	_data_root = create_temp_dir("gdsql_basic_fluent_api_%d" % _test_index)


func test_create_table_and_open_database_again() -> void:
	var database := _create_database_with_heroes()
	var open_result := GDSQLDatabase.open(&"game_config", _data_root)

	assert_bool(open_result.is_successful()).is_true()
	assert_object(open_result.get_database()).is_not_null()
	assert_bool(
		open_result.get_database().context.catalog.has_table(&"game_config", &"heroes"),
	).is_true()


func test_insert_and_minimal_select_pipeline() -> void:
	var database := _create_database_with_heroes()
	var insert_result := database.execute(
		database.query()
		.table(&"heroes")
		.insert()
		.values({ &"id": 1, &"name": "Knight" })
		.values({ &"id": 2, &"name": "Mage" })
		.build(),
	)

	assert_bool(insert_result.is_successful()).is_true()
	assert_int(insert_result.get_affected_rows()).is_equal(2)

	var select_result := database.execute(
		database.query()
		.select()
		.from_table(&"heroes")
		.columns([&"name"])
		.where(
			GDSQLComparisonExpression.new(
				GDSQLColumnExpression.new(&"id"),
				GDSQLComparisonExpression.ComparisonOperator.EQUAL,
				GDSQLLiteralExpression.new(2),
			),
		)
		.limit(1)
		.build(),
	)

	assert_bool(select_result.is_successful()).is_true()
	assert_int(select_result.get_returned_rows()).is_equal(1)
	assert_str(select_result.rows[0].get_value(&"name")).is_equal("Mage")
	assert_bool(select_result.rows[0].has_column(&"id")).is_false()


func _create_database_with_heroes() -> GDSQLDatabase:
	var database_result := GDSQLDatabase.create(&"game_config", _data_root)
	assert_bool(database_result.is_successful()).is_true()
	var database := database_result.get_database()
	var heroes := GDSQLTableDefinition.new(&"heroes", &"id")
	heroes.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true))
	heroes.add_column(GDSQLColumnDefinition.new(&"name", TYPE_STRING, false))
	assert_bool(database.create_table(heroes).is_successful()).is_true()
	return database
