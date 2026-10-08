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


func test_catalog_reopen_recovers_an_interrupted_schema_table_activation() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	TestDatabase.insert_basic_heroes(database)
	var resolver := GDSQLDatabasePathResolver.new(_data_root)
	var schema_path := resolver.resolve_schema_path(
		database.database_name,
		&"heroes",
	)
	var table_path := resolver.resolve_table_path(
		database.database_name,
		&"heroes",
	)
	var staged_schema := ConfigFile.new()
	assert_int(staged_schema.load(schema_path)).is_equal(OK)
	staged_schema.set_value("column:level", "type", TYPE_INT)
	staged_schema.set_value("column:level", "nullable", false)
	staged_schema.set_value("column:level", "unique", false)
	staged_schema.set_value("column:level", "auto_increment", false)
	staged_schema.set_value(
		"column:level",
		"generation",
		GDSQLColumnDefinition.Generation.NONE,
	)
	var staged_table := ConfigFile.new()
	assert_int(staged_table.load(table_path)).is_equal(OK)
	staged_table.set_value("2", "name", "Wizard")
	assert_int(staged_schema.save(schema_path + ".building")).is_equal(OK)
	assert_int(staged_table.save(table_path + ".building")).is_equal(OK)
	assert_int(
		DirAccess.rename_absolute(
			ProjectSettings.globalize_path(table_path),
			ProjectSettings.globalize_path(table_path + ".previous"),
		),
	).is_equal(OK)
	assert_int(
		DirAccess.rename_absolute(
			ProjectSettings.globalize_path(schema_path),
			ProjectSettings.globalize_path(schema_path + ".previous"),
		),
	).is_equal(OK)
	assert_int(
		DirAccess.rename_absolute(
			ProjectSettings.globalize_path(table_path + ".building"),
			ProjectSettings.globalize_path(table_path),
		),
	).is_equal(OK)

	var reopened_result := GDSQLDatabase.open(database.database_name, _data_root)

	assert_bool(reopened_result.is_successful()).is_true()
	var reopened := reopened_result.get_database()
	var table := reopened.context.catalog.get_table(
		database.database_name,
		&"heroes",
	)
	assert_object(table.get_column(&"level")).is_null()
	var selected := reopened.execute(
		reopened.query().table(&"heroes").select().order_by_column(&"id").build(),
	)
	assert_int(selected.rows.size()).is_equal(2)
	assert_str(selected.rows[1].get_value(&"name")).is_equal("Mage")
	for path in [schema_path, table_path]:
		assert_bool(FileAccess.file_exists(path + ".building")).is_false()
		assert_bool(FileAccess.file_exists(path + ".previous")).is_false()


func test_catalog_reopen_rolls_back_an_interrupted_table_rename() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	TestDatabase.insert_rows(database, [{ &"id": 1, &"name": "Knight" }])
	var resolver := GDSQLDatabasePathResolver.new(_data_root)
	var old_schema := resolver.resolve_schema_path(database.database_name, &"heroes")
	var old_table := resolver.resolve_table_path(database.database_name, &"heroes")
	var new_schema := resolver.resolve_schema_path(database.database_name, &"characters")
	var new_table := resolver.resolve_table_path(database.database_name, &"characters")
	var staged_schema := ConfigFile.new()
	assert_int(staged_schema.load(old_schema)).is_equal(OK)
	staged_schema.set_value("table", "name", "characters")
	assert_int(staged_schema.save(new_schema + ".building")).is_equal(OK)
	var marker := _write_lifecycle_marker(
		resolver,
		database.database_name,
		"rename_table",
		&"heroes",
		&"characters",
		false,
	)
	assert_int(_rename_file(old_table, new_table)).is_equal(OK)
	assert_int(_rename_file(old_schema, old_schema + ".previous")).is_equal(OK)

	var reopened_result := GDSQLDatabase.open(database.database_name, _data_root)

	assert_bool(reopened_result.is_successful()).is_true()
	var reopened := reopened_result.get_database()
	assert_bool(reopened.context.catalog.has_table(database.database_name, &"heroes")).is_true()
	assert_bool(reopened.context.catalog.has_table(database.database_name, &"characters")).is_false()
	var selected := reopened.execute(
		reopened.query().table(&"heroes").select().build(),
	)
	assert_int(selected.rows.size()).is_equal(1)
	assert_str(selected.rows[0].get_value(&"name")).is_equal("Knight")
	assert_bool(FileAccess.file_exists(new_schema + ".building")).is_false()
	assert_bool(FileAccess.file_exists(old_schema + ".previous")).is_false()
	assert_bool(FileAccess.file_exists(marker)).is_false()


func test_catalog_reopen_finishes_a_committed_table_rename() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	TestDatabase.insert_rows(database, [{ &"id": 1, &"name": "Knight" }])
	var resolver := GDSQLDatabasePathResolver.new(_data_root)
	var old_schema := resolver.resolve_schema_path(database.database_name, &"heroes")
	var old_table := resolver.resolve_table_path(database.database_name, &"heroes")
	var new_schema := resolver.resolve_schema_path(database.database_name, &"characters")
	var new_table := resolver.resolve_table_path(database.database_name, &"characters")
	var renamed_schema := ConfigFile.new()
	assert_int(renamed_schema.load(old_schema)).is_equal(OK)
	renamed_schema.set_value("table", "name", "characters")
	assert_int(renamed_schema.save(new_schema)).is_equal(OK)
	var marker := _write_lifecycle_marker(
		resolver,
		database.database_name,
		"rename_table",
		&"heroes",
		&"characters",
		true,
	)
	assert_int(_rename_file(old_table, new_table)).is_equal(OK)
	assert_int(_rename_file(old_schema, old_schema + ".previous")).is_equal(OK)

	var reopened_result := GDSQLDatabase.open(database.database_name, _data_root)

	assert_bool(reopened_result.is_successful()).is_true()
	var reopened := reopened_result.get_database()
	assert_bool(reopened.context.catalog.has_table(database.database_name, &"heroes")).is_false()
	assert_bool(reopened.context.catalog.has_table(database.database_name, &"characters")).is_true()
	var selected := reopened.execute(
		reopened.query().table(&"characters").select().build(),
	)
	assert_int(selected.rows.size()).is_equal(1)
	assert_str(selected.rows[0].get_value(&"name")).is_equal("Knight")
	assert_bool(FileAccess.file_exists(old_schema + ".previous")).is_false()
	assert_bool(FileAccess.file_exists(marker)).is_false()


func test_catalog_reopen_rolls_back_an_interrupted_table_drop() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	TestDatabase.insert_rows(database, [{ &"id": 1, &"name": "Knight" }])
	var resolver := GDSQLDatabasePathResolver.new(_data_root)
	var table_path := resolver.resolve_table_path(database.database_name, &"heroes")
	var marker := _write_lifecycle_marker(
		resolver,
		database.database_name,
		"drop_table",
		&"heroes",
		&"",
		false,
	)
	assert_int(_rename_file(table_path, table_path + ".dropping")).is_equal(OK)

	var reopened_result := GDSQLDatabase.open(database.database_name, _data_root)

	assert_bool(reopened_result.is_successful()).is_true()
	var reopened := reopened_result.get_database()
	assert_bool(reopened.context.catalog.has_table(database.database_name, &"heroes")).is_true()
	var selected := reopened.execute(
		reopened.query().table(&"heroes").select().build(),
	)
	assert_int(selected.rows.size()).is_equal(1)
	assert_bool(FileAccess.file_exists(table_path + ".dropping")).is_false()
	assert_bool(FileAccess.file_exists(marker)).is_false()


func test_catalog_reopen_finishes_a_committed_table_drop() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	var resolver := GDSQLDatabasePathResolver.new(_data_root)
	var schema_path := resolver.resolve_schema_path(database.database_name, &"heroes")
	var table_path := resolver.resolve_table_path(database.database_name, &"heroes")
	var marker := _write_lifecycle_marker(
		resolver,
		database.database_name,
		"drop_table",
		&"heroes",
		&"",
		true,
	)
	assert_int(_rename_file(schema_path, schema_path + ".dropping")).is_equal(OK)
	assert_int(_rename_file(table_path, table_path + ".dropping")).is_equal(OK)

	var reopened_result := GDSQLDatabase.open(database.database_name, _data_root)

	assert_bool(reopened_result.is_successful()).is_true()
	var reopened := reopened_result.get_database()
	assert_bool(reopened.context.catalog.has_table(database.database_name, &"heroes")).is_false()
	assert_bool(FileAccess.file_exists(schema_path + ".dropping")).is_false()
	assert_bool(FileAccess.file_exists(table_path + ".dropping")).is_false()
	assert_bool(FileAccess.file_exists(marker)).is_false()


func test_catalog_reopen_rolls_back_an_interrupted_database_rename() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	TestDatabase.insert_rows(database, [{ &"id": 1, &"name": "Knight" }])
	var resolver := GDSQLDatabasePathResolver.new(_data_root)
	var registry_path := resolver.resolve_catalog_path()
	var old_path := resolver.resolve_database_path(&"game_config")
	var new_path := resolver.resolve_database_path(&"game_data")
	_stage_database_registry(resolver, &"game_config", &"game_data")
	var marker := _write_database_lifecycle_marker(
		resolver,
		"rename_database",
		&"game_config",
		&"game_data",
		false,
	)
	assert_int(_rename_file(old_path, new_path)).is_equal(OK)
	_activate_staged_database_registry(registry_path)

	var reopened_result := GDSQLDatabase.open(&"game_config", _data_root)

	assert_bool(reopened_result.is_successful()).is_true()
	assert_bool(GDSQLDatabase.open(&"game_data", _data_root).is_successful()).is_false()
	var selected := reopened_result.get_database().execute(
		reopened_result.get_database().query().table(&"heroes").select().build(),
	)
	assert_int(selected.rows.size()).is_equal(1)
	assert_str(selected.rows[0].get_value(&"name")).is_equal("Knight")
	assert_bool(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(old_path))).is_true()
	assert_bool(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(new_path))).is_false()
	_assert_database_lifecycle_artifacts_removed(registry_path, marker)


func test_catalog_reopen_discards_an_unactivated_database_registry_stage() -> void:
	TestDatabase.create_heroes_database(_data_root)
	var resolver := GDSQLDatabasePathResolver.new(_data_root)
	var registry_path := resolver.resolve_catalog_path()
	_stage_database_registry(resolver, &"game_config", &"game_data")

	var reopened_result := GDSQLDatabase.open(&"game_config", _data_root)

	assert_bool(reopened_result.is_successful()).is_true()
	assert_bool(GDSQLDatabase.open(&"game_data", _data_root).is_successful()).is_false()
	assert_bool(FileAccess.file_exists(registry_path + ".building")).is_false()


func test_catalog_reopen_finishes_a_committed_database_rename() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	TestDatabase.insert_rows(database, [{ &"id": 1, &"name": "Knight" }])
	var resolver := GDSQLDatabasePathResolver.new(_data_root)
	var registry_path := resolver.resolve_catalog_path()
	var old_path := resolver.resolve_database_path(&"game_config")
	var new_path := resolver.resolve_database_path(&"game_data")
	_stage_database_registry(resolver, &"game_config", &"game_data")
	var marker := _write_database_lifecycle_marker(
		resolver,
		"rename_database",
		&"game_config",
		&"game_data",
		true,
	)
	assert_int(_rename_file(old_path, new_path)).is_equal(OK)
	_activate_staged_database_registry(registry_path)

	var reopened_result := GDSQLDatabase.open(&"game_data", _data_root)

	assert_bool(reopened_result.is_successful()).is_true()
	assert_bool(GDSQLDatabase.open(&"game_config", _data_root).is_successful()).is_false()
	var selected := reopened_result.get_database().execute(
		reopened_result.get_database().query().table(&"heroes").select().build(),
	)
	assert_int(selected.rows.size()).is_equal(1)
	assert_str(selected.rows[0].get_value(&"name")).is_equal("Knight")
	assert_bool(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(old_path))).is_false()
	assert_bool(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(new_path))).is_true()
	_assert_database_lifecycle_artifacts_removed(registry_path, marker)


func test_catalog_reopen_rolls_back_an_interrupted_database_drop() -> void:
	TestDatabase.create_heroes_database(_data_root)
	var resolver := GDSQLDatabasePathResolver.new(_data_root)
	var registry_path := resolver.resolve_catalog_path()
	var database_path := resolver.resolve_database_path(&"game_config")
	var dropping_path := database_path + ".dropping"
	_stage_database_registry(resolver, &"game_config")
	var marker := _write_database_lifecycle_marker(
		resolver,
		"drop_database",
		&"game_config",
		&"",
		false,
	)
	assert_int(_rename_file(database_path, dropping_path)).is_equal(OK)
	_activate_staged_database_registry(registry_path)

	var reopened_result := GDSQLDatabase.open(&"game_config", _data_root)

	assert_bool(reopened_result.is_successful()).is_true()
	assert_bool(
		DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(database_path)),
	).is_true()
	assert_bool(
		DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dropping_path)),
	).is_false()
	_assert_database_lifecycle_artifacts_removed(registry_path, marker)


func test_catalog_reopen_finishes_a_committed_database_drop() -> void:
	TestDatabase.create_heroes_database(_data_root)
	var resolver := GDSQLDatabasePathResolver.new(_data_root)
	var registry_path := resolver.resolve_catalog_path()
	var database_path := resolver.resolve_database_path(&"game_config")
	var dropping_path := database_path + ".dropping"
	_stage_database_registry(resolver, &"game_config")
	var marker := _write_database_lifecycle_marker(
		resolver,
		"drop_database",
		&"game_config",
		&"",
		true,
	)
	assert_int(_rename_file(database_path, dropping_path)).is_equal(OK)
	_activate_staged_database_registry(registry_path)

	var reopened_result := GDSQLDatabase.open(&"game_config", _data_root)

	assert_bool(reopened_result.is_successful()).is_false()
	assert_bool(
		DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(database_path)),
	).is_false()
	assert_bool(
		DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dropping_path)),
	).is_false()
	_assert_database_lifecycle_artifacts_removed(registry_path, marker)


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


func test_foreign_key_metadata_round_trips_with_the_table_schema() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	var skills := GDSQLTableDefinition.new(&"skills", &"id")
	skills.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true))
	skills.add_column(GDSQLColumnDefinition.new(&"hero_id", TYPE_INT, false))
	skills.add_foreign_key(
		GDSQLForeignKeyDefinition.new(
			&"skills_hero",
			&"hero_id",
			&"heroes",
			&"id",
		),
	)

	assert_bool(database.create_table(skills).is_successful()).is_true()
	var reopened := GDSQLDatabase.open(&"game_config", _data_root).get_database()
	var stored := reopened.context.catalog.get_table(&"game_config", &"skills")
	var foreign_key := stored.get_foreign_key(&"skills_hero")

	assert_object(foreign_key).is_not_null()
	assert_str(String(foreign_key.column)).is_equal("hero_id")
	assert_str(String(foreign_key.referenced_table)).is_equal("heroes")
	assert_str(String(foreign_key.referenced_column)).is_equal("id")
	assert_int(foreign_key.on_delete).is_equal(
		GDSQLForeignKeyDefinition.Action.RESTRICT,
	)
	assert_array(stored.get_foreign_keys_for_column(&"hero_id")).has_size(1)


func test_foreign_key_metadata_rejects_an_unknown_local_column() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	var skills := GDSQLTableDefinition.new(&"skills", &"id")
	skills.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true))
	skills.add_foreign_key(
		GDSQLForeignKeyDefinition.new(
			&"skills_hero",
			&"hero_id",
			&"heroes",
			&"id",
		),
	)

	var result := database.create_table(skills)

	assert_bool(result.is_successful()).is_false()
	assert_str(String(result.diagnostics.entries[0].code)).is_equal(
		"GDSQL_CATALOG_FOREIGN_KEY_UNKNOWN_COLUMN",
	)


func test_foreign_key_requires_a_supported_matching_unique_target() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	var unsupported := _referencing_table(&"unsupported", TYPE_FLOAT, &"heroes", &"id")
	var mismatched := _referencing_table(&"mismatched", TYPE_STRING, &"heroes", &"id")
	var not_unique := _referencing_table(&"not_unique", TYPE_STRING, &"heroes", &"name")

	var unsupported_result := database.create_table(unsupported)
	var mismatched_result := database.create_table(mismatched)
	var not_unique_result := database.create_table(not_unique)

	assert_str(String(unsupported_result.diagnostics.entries[0].code)).is_equal(
		"GDSQL_CATALOG_FOREIGN_KEY_UNSUPPORTED_TYPE",
	)
	assert_str(String(mismatched_result.diagnostics.entries[0].code)).is_equal(
		"GDSQL_CATALOG_FOREIGN_KEY_TYPE_MISMATCH",
	)
	assert_str(String(not_unique_result.diagnostics.entries[0].code)).is_equal(
		"GDSQL_CATALOG_FOREIGN_KEY_TARGET_NOT_UNIQUE",
	)
	assert_bool(
		database.alter_table(
			&"heroes",
			[
				GDSQLTableAlteration.add_index(
					GDSQLIndexDefinition.new(&"heroes_name", [&"name"], true),
				),
			],
		).is_successful(),
	).is_true()
	assert_bool(
		database.create_table(
			_referencing_table(&"indexed_target", TYPE_STRING, &"heroes", &"name"),
		).is_successful(),
	).is_true()


func test_foreign_key_rejects_an_unknown_target_table() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	var skills := _referencing_table(&"skills", TYPE_INT, &"missing", &"id")

	var result := database.create_table(skills)

	assert_bool(result.is_successful()).is_false()
	assert_str(String(result.diagnostics.entries[0].code)).is_equal(
		"GDSQL_CATALOG_FOREIGN_KEY_UNKNOWN_TABLE",
	)


func test_foreign_key_alteration_validates_rows_and_round_trips() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	TestDatabase.insert_rows(database, [{ &"id": 1, &"name": "Mage" }])
	var skills := _referencing_table(&"skills")
	skills.foreign_keys.clear()
	assert_bool(database.create_table(skills).is_successful()).is_true()
	TestDatabase.insert_rows(database, [{ &"id": 10, &"reference_id": 1 }], &"skills")
	var foreign_key := GDSQLForeignKeyDefinition.new(
		&"skills_reference",
		&"reference_id",
		&"heroes",
		&"id",
	)

	var added := database.alter_table(
		&"skills",
		[GDSQLTableAlteration.add_foreign_key(foreign_key)],
	)
	var stored := database.context.catalog.get_table(&"game_config", &"skills")

	assert_bool(added.is_successful()).is_true()
	assert_object(stored.get_foreign_key(&"skills_reference")).is_not_null()
	assert_bool(
		database.alter_table(
			&"skills",
			[GDSQLTableAlteration.drop_foreign_key(&"skills_reference")],
		).is_successful(),
	).is_true()
	assert_object(
		database.context.catalog.get_table(&"game_config", &"skills") \
				.get_foreign_key(&"skills_reference"),
	).is_null()


func test_foreign_key_alteration_rejects_existing_orphans() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	TestDatabase.insert_rows(database, [{ &"id": 1, &"name": "Mage" }])
	var skills := _referencing_table(&"skills")
	skills.foreign_keys.clear()
	assert_bool(database.create_table(skills).is_successful()).is_true()
	TestDatabase.insert_rows(database, [{ &"id": 10, &"reference_id": 99 }], &"skills")

	var result := database.alter_table(
		&"skills",
		[
			GDSQLTableAlteration.add_foreign_key(
				GDSQLForeignKeyDefinition.new(
					&"skills_reference",
					&"reference_id",
					&"heroes",
					&"id",
				),
			),
		],
	)

	assert_bool(result.is_successful()).is_false()
	assert_str(String(result.diagnostics.entries[0].code)).is_equal(
		"GDSQL_CATALOG_FOREIGN_KEY_ORPHAN_VALUE",
	)


func test_incoming_foreign_key_blocks_target_table_rename_and_drop() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	assert_bool(database.create_table(_referencing_table(&"skills")).is_successful()).is_true()

	var renamed := database.rename_table(&"heroes", &"characters")
	var dropped := database.drop_table(&"heroes")

	assert_bool(renamed.is_successful()).is_false()
	assert_bool(dropped.is_successful()).is_false()
	assert_str(String(renamed.diagnostics.entries[0].code)).is_equal(
		"GDSQL_CATALOG_FOREIGN_KEY_DEPENDENCY",
	)
	assert_str(String(dropped.diagnostics.entries[0].code)).is_equal(
		"GDSQL_CATALOG_FOREIGN_KEY_DEPENDENCY",
	)


func test_incoming_foreign_key_blocks_target_column_changes() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	assert_bool(
		database.alter_table(
			&"heroes",
			[GDSQLTableAlteration.set_column_unique(&"name", true)],
		).is_successful(),
	).is_true()
	assert_bool(
		database.create_table(
			_referencing_table(&"skills", TYPE_STRING, &"heroes", &"name"),
		).is_successful(),
	).is_true()

	var renamed := database.alter_table(
		&"heroes",
		[GDSQLTableAlteration.rename_column(&"name", &"code")],
	)
	var dropped := database.alter_table(
		&"heroes",
		[GDSQLTableAlteration.drop_column(&"name")],
	)
	var uniqueness_removed := database.alter_table(
		&"heroes",
		[GDSQLTableAlteration.set_column_unique(&"name", false)],
	)

	for result in [renamed, dropped, uniqueness_removed]:
		assert_bool(result.is_successful()).is_false()
		assert_str(String(result.diagnostics.entries[0].code)).is_equal(
			"GDSQL_CATALOG_FOREIGN_KEY_DEPENDENCY",
		)


func test_incoming_foreign_key_blocks_only_the_last_unique_index() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	assert_bool(
		database.alter_table(
			&"heroes",
			[
				GDSQLTableAlteration.add_index(
					GDSQLIndexDefinition.new(&"heroes_name", [&"name"], true),
				),
			],
		).is_successful(),
	).is_true()
	assert_bool(
		database.create_table(
			_referencing_table(&"skills", TYPE_STRING, &"heroes", &"name"),
		).is_successful(),
	).is_true()

	var blocked := database.alter_table(
		&"heroes",
		[GDSQLTableAlteration.drop_index(&"heroes_name")],
	)
	assert_bool(blocked.is_successful()).is_false()
	assert_str(String(blocked.diagnostics.entries[0].code)).is_equal(
		"GDSQL_CATALOG_FOREIGN_KEY_DEPENDENCY",
	)
	assert_bool(
		database.alter_table(
			&"heroes",
			[GDSQLTableAlteration.set_column_unique(&"name", true)],
		).is_successful(),
	).is_true()
	assert_bool(
		database.alter_table(
			&"heroes",
			[GDSQLTableAlteration.drop_index(&"heroes_name")],
		).is_successful(),
	).is_true()


func test_self_referencing_table_and_column_renames_update_the_constraint() -> void:
	var categories := GDSQLTableDefinition.new(&"categories", &"id")
	categories.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true))
	categories.add_column(GDSQLColumnDefinition.new(&"parent_id", TYPE_INT, true))
	categories.add_foreign_key(
		GDSQLForeignKeyDefinition.new(
			&"categories_parent",
			&"parent_id",
			&"categories",
			&"id",
		),
	)
	var database := TestDatabase.create_database(_data_root, categories)

	assert_bool(database.rename_table(&"categories", &"groups").is_successful()).is_true()
	assert_bool(
		database.alter_table(
			&"groups",
			[GDSQLTableAlteration.rename_column(&"id", &"group_id")],
		).is_successful(),
	).is_true()
	var stored := database.context.catalog.get_table(&"game_config", &"groups")
	var foreign_key := stored.get_foreign_key(&"categories_parent")

	assert_str(String(foreign_key.referenced_table)).is_equal("groups")
	assert_str(String(foreign_key.referenced_column)).is_equal("group_id")
	assert_bool(database.drop_table(&"groups").is_successful()).is_true()


func test_alter_table_rejects_constraints_violated_by_existing_rows() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	TestDatabase.insert_rows(
		database,
		[
			{ &"id": 1, &"name": "Mage" },
			{ &"id": 2, &"name": "Mage" },
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
	TestDatabase.insert_rows(database, [{ &"id": 1, &"name": "Knight" }])

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
	TestDatabase.insert_rows(database, [{ &"id": 1, &"name": "Knight" }])
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


func _referencing_table(
		table_name: StringName,
		reference_type: Variant.Type = TYPE_INT,
		target_table: StringName = &"heroes",
		target_column: StringName = &"id",
) -> GDSQLTableDefinition:
	var table := GDSQLTableDefinition.new(table_name, &"id")
	table.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true))
	table.add_column(GDSQLColumnDefinition.new(&"reference_id", reference_type, false))
	table.add_foreign_key(
		GDSQLForeignKeyDefinition.new(
			StringName("%s_reference" % table_name),
			&"reference_id",
			target_table,
			target_column,
		),
	)
	return table


func _write_lifecycle_marker(
		resolver: GDSQLDatabasePathResolver,
		database_name: StringName,
		kind: String,
		source: StringName,
		target: StringName,
		committed: bool,
) -> String:
	var root := resolver.resolve_catalog_transaction_root(database_name)
	assert_int(
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root)),
	).is_equal(OK)
	var phase := ".committed" if committed else ".preparing"
	var path := root.path_join("simulated.cfg" + phase)
	var marker := ConfigFile.new()
	marker.set_value("transaction", "kind", kind)
	marker.set_value("transaction", "database", String(database_name))
	marker.set_value("transaction", "source", String(source))
	marker.set_value("transaction", "target", String(target))
	assert_int(marker.save(path)).is_equal(OK)
	return path


func _stage_database_registry(
		resolver: GDSQLDatabasePathResolver,
		source: StringName,
		target: StringName = &"",
) -> void:
	var registry_path := resolver.resolve_catalog_path()
	var registry := ConfigFile.new()
	assert_int(registry.load(registry_path)).is_equal(OK)
	registry.erase_section(String(source))
	if target != &"":
		registry.set_value(
			String(target),
			"path",
			resolver.resolve_database_path(target),
		)
	assert_int(registry.save(registry_path + ".building")).is_equal(OK)


func _activate_staged_database_registry(registry_path: String) -> void:
	assert_int(
		_rename_file(registry_path, registry_path + ".previous"),
	).is_equal(OK)
	assert_int(
		_rename_file(registry_path + ".building", registry_path),
	).is_equal(OK)


func _write_database_lifecycle_marker(
		resolver: GDSQLDatabasePathResolver,
		kind: String,
		source: StringName,
		target: StringName,
		committed: bool,
) -> String:
	var root := resolver.resolve_catalog_transaction_root()
	assert_int(
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root)),
	).is_equal(OK)
	var phase := ".committed" if committed else ".preparing"
	var path := root.path_join("simulated_database.cfg" + phase)
	var marker := ConfigFile.new()
	marker.set_value("transaction", "kind", kind)
	marker.set_value("transaction", "source", String(source))
	marker.set_value("transaction", "target", String(target))
	assert_int(marker.save(path)).is_equal(OK)
	return path


func _assert_database_lifecycle_artifacts_removed(
		registry_path: String,
		marker_path: String,
) -> void:
	assert_bool(FileAccess.file_exists(registry_path + ".building")).is_false()
	assert_bool(FileAccess.file_exists(registry_path + ".previous")).is_false()
	assert_bool(FileAccess.file_exists(marker_path)).is_false()


func _rename_file(source: String, destination: String) -> Error:
	return DirAccess.rename_absolute(
		ProjectSettings.globalize_path(source),
		ProjectSettings.globalize_path(destination),
	)
