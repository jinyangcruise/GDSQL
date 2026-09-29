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
	TestDatabase.insert_rows(database, [{ &"id": 1, &"name": "Mage", &"level": 3 }])

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
			{ &"id": 1, &"name": "Mage", &"level": 3 },
			{ &"id": 2, &"name": "Knight", &"level": 4 },
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


func test_global_count_aggregate_returns_one_row() -> void:
	var database := TestDatabase.create_heroes_database(_data_root, true)
	var result := database.execute(
		database.table(&"heroes")
		.select()
		.count(GDSQLColumnExpression.new(&"id"), &"hero_count")
		.build(),
	)

	assert_bool(result.is_successful()).is_true()
	assert_int(result.get_returned_rows()).is_equal(1)
	assert_int(result.rows[0].get_value(&"hero_count")).is_equal(0)


func test_expr_builds_canonical_expression_nodes_and_coerces_literals() -> void:
	var expression := GDSQLExpr.column(&"level", &"heroes").add(1).greater_than(3)

	assert_object(expression).is_instanceof(GDSQLComparisonExpression)
	assert_int(expression.operator).is_equal(
		GDSQLComparisonExpression.ComparisonOperator.GREATER_THAN,
	)
	assert_object(expression.left).is_instanceof(GDSQLArithmeticExpression)
	assert_object(expression.left.left).is_instanceof(GDSQLColumnExpression)
	assert_str(String(expression.left.left.table_alias)).is_equal("heroes")
	assert_object(expression.left.right).is_instanceof(GDSQLLiteralExpression)
	assert_int(expression.left.right.value).is_equal(1)
	assert_int(expression.right.value).is_equal(3)


func test_expr_composes_logical_null_and_function_expressions() -> void:
	var condition := GDSQLExpr.and_(
		GDSQLExpr.column(&"name").equals("Mage"),
		GDSQLExpr.column(&"nickname").is_not_null(),
	)

	# Another way of writing the same code
	#var condition := GDSQLExpr.column(&"name").equals("Mage").and_(
	#	#GDSQLExpr.column(&"nickname").is_not_null(),
	#)

	var function := GDSQLExpr.scalar(
		&"coalesce",
		[
			GDSQLExpr.column(&"nickname"),
			"Unknown",
		],
	)
	var aggregate := GDSQLExpr.aggregate(&"count", [GDSQLExpr.column(&"id")])

	assert_object(condition).is_instanceof(GDSQLLogicalExpression)
	assert_int(condition.operator).is_equal(GDSQLLogicalExpression.LogicalOperator.AND)
	assert_object(condition.right).is_instanceof(GDSQLNullCheckExpression)
	assert_int(condition.right.operator).is_equal(
		GDSQLNullCheckExpression.NullCheckOperator.IS_NOT_NULL,
	)
	assert_object(function.arguments[1]).is_instanceof(GDSQLLiteralExpression)
	assert_str(function.arguments[1].value).is_equal("Unknown")
	assert_bool(aggregate.aggregate).is_true()


func test_expr_executes_through_the_existing_query_pipeline() -> void:
	var database := TestDatabase.create_heroes_database(_data_root, true)
	TestDatabase.insert_rows(
		database,
		[
			{ &"id": 1, &"name": "Mage", &"level": 3 },
			{ &"id": 2, &"name": "Knight", &"level": 5 },
		],
	)

	var result := database.execute(
		database.table(&"heroes")
		.select()
		.where(GDSQLExpr.column(&"level").greater_than(3))
		.build(),
	)

	assert_bool(result.is_successful()).is_true()
	assert_int(result.get_returned_rows()).is_equal(1)
	assert_str(result.rows[0].get_value(&"name")).is_equal("Knight")


func test_resource_property_filter_executes_only_on_scalar_leaf() -> void:
	var table := GDSQLTableDefinition.new(&"mesh_heroes", &"id")
	table.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true))
	var mesh_column := GDSQLColumnDefinition.new(&"mesh", TYPE_OBJECT, false)
	mesh_column.resource_type = GDSQLResourceTypeConstraint.from_resource(BoxMesh.new())
	table.add_column(mesh_column)
	var database := TestDatabase.create_database(_data_root, table)
	var small_mesh := BoxMesh.new()
	small_mesh.size = Vector3(1.0, 2.0, 3.0)
	var large_mesh := BoxMesh.new()
	large_mesh.size = Vector3(4.0, 5.0, 6.0)
	TestDatabase.insert_rows(
		database,
		[
			{ &"id": 1, &"mesh": small_mesh },
			{ &"id": 2, &"mesh": large_mesh },
		],
		&"mesh_heroes",
	)

	var result := database.execute(
		database.table(&"mesh_heroes")
		.select()
		.where(
			GDSQLExpr.resource_property(&"mesh", [&"size", &"x"]).greater_than(2.0),
		)
		.build(),
	)

	assert_bool(result.is_successful()).is_true()
	assert_int(result.get_returned_rows()).is_equal(1)
	assert_int(result.rows[0].get_value(&"id")).is_equal(2)


func test_resource_property_filter_rejects_compound_value() -> void:
	var table := GDSQLTableDefinition.new(&"mesh_heroes", &"id")
	table.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true))
	var mesh_column := GDSQLColumnDefinition.new(&"mesh", TYPE_OBJECT, false)
	mesh_column.resource_type = GDSQLResourceTypeConstraint.from_resource(BoxMesh.new())
	table.add_column(mesh_column)
	var database := TestDatabase.create_database(_data_root, table)

	var result := database.execute(
		database.table(&"mesh_heroes")
		.select()
		.where(
			GDSQLExpr.scalar(
				&"resource_property",
				[GDSQLExpr.column(&"mesh"), "size"],
			).equals(Vector3.ONE),
		)
		.build(),
	)

	assert_bool(result.is_successful()).is_false()
	assert_str(String(result.diagnostics.entries[0].code)).is_equal(
		"GDSQL_VALIDATION_RESOURCE_PROPERTY_LEAF",
	)
