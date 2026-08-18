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


func test_reorder_columns_changes_schema_order_without_rewriting_rows() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	TestDatabase.insert_basic_heroes(database)
	var table_path := _data_root.path_join("game_config/tables/heroes.cfg")
	var stored_rows := FileAccess.get_file_as_string(table_path)

	var result := database.alter_table(
		&"heroes",
		[GDSQLTableAlteration.reorder_columns([&"name", &"id"])],
	)
	assert_bool(result.is_successful()).is_true()
	assert_str(FileAccess.get_file_as_string(table_path)).is_equal(stored_rows)

	var reopened := GDSQLDatabase.open(&"game_config", _data_root).get_database()
	var table := reopened.context.catalog.get_table(&"game_config", &"heroes")
	assert_str(String(table.columns[0].name)).is_equal("name")
	assert_str(String(table.columns[1].name)).is_equal("id")


func test_alter_table_rejects_primary_key_drop() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	var alterations: Array[GDSQLTableAlteration] = [
		GDSQLTableAlteration.drop_column(&"id"),
	]
	var result := database.alter_table(&"heroes", alterations)
	assert_bool(result.is_successful()).is_false()
	assert_str(String(result.diagnostics.entries[0].code)).is_equal("GDSQL_CATALOG_PRIMARY_KEY_DROP_FORBIDDEN")


func test_database_workspace_contains_only_schema_and_tables() -> void:
	TestDatabase.create_heroes_database(_data_root)
	var database_path := _data_root.path_join("game_config")
	assert_bool(DirAccess.dir_exists_absolute(database_path.path_join("schema"))).is_true()
	assert_bool(DirAccess.dir_exists_absolute(database_path.path_join("tables"))).is_true()
	assert_bool(DirAccess.dir_exists_absolute(database_path.path_join("mappers"))).is_false()
	assert_bool(DirAccess.dir_exists_absolute(database_path.path_join("graphs"))).is_false()


func test_alter_table_updates_column_metadata_and_indexes() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	TestDatabase.insert_basic_heroes(database)
	var index := GDSQLIndexDefinition.new(&"heroes_name", [&"name"], true)
	var alterations: Array[GDSQLTableAlteration] = [
		GDSQLTableAlteration.set_column_default(&"name", "Unknown"),
		GDSQLTableAlteration.set_column_unique(&"name", true),
		GDSQLTableAlteration.add_index(index),
	]
	var result := database.alter_table(&"heroes", alterations)
	assert_bool(result.is_successful()).is_true()

	var reopened := GDSQLDatabase.open(&"game_config", _data_root).get_database()
	var table := reopened.context.catalog.get_table(&"game_config", &"heroes")
	assert_bool(table.get_column(&"name").has_default()).is_true()
	assert_str(table.get_column(&"name").get_default_value()).is_equal("Unknown")
	assert_bool(table.get_column(&"name").unique).is_true()
	assert_object(table.get_index(&"heroes_name")).is_not_null()
	var selected := reopened.execute(
		reopened.query().select().from_table(&"heroes") \
			.where(GDSQLExpr.column(&"name").equals("Mage")) \
			.build(),
	)
	assert_bool(selected.is_successful()).is_true()
	assert_int(selected.rows.size()).is_equal(1)
	assert_bool(
		reopened.alter_table(
			&"heroes",
			[GDSQLTableAlteration.drop_index(&"heroes_name")],
		).is_successful(),
	).is_true()


func test_alter_table_rejects_constraints_violated_by_existing_rows() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	TestDatabase.insert_rows(
		database,
		[
			{&"id": 1, &"name": "Mage"},
			{&"id": 2, &"name": "Mage"},
		],
	)
	var result := database.alter_table(
		&"heroes",
		[GDSQLTableAlteration.set_column_unique(&"name", true)],
	)
	assert_bool(result.is_successful()).is_false()
	assert_str(String(result.diagnostics.entries[0].code)) \
		.is_equal("GDSQL_CATALOG_DUPLICATE_UNIQUE_VALUE")


func test_change_plan_previews_applies_and_detects_stale_schema() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	TestDatabase.insert_basic_heroes(database)
	var preview := database.preview_alter_table(
		&"heroes",
		[GDSQLTableAlteration.drop_column(&"name")],
	)
	assert_bool(preview.is_successful()).is_true()
	var plan := preview.get_value() as GDSQLCatalogChangePlan
	assert_bool(plan.requires_confirmation()).is_true()
	assert_int(plan.affected_rows).is_equal(2)
	assert_object(
		database.context.catalog.get_table(&"game_config", &"heroes").get_column(&"name"),
	).is_not_null()

	assert_bool(
		database.alter_table(
			&"heroes",
			[
				GDSQLTableAlteration.add_column(
					GDSQLColumnDefinition.new(&"level", TYPE_INT, true),
				),
			],
		).is_successful(),
	).is_true()
	var stale := database.apply_change_plan(plan)
	assert_bool(stale.is_successful()).is_false()
	assert_str(String(stale.diagnostics.entries[0].code)) \
		.is_equal("GDSQL_CATALOG_CHANGE_PLAN_STALE")


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


func test_unregister_preserves_and_reloads_existing_database_files() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	TestDatabase.insert_rows(database, [{&"id": 1, &"name": "Knight"}])
	var database_path := _data_root.path_join("game_config")

	assert_bool(database.unregister().is_successful()).is_true()
	assert_bool(GDSQLDatabase.open(&"game_config", _data_root).is_successful()).is_false()
	assert_bool(DirAccess.dir_exists_absolute(database_path)).is_true()
	assert_bool(FileAccess.file_exists(database_path.path_join("schema/heroes.cfg"))).is_true()
	assert_bool(FileAccess.file_exists(database_path.path_join("tables/heroes.cfg"))).is_true()

	var registered_again := GDSQLDatabase.create(&"game_config", _data_root)
	assert_bool(registered_again.is_successful()).is_true()
	var reloaded := registered_again.get_database()
	var selected := reloaded.execute(
		reloaded.query().select().from_table(&"heroes").build(),
	)
	assert_bool(selected.is_successful()).is_true()
	assert_int(selected.rows.size()).is_equal(1)
	assert_str(selected.rows[0].get_value(&"name")).is_equal("Knight")
