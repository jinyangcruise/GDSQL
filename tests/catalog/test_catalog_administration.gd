class_name GDSQLCatalogAdministrationTest
extends GdUnitTestSuite

const TestDatabase = preload("res://tests/utils/gdsql_test_database.gd")

var _data_root: String
var _test_index := 0


func before_test() -> void:
	_test_index += 1
	_data_root = create_temp_dir("gdsql_catalog_management_%d" % _test_index)


func test_alter_table_migrates_existing_rows() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	TestDatabase.insert_basic_heroes(database)

	var alterations: Array[GDSQLTableAlteration] = [
		GDSQLTableAlteration.add_column(
			GDSQLColumnDefinition.new(&"level", TYPE_INT, false, false, false, 1),
		),
		GDSQLTableAlteration.rename_column(&"name", &"display_name"),
	]
	var result := database.alter_table(&"heroes", alterations)
	assert_bool(result.is_successful()).is_true()

	var table := database.context.catalog.get_table(&"game_config", &"heroes")
	assert_object(table.get_column(&"name")).is_null()
	assert_object(table.get_column(&"display_name")).is_not_null()
	assert_object(table.get_column(&"level")).is_not_null()
	var select_result := database.execute(database.query().select().from_table(&"heroes").build())
	assert_bool(select_result.is_successful()).is_true()
	assert_int(select_result.rows.size()).is_equal(2)
	for row in select_result.rows:
		assert_bool(row.has_column(&"name")).is_false()
		assert_bool(row.has_column(&"display_name")).is_true()
		assert_int(row.get_value(&"level")).is_equal(1)

	var drop_alterations: Array[GDSQLTableAlteration] = [
		GDSQLTableAlteration.drop_column(&"level"),
	]
	assert_bool(database.alter_table(&"heroes", drop_alterations).is_successful()).is_true()
	var dropped_table := database.context.catalog.get_table(&"game_config", &"heroes")
	assert_object(dropped_table.get_column(&"level")).is_null()
	var dropped_select := database.execute(database.query().select().from_table(&"heroes").build())
	for row in dropped_select.rows:
		assert_bool(row.has_column(&"level")).is_false()


func test_alter_table_rejects_primary_key_drop() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	var alterations: Array[GDSQLTableAlteration] = [
		GDSQLTableAlteration.drop_column(&"id"),
	]
	var result := database.alter_table(&"heroes", alterations)
	assert_bool(result.is_successful()).is_false()
	assert_str(String(result.diagnostics.entries[0].code)).is_equal("GDSQL_CATALOG_PRIMARY_KEY_DROP_FORBIDDEN")


func test_rename_and_drop_database_and_table() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	TestDatabase.insert_rows(database, [{&"id": 1, &"name": "Knight"}])

	assert_bool(database.rename_table(&"heroes", &"characters").is_successful()).is_true()
	assert_bool(database.context.catalog.has_table(&"game_config", &"heroes")).is_false()
	assert_bool(database.context.catalog.has_table(&"game_config", &"characters")).is_true()

	var rename_result := database.rename(&"game_data")
	assert_bool(rename_result.is_successful()).is_true()
	assert_str(String(database.database_name)).is_equal("game_data")
	assert_bool(GDSQLDatabase.open(&"game_config", _data_root).is_successful()).is_false()
	assert_bool(GDSQLDatabase.open(&"game_data", _data_root).is_successful()).is_true()
	var select_result := database.execute(database.query().select().from_table(&"characters").build())
	assert_bool(select_result.is_successful()).is_true()
	assert_int(select_result.rows.size()).is_equal(1)

	assert_bool(database.drop_table(&"characters").is_successful()).is_true()
	assert_bool(database.context.catalog.has_table(&"game_data", &"characters")).is_false()
	assert_bool(database.drop().is_successful()).is_true()
	assert_bool(GDSQLDatabase.open(&"game_data", _data_root).is_successful()).is_false()
	assert_bool(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_data_root.path_join("game_data")))).is_false()
