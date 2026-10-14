class_name GDSQLMcpMigrationAuthoringServiceTest
extends GdUnitTestSuite

const TestDatabase = preload("res://tests/utils/gdsql_test_database.gd")


func test_authored_schema_migration_previews_then_commits() -> void:
	var root := create_temp_dir("gdsql_mcp_migration_%d" % Time.get_ticks_usec())
	TestDatabase.create_heroes_database(root)
	var snapshot := GDSQLDatabaseRegistrySnapshot.new()
	snapshot.registrations.assign(
		[GDSQLDatabaseRegistration.new(&"content", &"game_config", root)],
	)
	var registry := GDSQLDatabaseRegistry.new(
		GDSQLConfigFileDatabaseRegistryStore.new(root.path_join("registry.cfg")),
	)
	assert_bool(registry.save_snapshot(snapshot).is_successful()).is_true()
	var workbench := GDSQLWorkbench.new(registry, GDSQLConfigFileDatabaseExplorer.new())
	assert_bool(workbench.load().is_successful()).is_true()
	var history := GDSQLConfigFileMigrationHistoryStore.new(root.path_join("history"))
	var states := GDSQLConfigFileMigrationSchemaStateStore.new(root.path_join("states"))
	var service := GDSQLMcpAuthoringService.new(workbench, { }, history, states)

	var preview := service.preview_migration(
		{
			"registration": "content",
			"migration_id": "001_add_level",
			"description": "Add hero level.",
			"steps": [
				{
					"kind": "schema",
					"operation": "alter_table",
					"table": "heroes",
					"alterations": [
						{
							"kind": "add_column",
							"column": { "name": "level", "type": "int" },
						},
					],
				},
			],
		},
	)
	assert_bool(preview.is_successful()).is_true()
	assert_str(
		preview.get_value()["data"]["schema_change_decision"]["selected"],
	).is_equal("migration")
	assert_bool(
		preview.get_value()["data"]["schema_change_decision"]["direct_change_allowed"],
	).is_true()
	assert_int((history.load(&"game_config").get_value() as Array).size()).is_zero()

	var committed := service.commit_migration(
		preview.get_value()["data"]["confirmation_handle"],
		true,
	)

	assert_bool(committed.is_successful()).is_true()
	var database := GDSQLDatabase.open(&"game_config", root).get_database()
	assert_object(
		database.context.catalog.get_table(&"game_config", &"heroes").get_column(&"level"),
	).is_not_null()
	assert_int((history.load(&"game_config").get_value() as Array).size()).is_equal(1)
	assert_int(
		(states.load(&"game_config").get_value() as GDSQLMigrationSchemaState).history_count,
	).is_equal(1)
