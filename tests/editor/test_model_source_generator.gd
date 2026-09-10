class_name GDSQLModelSourceGeneratorTest
extends GdUnitTestSuite

func test_builds_separate_generated_and_user_owned_content_scripts() -> void:
	var table := GDSQLTableDefinition.new(&"heroes", &"id")
	table.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false))
	table.add_column(GDSQLColumnDefinition.new(&"name", TYPE_STRING, false))
	table.add_column(GDSQLColumnDefinition.new(&"nickname", TYPE_STRING, true))

	var result := GDSQLModelSourceGenerator.new().build(
		table,
		&"Hero",
		GDSQLDatabaseRegistry.CONTENT_ROLE,
	)
	var source := result.get_value() as GDSQLModelSource

	assert_bool(result.is_successful()).is_true()
	assert_str(source.generated_path).is_equal(
		"res://models/generated/hero_model_generated.gd",
	)
	assert_str(source.user_path).is_equal("res://models/hero.gd")
	assert_str(source.generated_source).contains("extends GDSQLContentModel")
	assert_str(source.generated_source).contains("var id: int")
	assert_str(source.generated_source).contains("var name: String")
	assert_str(source.generated_source).contains("var nickname: Variant # String or null")
	assert_str(source.generated_source).contains("return &\"heroes\"")
	assert_str(source.user_source).contains(
		"extends \"res://models/generated/hero_model_generated.gd\"",
	)
	assert_str(source.user_source).contains("GDSQLModels.query(Hero)")


func test_custom_role_is_declared_by_the_generated_base() -> void:
	var table := GDSQLTableDefinition.new(&"events", &"event_id")
	table.add_column(GDSQLColumnDefinition.new(&"event_id", TYPE_STRING_NAME, false))

	var result := GDSQLModelSourceGenerator.new().build(
		table,
		&"AnalyticsEvent",
		&"analytics",
		"res://game/models/",
	)
	var source := result.get_value() as GDSQLModelSource

	assert_bool(result.is_successful()).is_true()
	assert_str(source.generated_source).contains("extends GDSQLModel")
	assert_str(source.generated_source).contains("func database_role() -> StringName:")
	assert_str(source.generated_source).contains("return &\"analytics\"")
	assert_str(source.generated_source).contains("var event_id: StringName")
	assert_str(source.generated_path).is_equal(
		"res://game/models/generated/analytics_event_model_generated.gd",
	)


func test_generated_base_is_valid_gdscript() -> void:
	var table := GDSQLTableDefinition.new(&"generated_test_records", &"id")
	table.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false))
	table.add_column(GDSQLColumnDefinition.new(&"payload", TYPE_DICTIONARY, false))
	var source := GDSQLModelSourceGenerator.new().build(
		table,
		&"GeneratedTestRecord",
		GDSQLDatabaseRegistry.SAVE_ROLE,
	).get_value() as GDSQLModelSource
	var script := GDScript.new()
	script.source_code = source.generated_source

	assert_int(script.reload()).is_equal(OK)


func test_rejects_columns_that_conflict_with_model_metadata() -> void:
	var table := GDSQLTableDefinition.new(&"broken", &"id")
	table.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false))
	table.add_column(GDSQLColumnDefinition.new(&"table_name", TYPE_STRING, false))

	var result := GDSQLModelSourceGenerator.new().build(
		table,
		&"Broken",
		GDSQLDatabaseRegistry.CONTENT_ROLE,
	)

	assert_bool(result.is_successful()).is_false()
	assert_str(String(result.diagnostics.entries[0].code)).is_equal(
		"GDSQL_MODEL_SOURCE_COLUMN_RESERVED",
	)


func test_rejects_plugin_source_as_a_model_destination() -> void:
	var table := GDSQLTableDefinition.new(&"heroes", &"id")
	table.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false))

	var result := GDSQLModelSourceGenerator.new().build(
		table,
		&"Hero",
		GDSQLDatabaseRegistry.CONTENT_ROLE,
		"res://models/../addons/gdsql/generated_models",
	)

	assert_bool(result.is_successful()).is_false()
	assert_str(String(result.diagnostics.entries[0].code)).is_equal(
		"GDSQL_MODEL_SOURCE_ROOT_INVALID",
	)
