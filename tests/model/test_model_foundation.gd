class_name GDSQLModelFoundationTest
extends GdUnitTestSuite

const TestDatabase = preload("res://tests/utils/gdsql_test_database.gd")

var _data_root: String
var _test_index := 0


func before_test() -> void:
	GDSQLModels.clear_context()
	_test_index += 1
	_data_root = create_temp_dir("gdsql_model_foundation_%d" % _test_index)


func after_test() -> void:
	GDSQLModels.clear_context()


func test_model_query_resolves_role_and_materializes_registered_models() -> void:
	var database := TestDatabase.create_heroes_database(_data_root, true)
	TestDatabase.insert_rows(
		database,
		[
			{ &"id": 1, &"name": "Knight", &"level": 3 },
			{ &"id": 2, &"name": "Mage", &"level": 5 },
		],
	)
	var context := _create_context(database, TestHero)
	assert_bool(GDSQLModels.configure(context).is_successful()).is_true()

	var result := TestHero.query() \
			.where(GDSQLExpr.column(&"level").greater_than(3)) \
			.order_by(&"id") \
			.all()
	var heroes: Array = result.get_value()

	assert_bool(result.is_successful()).is_true()
	assert_int(heroes.size()).is_equal(1)
	assert_object(heroes[0]).is_instanceof(TestHero)
	assert_int(heroes[0].id).is_equal(2)
	assert_str(heroes[0].name).is_equal("Mage")
	assert_bool(heroes[0].is_persisted()).is_true()
	assert_object(heroes[0].get_model_context()).is_same(context)


func test_find_uses_registered_primary_key_and_returns_one_model() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	TestDatabase.insert_basic_heroes(database)
	var context := _create_context(database, TestHero)
	assert_bool(GDSQLModels.configure(context).is_successful()).is_true()

	var result := TestHero.find(1)
	var hero := result.get_value() as TestHero

	assert_bool(result.is_successful()).is_true()
	assert_object(hero).is_instanceof(TestHero)
	assert_int(hero.id).is_equal(1)
	assert_str(hero.name).is_equal("Knight")


func test_standard_model_types_capture_roles_and_access_modes() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	var database_registry := GDSQLDatabaseRegistry.new()
	database_registry.register(&"active", database)
	database_registry.bind_role(GDSQLDatabaseRegistry.CONTENT_ROLE, &"active")
	var registry := GDSQLModelRegistry.new(database_registry)

	var content := registry.register(TestHero).get_value() as GDSQLModelDefinition
	var save := registry.register(TestSaveHero).get_value() as GDSQLModelDefinition
	var settings := registry.register(TestSetting).get_value() as GDSQLModelDefinition

	assert_str(String(content.database_role)).is_equal("content")
	assert_int(content.access_mode).is_equal(GDSQLModelAccess.Mode.READ_ONLY)
	assert_str(String(save.database_role)).is_equal("save")
	assert_int(save.access_mode).is_equal(GDSQLModelAccess.Mode.READ_WRITE)
	assert_str(String(settings.database_role)).is_equal("settings")
	assert_int(settings.access_mode).is_equal(GDSQLModelAccess.Mode.READ_WRITE)


func test_static_query_reports_missing_default_context() -> void:
	var result := TestHero.query().all()

	assert_bool(result.is_successful()).is_false()
	assert_str(String(result.diagnostics.entries[0].code)).is_equal(
		"GDSQL_MODEL_CONTEXT_REQUIRED",
	)


func test_materialized_save_updates_changed_fields() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	TestDatabase.insert_basic_heroes(database)
	var context := _create_context(
		database,
		TestSaveHero,
		GDSQLDatabaseRegistry.SAVE_ROLE,
	)
	GDSQLModels.configure(context)
	var hero := TestSaveHero.find(1).get_value() as TestSaveHero

	hero.name = "Paladin"
	var result := hero.save()
	var selected := database.execute(
		database.table(&"heroes").select()
		.where(GDSQLExpr.column(&"id").equals(1))
		.build(),
	)

	assert_bool(result.is_successful()).is_true()
	assert_int(result.get_affected_rows()).is_equal(1)
	assert_str(selected.rows[0].get_value(&"name")).is_equal("Paladin")


func test_materialized_refresh_reloads_the_same_instance() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	TestDatabase.insert_basic_heroes(database)
	var context := _create_context(
		database,
		TestSaveHero,
		GDSQLDatabaseRegistry.SAVE_ROLE,
	)
	GDSQLModels.configure(context)
	var hero := TestSaveHero.find(2).get_value() as TestSaveHero
	database.execute(
		database.table(&"heroes").update()
		.set_value(&"name", "Wizard")
		.where(GDSQLExpr.column(&"id").equals(2))
		.build(),
	)

	var result := hero.refresh()

	assert_bool(result.is_successful()).is_true()
	assert_object(result.get_value()).is_same(hero)
	assert_str(hero.name).is_equal("Wizard")


func test_materialized_delete_clears_persisted_state() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	TestDatabase.insert_basic_heroes(database)
	var context := _create_context(
		database,
		TestSaveHero,
		GDSQLDatabaseRegistry.SAVE_ROLE,
	)
	GDSQLModels.configure(context)
	var hero := TestSaveHero.find(1).get_value() as TestSaveHero

	var result := hero.delete()
	var remaining := database.execute(database.table(&"heroes").select().build())

	assert_bool(result.is_successful()).is_true()
	assert_int(result.get_affected_rows()).is_equal(1)
	assert_bool(hero.is_persisted()).is_false()
	assert_int(remaining.get_returned_rows()).is_equal(1)


func test_content_model_rejects_mutation() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	TestDatabase.insert_basic_heroes(database)
	var context := _create_context(database, TestHero)
	GDSQLModels.configure(context)
	var hero := TestHero.find(1).get_value() as TestHero

	hero.name = "Changed"
	var result := hero.save()

	assert_bool(result.is_successful()).is_false()
	assert_str(String(result.diagnostics.entries[0].code)).is_equal(
		"GDSQL_MODEL_READ_ONLY",
	)


func _create_context(
		database: GDSQLDatabase,
		model_script: Script,
		role: StringName = GDSQLDatabaseRegistry.CONTENT_ROLE,
) -> GDSQLModelContext:
	var database_registry := GDSQLDatabaseRegistry.new()
	assert_bool(database_registry.register(&"active", database).is_successful()).is_true()
	assert_bool(
		database_registry.bind_role(role, &"active")
		.is_successful(),
	).is_true()
	var model_registry := GDSQLModelRegistry.new(database_registry)
	assert_bool(model_registry.register(model_script).is_successful()).is_true()
	return GDSQLModelContext.new(model_registry)


class TestHero extends GDSQLContentModel:
	var id: int
	var name: String
	var level: int


	func table_name() -> StringName:
		return &"heroes"


	static func query() -> GDSQLModelQuery:
		return GDSQLModels.query(TestHero)


	static func find(identity: Variant) -> GDSQLQueryResult:
		return GDSQLModels.find(TestHero, identity)


class TestSaveHero extends GDSQLSaveModel:
	var id: int
	var name: String


	static func query() -> GDSQLModelQuery:
		return GDSQLModels.query(TestSaveHero)


	static func find(identity: Variant) -> GDSQLQueryResult:
		return query().find(identity)


	func table_name() -> StringName:
		return &"heroes"


class TestSetting extends GDSQLSettingsModel:
	func table_name() -> StringName:
		return &"settings"
