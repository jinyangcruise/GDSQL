class_name GDSQLMcpDatabaseAuthoringServiceTest
extends GdUnitTestSuite

const TestDatabase = preload("res://tests/utils/gdsql_test_database.gd")

var _root: String
var _service: GDSQLMcpAuthoringService
var _workbench: GDSQLWorkbench
var _history_store: GDSQLConfigFileMigrationHistoryStore
var _test_index := 0


func before_test() -> void:
	_test_index += 1
	_root = create_temp_dir(
		"gdsql_mcp_database_%d_%d" % [_test_index, Time.get_ticks_usec()],
	)
	var database := TestDatabase.create_heroes_database(_root)
	TestDatabase.insert_basic_heroes(database)
	var snapshot := GDSQLDatabaseRegistrySnapshot.new()
	snapshot.registrations.assign(
		[GDSQLDatabaseRegistration.new(&"content", &"game_config", _root)],
	)
	snapshot.role_bindings.assign(
		[GDSQLDatabaseRoleBinding.new(GDSQLDatabaseRegistry.CONTENT_ROLE, &"content")],
	)
	var registry := GDSQLDatabaseRegistry.new(
		GDSQLConfigFileDatabaseRegistryStore.new(_root.path_join("editor_registry.cfg")),
	)
	assert_bool(registry.save_snapshot(snapshot).is_successful()).is_true()
	_workbench = GDSQLWorkbench.new(registry, GDSQLConfigFileDatabaseExplorer.new())
	assert_bool(_workbench.load().is_successful()).is_true()
	_history_store = GDSQLConfigFileMigrationHistoryStore.new(
		_root.path_join("migrations"),
	)
	_service = GDSQLMcpAuthoringService.new(
		_workbench,
		{ "project_data": _root },
		_history_store,
	)


func test_create_database_requires_preview_and_registers_only_after_commit() -> void:
	var preview := _service.preview_database_mutation(
		{
			"operation": "create_database",
			"registration": "localization",
			"database": "localization",
			"location": "project_data",
		},
	)

	assert_bool(preview.is_successful()).is_true()
	assert_bool(preview.get_value()["data"]["storage_decision"]["default_applied"]) \
			.is_true()
	assert_bool(
		preview.get_value()["data"]["storage_decision"]["requires_checkpoint_management"],
	).is_false()
	assert_object(_workbench.get_registration(&"localization")).is_null()
	assert_bool(GDSQLDatabase.open(&"localization", _root).is_successful()).is_false()
	var handle: String = preview.get_value()["data"]["confirmation_handle"]
	assert_bool(_service.commit_database_mutation(handle, true).is_successful()).is_true()
	assert_object(_workbench.get_registration(&"localization")).is_not_null()
	assert_bool(GDSQLDatabase.open(&"localization", _root).is_successful()).is_true()
	assert_bool(_service.commit_database_mutation(handle, true).is_successful()).is_false()


func test_rename_database_updates_physical_and_registered_identity() -> void:
	var preview := _service.preview_database_mutation(
		{
			"operation": "rename_database",
			"registration": "content",
			"new_name": "base_content",
		},
	)
	assert_bool(preview.is_successful()).is_true()

	var committed := _service.commit_database_mutation(
		preview.get_value()["data"]["confirmation_handle"],
		true,
	)

	assert_bool(committed.is_successful()).is_true()
	assert_str(String(_workbench.get_registration(&"content").database_name)).is_equal(
		"base_content",
	)
	assert_bool(GDSQLDatabase.open(&"base_content", _root).is_successful()).is_true()
	assert_bool(GDSQLDatabase.open(&"game_config", _root).is_successful()).is_false()


func test_rename_rejects_a_database_with_authored_migration_history() -> void:
	var migration := GDSQLMigrationDefinition.new(
		"001_add_level",
		"Add the hero level.",
		[
			GDSQLSchemaMigrationStep.new(
				&"heroes",
				[
					GDSQLTableAlteration.add_column(
						GDSQLColumnDefinition.new(&"level", TYPE_INT, true),
					),
				],
			),
		],
	)
	assert_bool(_history_store.append(&"game_config", migration, 0).is_successful()).is_true()

	var preview := _service.preview_database_mutation(
		{
			"operation": "rename_database",
			"registration": "content",
			"new_name": "base_content",
		},
	)

	assert_bool(preview.is_successful()).is_false()
	assert_str(String(preview.diagnostics.entries[0].code)).is_equal(
		"GDSQL_MCP_DATABASE_RENAME_MIGRATIONS",
	)


func test_unregister_preserves_files_and_removes_roles_and_registration() -> void:
	var database_path := GDSQLDatabasePathResolver.new(_root).resolve_database_path(
		&"game_config",
	)
	var preview := _service.preview_database_mutation(
		{ "operation": "unregister_database", "registration": "content" },
	)
	assert_bool(preview.is_successful()).is_true()
	assert_bool(preview.get_value()["data"]["preserves_files"]).is_true()

	assert_bool(
		_service.commit_database_mutation(
			preview.get_value()["data"]["confirmation_handle"],
			true,
		).is_successful(),
	).is_true()

	assert_object(_workbench.get_registration(&"content")).is_null()
	assert_bool(_workbench.snapshot.role_bindings.is_empty()).is_true()
	assert_bool(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(database_path))).is_true()
	assert_bool(GDSQLDatabase.open(&"game_config", _root).is_successful()).is_false()


func test_destroy_removes_database_files_and_stale_preview_cannot_commit() -> void:
	var database_path := GDSQLDatabasePathResolver.new(_root).resolve_database_path(
		&"game_config",
	)
	var stale := _service.preview_database_mutation(
		{ "operation": "destroy_database", "registration": "content" },
	)
	assert_bool(stale.is_successful()).is_true()
	var opened := GDSQLDatabase.open(&"game_config", _root)
	assert_bool(opened.is_successful()).is_true()
	assert_bool(
		opened.get_database().create_table(
			GDSQLTableDefinition.new(&"items", &"id").add_column(
				GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true),
			),
		).is_successful(),
	).is_true()
	assert_bool(
		_service.commit_database_mutation(
			stale.get_value()["data"]["confirmation_handle"],
			true,
		).is_successful(),
	).is_false()

	var preview := _service.preview_database_mutation(
		{ "operation": "destroy_database", "registration": "content" },
	)
	assert_bool(preview.is_successful()).is_true()
	assert_bool(preview.get_value()["data"]["destructive"]).is_true()
	assert_bool(
		_service.commit_database_mutation(
			preview.get_value()["data"]["confirmation_handle"],
			true,
		).is_successful(),
	).is_true()
	assert_object(_workbench.get_registration(&"content")).is_null()
	assert_bool(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(database_path))).is_false()
