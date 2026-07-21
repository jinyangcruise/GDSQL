class_name GDSQLJoinTest
extends GdUnitTestSuite

const TestDatabase = preload("res://tests/utils/gdsql_test_database.gd")

var _data_root: String
var _test_index := 0


func before_test() -> void:
	_test_index += 1
	_data_root = create_temp_dir("gdsql_joins_%d" % _test_index)


func test_inner_join_binds_qualified_columns_from_two_sources() -> void:
	var database := _create_database_with_relationship_data()
	var result := database.execute(
		database.query()
		.select()
		.from_table(&"heroes", &"h")
		.join_table(&"skills", _hero_skill_condition(), &"s")
		.project(GDSQLColumnExpression.new(&"name", &"h"), &"hero_name")
		.project(GDSQLColumnExpression.new(&"name", &"s"), &"skill_name")
		.order_by(
			GDSQLOrderClause.new(GDSQLColumnExpression.new(&"id", &"s")),
		)
		.build(),
	)

	assert_bool(result.is_successful()).is_true()
	assert_int(result.get_returned_rows()).is_equal(3)
	assert_str(result.rows[0].get_value(&"hero_name")).is_equal("Knight")
	assert_str(result.rows[0].get_value(&"skill_name")).is_equal("Sword")
	assert_str(result.rows[2].get_value(&"skill_name")).is_equal("Shield")
	#for row in result.rows:
	#print(row.values)


func test_left_join_keeps_unmatched_rows_with_null_right_values() -> void:
	var database := _create_database_with_relationship_data()
	var result := database.execute(
		database.query()
		.select()
		.from_table(&"heroes", &"h")
		.left_join(&"skills", _hero_skill_condition(), &"s")
		.project(GDSQLColumnExpression.new(&"name", &"h"), &"hero_name")
		.project(GDSQLColumnExpression.new(&"name", &"s"), &"skill_name")
		.order_by(
			GDSQLOrderClause.new(GDSQLColumnExpression.new(&"id", &"h")),
		)
		.build(),
	)

	assert_bool(result.is_successful()).is_true()
	assert_int(result.get_returned_rows()).is_equal(4)
	assert_str(result.rows[3].get_value(&"hero_name")).is_equal("Rogue")
	assert_object(result.rows[3].get_value(&"skill_name")).is_null()
	assert_bool(result.get_schema().get_column(&"skill_name").nullable).is_true()
	#for row in result.rows:
	#print(row.values)


func test_chained_joins_bind_columns_from_prior_and_new_sources() -> void:
	var database := _create_database_with_relationship_data()
	var result := database.execute(
		database.query()
		.select()
		.from_table(&"heroes", &"h")
		.join_table(&"skills", _hero_skill_condition(), &"s")
		.join_table(
			&"skill_effects",
			GDSQLComparisonExpression.new(
				GDSQLColumnExpression.new(&"id", &"s"),
				GDSQLComparisonExpression.ComparisonOperator.EQUAL,
				GDSQLColumnExpression.new(&"skill_id", &"e"),
			),
			&"e",
		)
		.project(GDSQLColumnExpression.new(&"name", &"h"), &"hero_name")
		.project(GDSQLColumnExpression.new(&"name", &"s"), &"skill_name")
		.project(GDSQLColumnExpression.new(&"effect", &"e"))
		.order_by(
			GDSQLOrderClause.new(GDSQLColumnExpression.new(&"id", &"e")),
		)
		.build(),
	)
	#for row in result.rows:
	#print(row.values)

	assert_bool(result.is_successful()).is_true()
	assert_int(result.get_returned_rows()).is_equal(2)
	assert_str(result.rows[0].get_value(&"skill_name")).is_equal("Sword")
	assert_str(result.rows[0].get_value(&"effect")).is_equal("bleed")
	assert_str(result.rows[1].get_value(&"hero_name")).is_equal("Mage")


func test_join_without_projections_uses_qualified_output_names() -> void:
	var database := _create_database_with_relationship_data()
	var result := database.execute(
		database.query()
		.select()
		.from_table(&"heroes", &"h")
		.join_table(&"skills", _hero_skill_condition(), &"s")
		.limit(1)
		.build(),
	)

	#for row in result.rows:
	#print(row.values)

	assert_bool(result.is_successful()).is_true()
	assert_bool(result.rows[0].has_column(&"h.name")).is_true()
	assert_bool(result.rows[0].has_column(&"s.name")).is_true()
	assert_str(result.rows[0].get_value(&"h.name")).is_equal("Knight")
	assert_str(result.rows[0].get_value(&"s.name")).is_equal("Sword")


func test_self_join_distinguishes_two_aliases_of_the_same_table() -> void:
	var employees := GDSQLTableDefinition.new(&"employees", &"id")
	employees.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true))
	employees.add_column(GDSQLColumnDefinition.new(&"manager_id", TYPE_INT, true))
	employees.add_column(GDSQLColumnDefinition.new(&"name", TYPE_STRING, false))
	var database := TestDatabase.create_database(_data_root, employees)
	TestDatabase.insert_rows(
		database,
		[
			{ &"id": 1, &"manager_id": null, &"name": "Archmage" },
			{ &"id": 2, &"manager_id": 1, &"name": "Apprentice" },
		],
		&"employees",
	)
	var result := database.execute(
		database.query()
		.select()
		.from_table(&"employees", &"employee")
		.join_table(
			&"employees",
			GDSQLComparisonExpression.new(
				GDSQLColumnExpression.new(&"manager_id", &"employee"),
				GDSQLComparisonExpression.ComparisonOperator.EQUAL,
				GDSQLColumnExpression.new(&"id", &"manager"),
			),
			&"manager",
		)
		.project(GDSQLColumnExpression.new(&"name", &"employee"), &"employee_name")
		.project(GDSQLColumnExpression.new(&"name", &"manager"), &"manager_name")
		.build(),
	)

	#for row in result.rows:
	#print(row.values)

	assert_bool(result.is_successful()).is_true()
	assert_int(result.get_returned_rows()).is_equal(1)
	assert_str(result.rows[0].get_value(&"employee_name")).is_equal("Apprentice")
	assert_str(result.rows[0].get_value(&"manager_name")).is_equal("Archmage")


func test_unqualified_duplicate_column_is_rejected_as_ambiguous() -> void:
	var database := _create_database_with_relationship_data()
	var result := database.execute(
		database.query()
		.select()
		.from_table(&"heroes", &"h")
		.join_table(&"skills", _hero_skill_condition(), &"s")
		.project(GDSQLColumnExpression.new(&"name"))
		.build(),
	)

	#result.diagnostics.print_to_debug()

	assert_bool(result.is_successful()).is_false()
	assert_str(String(result.diagnostics.entries[0].code)).is_equal(
		"GDSQL_VALIDATION_AMBIGUOUS_COLUMN",
	)


func test_right_join_is_scaffolded_with_an_unsupported_diagnostic() -> void:
	var database := _create_database_with_relationship_data()
	var result := database.execute(
		database.query()
		.select()
		.from_table(&"heroes", &"h")
		.join_table(
			&"skills",
			_hero_skill_condition(),
			&"s",
			GDSQLJoinSpec.JoinType.RIGHT,
		)
		.build(),
	)

	assert_bool(result.is_successful()).is_false()
	assert_str(String(result.diagnostics.entries[0].code)).is_equal(
		"GDSQL_VALIDATION_JOIN_TYPE_UNSUPPORTED",
	)


func _create_database_with_relationship_data() -> GDSQLDatabase:
	var heroes := GDSQLTableDefinition.new(&"heroes", &"id")
	heroes.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true))
	heroes.add_column(GDSQLColumnDefinition.new(&"name", TYPE_STRING, false))
	var skills := GDSQLTableDefinition.new(&"skills", &"id")
	skills.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true))
	skills.add_column(GDSQLColumnDefinition.new(&"hero_id", TYPE_INT, false))
	skills.add_column(GDSQLColumnDefinition.new(&"name", TYPE_STRING, false))
	var effects := GDSQLTableDefinition.new(&"skill_effects", &"id")
	effects.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true))
	effects.add_column(GDSQLColumnDefinition.new(&"skill_id", TYPE_INT, false))
	effects.add_column(GDSQLColumnDefinition.new(&"effect", TYPE_STRING, false))
	var database := TestDatabase.create_database_with_tables(
		_data_root,
		[heroes, skills, effects],
	)
	TestDatabase.insert_rows(
		database,
		[
			{ &"id": 1, &"name": "Knight" },
			{ &"id": 2, &"name": "Mage" },
			{ &"id": 3, &"name": "Rogue" },
		],
		&"heroes",
	)
	TestDatabase.insert_rows(
		database,
		[
			{ &"id": 1, &"hero_id": 1, &"name": "Sword" },
			{ &"id": 2, &"hero_id": 2, &"name": "Fireball" },
			{ &"id": 3, &"hero_id": 1, &"name": "Shield" },
		],
		&"skills",
	)
	TestDatabase.insert_rows(
		database,
		[
			{ &"id": 1, &"skill_id": 1, &"effect": "bleed" },
			{ &"id": 2, &"skill_id": 2, &"effect": "burn" },
		],
		&"skill_effects",
	)
	return database


func _hero_skill_condition() -> GDSQLComparisonExpression:
	return GDSQLComparisonExpression.new(
		GDSQLColumnExpression.new(&"id", &"h"),
		GDSQLComparisonExpression.ComparisonOperator.EQUAL,
		GDSQLColumnExpression.new(&"hero_id", &"s"),
	)
