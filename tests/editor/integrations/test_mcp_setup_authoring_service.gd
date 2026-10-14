class_name GDSQLMcpSetupAuthoringServiceTest
extends GdUnitTestSuite

const TestDatabase = preload("res://tests/utils/gdsql_test_database.gd")


class FakeCacheStore extends GDSQLContentCacheStore:
	var manifest: GDSQLContentCacheManifest


	func load_manifest() -> GDSQLOperationResult:
		var result := GDSQLOperationResult.new()
		result.value = manifest
		return result


	func has_database(_database_name: StringName) -> bool:
		return manifest != null


	func replace(
			cache_manifest: GDSQLContentCacheManifest,
			_database: GDSQLContentDatabaseSnapshot,
	) -> GDSQLOperationResult:
		manifest = cache_manifest
		var result := GDSQLOperationResult.new()
		result.value = true
		return result


	func get_cache_root() -> String:
		return "user://test-cache"


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
	var runtime_state := { "path": "" }
	var history_store := GDSQLConfigFileMigrationHistoryStore.new(root.path_join("migrations"))
	var state_store := GDSQLConfigFileMigrationSchemaStateStore.new(root.path_join("states"))
	var service := GDSQLMcpSetupAuthoringService.new(
		workbench,
		profiles,
		history_store,
		state_store,
		func() -> String: return runtime_state["path"],
		func() -> GDSQLOperationResult:
			runtime_state["path"] = "*%s" % GDSQLMcpSetupAuthoringService.RUNTIME_NODE_PATH
			var result := GDSQLOperationResult.new()
			result.value = true
			return result,
	)

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

	var runtime_preview := service.preview({ "operation": "install_runtime_adapter" })
	assert_bool(runtime_preview.is_successful()).is_true()
	assert_bool(
		service.commit(
			runtime_preview.get_value()["data"]["confirmation_handle"],
			true,
		).is_successful(),
	).is_true()
	assert_str(runtime_state["path"]).is_equal(
		"*%s" % GDSQLMcpSetupAuthoringService.RUNTIME_NODE_PATH,
	)

	var save_preview := service.preview(
		{
			"operation": "create_save_slot",
			"save_slot": "save_2",
			"storage_backend": "memory",
		},
	)
	assert_bool(save_preview.is_successful()).is_true()
	assert_bool(
		save_preview.get_value()["data"]["storage_decision"][
			"requires_checkpoint_management"
		],
	).is_true()
	assert_str(save_preview.get_value()["data"]["data_root"]).is_equal(
		"user://gdsql/saves/save_2",
	)
	assert_bool(save_preview.get_value()["data"]["copies_rows"]).is_false()

	var cache_preview := service.preview({ "operation": "build_managed_cache" })
	assert_bool(cache_preview.is_successful()).is_false()
	assert_str(String(cache_preview.diagnostics.entries[0].code)).is_equal(
		"GDSQL_MCP_MANAGED_PROFILE_REQUIRED",
	)


func test_managed_packages_and_save_expectations_require_confirmation() -> void:
	var root := create_temp_dir("gdsql_mcp_managed_%d" % Time.get_ticks_usec())
	var base_root := root.path_join("content/base")
	var packages_root := root.path_join("content/packages")
	var mod_root := packages_root.path_join("example_mod")
	assert_bool(
		GDSQLConfigFileContentPackageScaffolder.new().scaffold(
			base_root,
			GDSQLContentPackageManifest.new(
				&"base.game", "Base Game", "1.0.0", GDSQLContentPackageKind.Kind.BASE_GAME,
			),
		).is_successful(),
	).is_true()
	assert_bool(
		GDSQLConfigFileContentPackageScaffolder.new().scaffold(
			mod_root,
			GDSQLContentPackageManifest.new(
				&"mod.example", "Example Mod", "1.0.0", GDSQLContentPackageKind.Kind.MOD,
			),
		).is_successful(),
	).is_true()
	var save_root := root.path_join("saves/save_1")
	TestDatabase.create_heroes_database(save_root)
	var registration := GDSQLDatabaseRegistration.new(
		&"save_1", TestDatabase.DEFAULT_DATABASE_NAME, save_root,
	)
	var snapshot := GDSQLDatabaseRegistrySnapshot.new()
	snapshot.registrations.assign([registration])
	snapshot.role_bindings.assign(
		[GDSQLDatabaseRoleBinding.new(GDSQLDatabaseRegistry.SAVE_ROLE, &"save_1")],
	)
	var registry := GDSQLDatabaseRegistry.new(
		GDSQLConfigFileDatabaseRegistryStore.new(root.path_join("registry.cfg")),
	)
	assert_bool(registry.save_snapshot(snapshot).is_successful()).is_true()
	var workbench := GDSQLWorkbench.new(registry, GDSQLConfigFileDatabaseExplorer.new())
	assert_bool(workbench.load().is_successful()).is_true()
	var settings_path := root.path_join("settings.cfg")
	var profiles := GDSQLConfigFileSetupProfileStore.new(settings_path)
	assert_bool(profiles.save_profile(GDSQLSetupProfile.Kind.MANAGED).is_successful()).is_true()
	var configuration_store := GDSQLConfigFileManagedContentConfigurationStore.new(
		settings_path,
	)
	assert_bool(
		configuration_store.save_configuration(
			GDSQLManagedContentConfiguration.new(base_root, [packages_root]),
		).is_successful(),
	).is_true()
	var cache_store := FakeCacheStore.new()
	cache_store.manifest = GDSQLContentCacheManifest.new(
		&"content",
		&"effective_content",
		[
			GDSQLContentPackageFingerprint.new(&"base.game", "1.0.0", "base-hash"),
			GDSQLContentPackageFingerprint.new(&"mod.example", "1.0.0", "mod-hash"),
		],
	)
	var service := GDSQLMcpSetupAuthoringService.new(
		workbench, profiles, null, null, Callable(), Callable(), configuration_store,
		null, null, null, null, cache_store,
	)

	var configured := service.preview(
		{ "operation": "configure_managed_packages", "enabled_packages": ["mod.example"] },
	)
	assert_bool(configured.is_successful()).is_true()
	var package_decision: Dictionary = configured.get_value()["data"][
		"managed_content_decision"
	]
	assert_bool(package_decision["changes_effective_content"]).is_true()
	assert_array(package_decision["added_packages"]).contains_exactly(["mod.example"])
	assert_str(package_decision["active_save_before_change"]["status"]).is_equal(
		"untracked",
	)
	assert_bool(package_decision["updates_save_expectation"]).is_false()
	assert_bool(
		service.commit(configured.get_value()["data"]["confirmation_handle"], true) \
				.is_successful(),
	).is_true()
	assert_array(configuration_store.load_configuration().get_value().enabled_package_ids) \
			.contains_exactly([&"mod.example"])

	var recorded := service.preview({ "operation": "record_save_content" })
	assert_bool(recorded.is_successful()).is_true()
	var save_decision: Dictionary = recorded.get_value()["data"]["managed_content_decision"]
	assert_str(save_decision["selected_action"]).is_equal("record_save_expectation")
	assert_bool(save_decision["changes_save_rows"]).is_false()
	assert_bool(
		service.commit(recorded.get_value()["data"]["confirmation_handle"], true) \
				.is_successful(),
	).is_true()
	var saved := GDSQLConfigFileSaveContentManifestStore.new(save_root).load_manifest()
	assert_bool(saved.is_successful()).is_true()
	assert_int((saved.get_value() as GDSQLSaveContentManifest).packages.size()).is_equal(2)
