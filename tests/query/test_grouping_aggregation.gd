class_name GDSQLGroupingAggregationTest
extends GdUnitTestSuite

const TestDatabase = preload("res://tests/utils/gdsql_test_database.gd")

var _data_root: String
var _test_index := 0


func before_test() -> void:
	_test_index += 1
	_data_root = create_temp_dir("gdsql_grouping_aggregation_%d" % _test_index)


func test_grouping_calculates_basic_aggregates() -> void:
	var database := TestDatabase.create_heroes_database(_data_root, true)
	TestDatabase.insert_rows(
		database,
		[
			{ &"id": 1, &"name": "Mage", &"level": 3 },
			{ &"id": 2, &"name": "Mage", &"level": 5 },
			{ &"id": 3, &"name": "Knight", &"level": 4 },
		],
	)

	var result := database.execute(
		database.table(&"heroes")
		.select()
		.column(&"name")
		.count(GDSQLColumnExpression.new(&"id"), &"hero_count")
		.sum(GDSQLColumnExpression.new(&"level"), &"total_level")
		.average(GDSQLColumnExpression.new(&"level"), &"average_level")
		.minimum(GDSQLColumnExpression.new(&"level"), &"minimum_level")
		.maximum(GDSQLColumnExpression.new(&"level"), &"maximum_level")
		.group_by_column(&"name")
		.order_by(
			GDSQLOrderClause.new(
				GDSQLFunctionExpression.new(
					&"sum",
					[GDSQLColumnExpression.new(&"level")],
					true,
				),
				GDSQLOrderClause.SortDirection.DESCENDING,
			),
		)
		.build(),
	)

	#for row in result.rows:
	#print(row.values)

	assert_bool(result.is_successful()).is_true()
	assert_int(result.get_returned_rows()).is_equal(2)
	assert_str(result.rows[0].get_value(&"name")).is_equal("Mage")
	assert_int(result.rows[0].get_value(&"hero_count")).is_equal(2)
	assert_int(result.rows[0].get_value(&"total_level")).is_equal(8)
	assert_float(result.rows[0].get_value(&"average_level")).is_equal(4.0)
	assert_int(result.rows[0].get_value(&"minimum_level")).is_equal(3)
	assert_int(result.rows[0].get_value(&"maximum_level")).is_equal(5)


func test_having_filters_grouped_rows() -> void:
	var database := TestDatabase.create_heroes_database(_data_root, true)
	TestDatabase.insert_rows(
		database,
		[
			{ &"id": 1, &"name": "Mage", &"level": 3 },
			{ &"id": 2, &"name": "Mage", &"level": 5 },
			{ &"id": 3, &"name": "Knight", &"level": 4 },
		],
	)
	var count_expression := GDSQLFunctionExpression.new(
		&"count",
		[GDSQLColumnExpression.new(&"id")],
		true,
	)

	var result := database.execute(
		database.table(&"heroes")
		.select()
		.column(&"name")
		.project(count_expression, &"hero_count")
		.group_by_column(&"name")
		.having(
			GDSQLComparisonExpression.new(
				count_expression,
				GDSQLComparisonExpression.ComparisonOperator.GREATER_THAN,
				GDSQLLiteralExpression.new(1),
			),
		)
		.build(),
	)

	#for row in result.rows:
	#print(row.values)

	assert_bool(result.is_successful()).is_true()
	assert_int(result.get_returned_rows()).is_equal(1)
	assert_str(result.rows[0].get_value(&"name")).is_equal("Mage")
	assert_int(result.rows[0].get_value(&"hero_count")).is_equal(2)


func test_ungrouped_projection_returns_validation_diagnostic() -> void:
	var database := TestDatabase.create_heroes_database(_data_root, true)
	var result := database.execute(
		database.table(&"heroes")
		.select()
		.column(&"name")
		.count(GDSQLColumnExpression.new(&"id"), &"hero_count")
		.build(),
	)

	#result.diagnostics.print_to_debug()

	assert_bool(result.is_successful()).is_false()
	assert_str(String(result.diagnostics.entries[0].code)).is_equal(
		"GDSQL_VALIDATION_UNGROUPED_EXPRESSION",
	)
