class_name GDSQLMcpSetupAuthoringServiceTest
extends GdUnitTestSuite

const TestDatabase = preload("res://tests/utils/gdsql_test_database.gd")


func test_profile_selection_and_save_binding_require_preview() -> void:
	var root := create_temp_dir("gdsql_mcp_setup_%d" % Time.get_ticks_usec())
	TestDatabase.create_heroes_database(root)
	var registration := GDSQLDatabaseRegistration.new(&"save_1", &"game_config", root)
	var snapshot := GDSQLDatabaseRegistrySnapshot.new()
	snapshot.registrations.assign([registration])
	var registry := GDSQLDatabaseRegistry.new(
		GDSQLConfigFileDatabaseRegistryStore.new(root.path_join("registry.cfg")),
	)
	assert_bool(registry.save_snapshot(snapshot).is_successful()).is_true()
	var workbench := GDSQLWorkbench.new(registry, GDSQLConfigFileDatabaseExplorer.new())
	assert_bool(workbench.load().is_successful()).is_true()
	var profiles := GDSQLConfigFileSetupProfileStore.new(root.path_join("settings.cfg"))
	var service := GDSQLMcpSetupAuthoringService.new(workbench, profiles)

	var profile_preview := service.preview(
		{ "operation": "select_profile", "profile": "direct" },
	)
	assert_bool(profile_preview.is_successful()).is_true()
	assert_bool(
		service.commit(
			profile_preview.get_value()["data"]["confirmation_handle"],
			true,
		).is_successful(),
	).is_true()
	assert_int(profiles.load_profile().get_value()).is_equal(GDSQLSetupProfile.Kind.DIRECT)

	var role_preview := service.preview(
		{ "operation": "bind_role", "role": "save", "registration": "save_1" },
	)
	assert_bool(role_preview.is_successful()).is_true()
	assert_bool(
		service.commit(
			role_preview.get_value()["data"]["confirmation_handle"],
			true,
		).is_successful(),
	).is_true()
	assert_str(String(workbench.snapshot.role_bindings[0].registration_name)).is_equal("save_1")
