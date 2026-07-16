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


func test_update_matching_rows() -> void:
	var database := _create_database_with_heroes()
	_insert_heroes(database)
	var update_result := database.execute(
		database.query()
		.update()
		.table(&"heroes")
		.set_value(&"name", "Wizard")
		.where(_id_equals(2))
		.build(),
	)

	assert_bool(update_result.is_successful()).is_true()
	assert_int(update_result.get_affected_rows()).is_equal(1)
	assert_str(update_result.rows[0].get_value(&"name")).is_equal("Wizard")

	var reopened := GDSQLDatabase.open(&"game_config", _data_root).get_database()
	var select_result := reopened.execute(
		reopened.query().select().from_table(&"heroes").where(_id_equals(2)).build(),
	)
	assert_bool(select_result.is_successful()).is_true()
	assert_int(select_result.get_returned_rows()).is_equal(1)
	assert_str(select_result.rows[0].get_value(&"name")).is_equal("Wizard")


func test_delete_matching_rows() -> void:
	var database := _create_database_with_heroes()
	_insert_heroes(database)
	var delete_result := database.execute(
		database.query()
		.delete()
		.from_table(&"heroes")
		.where(_id_equals(1))
		.build(),
	)

	assert_bool(delete_result.is_successful()).is_true()
	assert_int(delete_result.get_affected_rows()).is_equal(1)
	assert_int(delete_result.rows[0].get_value(&"id")).is_equal(1)

	var select_result := database.execute(
		database.query().select().from_table(&"heroes").build(),
	)
	assert_bool(select_result.is_successful()).is_true()
	assert_int(select_result.get_returned_rows()).is_equal(1)
	assert_int(select_result.rows[0].get_value(&"id")).is_equal(2)


func test_select_orders_before_offset_and_limit() -> void:
	var database := _create_database_with_heroes()
	_insert_named_heroes(database, ["Mage", "Knight", "Archer"])

	var result := database.execute(
		database.table(&"heroes")
		.select()
		.order_by_column(
			&"name",
			GDSQLOrderClause.SortDirection.ASCENDING,
		)
		.offset(1)
		.limit(1)
		.build(),
	)

	assert_bool(result.is_successful()).is_true()
	assert_int(result.get_returned_rows()).is_equal(1)
	assert_str(result.rows[0].get_value(&"name")).is_equal("Knight")


func test_select_projection_alias_exposes_result_schema() -> void:
	var database := _create_database_with_heroes()
	_insert_named_heroes(database, ["Mage"])

	var result := database.execute(
		database.table(&"heroes")
		.select()
		.column(&"name", &"display_name")
		.build(),
	)

	assert_bool(result.is_successful()).is_true()
	assert_str(result.rows[0].get_value(&"display_name")).is_equal("Mage")
	assert_bool(result.rows[0].has_column(&"name")).is_false()
	assert_object(result.get_schema().get_column(&"display_name")).is_not_null()
	assert_int(result.get_schema().get_column(&"display_name").data_type).is_equal(TYPE_STRING)


func test_select_distinct_removes_duplicate_projected_rows() -> void:
	var database := _create_database_with_heroes()
	_insert_named_heroes(database, ["Mage", "Mage", "Knight"])

	var result := database.execute(
		database.table(&"heroes")
		.select()
		.column(&"name")
		.distinct()
		.order_by_column(&"name")
		.build(),
	)

	assert_bool(result.is_successful()).is_true()
	assert_int(result.get_returned_rows()).is_equal(2)
	assert_str(result.rows[0].get_value(&"name")).is_equal("Knight")
	assert_str(result.rows[1].get_value(&"name")).is_equal("Mage")


func _create_database_with_heroes() -> GDSQLDatabase:
	var database_result := GDSQLDatabase.create(&"game_config", _data_root)
	assert_bool(database_result.is_successful()).is_true()
	var database := database_result.get_database()
	var heroes := GDSQLTableDefinition.new(&"heroes", &"id")
	heroes.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true))
	heroes.add_column(GDSQLColumnDefinition.new(&"name", TYPE_STRING, false))
	assert_bool(database.create_table(heroes).is_successful()).is_true()
	return database


func _insert_heroes(database: GDSQLDatabase) -> void:
	assert_bool(database.insert(&"heroes", { &"id": 1, &"name": "Knight" }).is_successful()).is_true()
	assert_bool(database.insert(&"heroes", { &"id": 2, &"name": "Mage" }).is_successful()).is_true()


func _insert_named_heroes(database: GDSQLDatabase, names: Array[String]) -> void:
	for index in names.size():
		assert_bool(
			database.insert(
				&"heroes",
				{ &"id": index + 1, &"name": names[index] },
			).is_successful(),
		).is_true()


func _id_equals(id: int) -> GDSQLComparisonExpression:
	return GDSQLComparisonExpression.new(
		GDSQLColumnExpression.new(&"id"),
		GDSQLComparisonExpression.ComparisonOperator.EQUAL,
		GDSQLLiteralExpression.new(id),
	)
