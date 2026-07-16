class_name GDSQLExpressionSemanticsTest
extends GdUnitTestSuite

const TestDatabase = preload("res://tests/utils/gdsql_test_database.gd")

var _data_root: String
var _test_index := 0


func before_test() -> void:
	_test_index += 1
	_data_root = create_temp_dir("gdsql_expression_semantics_%d" % _test_index)


func test_select_projects_arithmetic_and_scalar_function_expressions() -> void:
	var database := TestDatabase.create_heroes_database(_data_root, true)
	TestDatabase.insert_rows(database, [{&"id": 1, &"name": "Mage", &"level": 3}])

	var result := database.execute(
		database.table(&"heroes")
		.select()
		.project(
			GDSQLArithmeticExpression.new(
				GDSQLColumnExpression.new(&"level"),
				GDSQLArithmeticExpression.ArithmeticOperator.MULTIPLY,
				GDSQLLiteralExpression.new(2),
			),
			&"power",
		)
		.project(
			GDSQLFunctionExpression.new(
				&"upper",
				[GDSQLColumnExpression.new(&"name")],
			),
			&"display_name",
		)
		.build(),
	)

	assert_bool(result.is_successful()).is_true()
	assert_int(result.rows[0].get_value(&"power")).is_equal(6)
	assert_str(result.rows[0].get_value(&"display_name")).is_equal("MAGE")
	assert_int(result.get_schema().get_column(&"power").data_type).is_equal(TYPE_INT)
	assert_int(result.get_schema().get_column(&"display_name").data_type).is_equal(TYPE_STRING)


func test_update_accepts_an_arithmetic_assignment() -> void:
	var database := TestDatabase.create_heroes_database(_data_root, true)
	TestDatabase.insert_rows(
		database,
		[
			{&"id": 1, &"name": "Mage", &"level": 3},
			{&"id": 2, &"name": "Knight", &"level": 4},
		],
	)

	var result := database.execute(
		database.table(&"heroes")
		.update()
		.set_expression(
			&"level",
			GDSQLArithmeticExpression.new(
				GDSQLColumnExpression.new(&"level"),
				GDSQLArithmeticExpression.ArithmeticOperator.ADD,
				GDSQLLiteralExpression.new(1),
			),
		)
		.build(),
	)

	assert_bool(result.is_successful()).is_true()
	assert_int(result.rows[0].get_value(&"level")).is_equal(4)
	assert_int(result.rows[1].get_value(&"level")).is_equal(5)


func test_null_checks_and_logical_expressions_use_three_valued_semantics() -> void:
	var evaluator := GDSQLExpressionEvaluator.new(GDSQLQueryFunctionRegistry.new())
	var row := GDSQLRowRecord.new({ &"nickname": null })
	var comparison := GDSQLComparisonExpression.new(
		GDSQLColumnExpression.new(&"nickname"),
		GDSQLComparisonExpression.ComparisonOperator.EQUAL,
		GDSQLLiteralExpression.new("Mage"),
	)

	assert_object(evaluator.evaluate(comparison, row)).is_null()
	assert_bool(
		evaluator.evaluate(
			GDSQLNullCheckExpression.new(GDSQLColumnExpression.new(&"nickname")),
			row,
		),
	).is_true()
	assert_object(
		evaluator.evaluate(
			GDSQLLogicalExpression.new(
				GDSQLLiteralExpression.new(true),
				GDSQLLogicalExpression.LogicalOperator.AND,
				comparison,
			),
			row,
		),
	).is_null()


func test_invalid_function_call_returns_validation_diagnostic() -> void:
	var database := TestDatabase.create_heroes_database(_data_root, true)
	var result := database.execute(
		database.table(&"heroes")
		.select()
		.project(GDSQLFunctionExpression.new(&"missing_function", []))
		.build(),
	)

	assert_bool(result.is_successful()).is_false()
	assert_str(String(result.diagnostics.entries[0].code)).is_equal(
		"GDSQL_VALIDATION_UNKNOWN_FUNCTION",
	)


func test_aggregate_function_is_scaffolded_with_an_unsupported_diagnostic() -> void:
	var database := TestDatabase.create_heroes_database(_data_root, true)
	var result := database.execute(
		database.table(&"heroes")
		.select()
		.project(
			GDSQLFunctionExpression.new(
				&"count",
				[GDSQLColumnExpression.new(&"id")],
				true,
			),
		)
		.build(),
	)

	assert_bool(result.is_successful()).is_false()
	assert_str(String(result.diagnostics.entries[0].code)).is_equal(
		"GDSQL_VALIDATION_AGGREGATE_UNSUPPORTED",
	)
