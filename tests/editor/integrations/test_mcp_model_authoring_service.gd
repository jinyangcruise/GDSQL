class_name GDSQLMcpModelAuthoringServiceTest
extends GdUnitTestSuite

const TestDatabase = preload("res://tests/utils/gdsql_test_database.gd")

var _test_index := 0


func test_previews_model_generation_and_commits_cross_role_reference() -> void:
	_test_index += 1
	var root := create_temp_dir(
		"gdsql_mcp_models_%d_%d" % [_test_index, Time.get_ticks_usec()],
	)
	var content_root := root.path_join("content")
	var save_root := root.path_join("save")
	var content_table := GDSQLTableDefinition.new(&"heroes", &"id") \
			.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true)) \
			.add_column(GDSQLColumnDefinition.new(&"name", TYPE_STRING, false))
	var save_table := GDSQLTableDefinition.new(&"hero_states", &"id") \
			.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true)) \
			.add_column(GDSQLColumnDefinition.new(&"hero_content_id", TYPE_INT, false))
	TestDatabase.create_database(content_root, content_table, &"content")
	TestDatabase.create_database(save_root, save_table, &"game_state")
	var snapshot := GDSQLDatabaseRegistrySnapshot.new()
	snapshot.registrations.assign(
		[
			GDSQLDatabaseRegistration.new(&"content", &"content", content_root),
			GDSQLDatabaseRegistration.new(&"save_1", &"game_state", save_root),
		],
	)
	snapshot.role_bindings.assign(
		[
			GDSQLDatabaseRoleBinding.new(GDSQLDatabaseRegistry.CONTENT_ROLE, &"content"),
			GDSQLDatabaseRoleBinding.new(GDSQLDatabaseRegistry.SAVE_ROLE, &"save_1"),
		],
	)
	var registry := GDSQLDatabaseRegistry.new(
		GDSQLConfigFileDatabaseRegistryStore.new(root.path_join("registry.cfg")),
	)
	assert_bool(registry.save_snapshot(snapshot).is_successful()).is_true()
	var workbench := GDSQLWorkbench.new(registry, GDSQLConfigFileDatabaseExplorer.new())
	assert_bool(workbench.load().is_successful()).is_true()
	var settings_path := root.path_join("settings.cfg")
	var bindings := GDSQLEditorModelBindingStore.new(settings_path)
	assert_int(
		bindings.save(
			&"content",
			&"content",
			&"heroes",
			&"HeroContent",
			GDSQLDatabaseRegistry.CONTENT_ROLE,
			"res://models",
		),
	).is_equal(OK)
	var references := GDSQLEditorContentReferenceStore.new(settings_path)
	var service := GDSQLMcpModelAuthoringService.new(
		workbench,
		bindings,
		references,
	)

	var model_preview := service.preview(
		{
			"operation": "generate_model",
			"registration": "content",
			"table": "heroes",
			"class_name": "HeroContent",
		},
	)
	assert_bool(model_preview.is_successful()).is_true()
	assert_str(model_preview.get_value()["data"]["generated_path"]).is_equal(
		"res://models/generated/hero_content_model_generated.gd",
	)

	var preview := service.preview(
		{
			"operation": "register_content_reference",
			"source_registration": "save_1",
			"source_table": "hero_states",
			"source_column": "hero_content_id",
			"target_registration": "content",
			"target_table": "heroes",
			"target_column": "id",
			"target_model_class": "HeroContent",
			"relationship_name": "hero_content",
		},
	)
	assert_bool(preview.is_successful()).is_true()
	var handle: String = preview.get_value()["data"]["confirmation_handle"]
	assert_bool(service.commit(handle, true).is_successful()).is_true()
	assert_int(
		references.load_for_table(&"save_1", &"game_state", &"hero_states").size(),
	).is_equal(1)
