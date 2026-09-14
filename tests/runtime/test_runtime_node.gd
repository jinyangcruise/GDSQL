class_name GDSQLRuntimeNodeTest
extends GdUnitTestSuite

const RUNTIME_NODE_SCENE := preload(
	"res://addons/gdsql/runtime/gdsql_runtime_node.tscn"
)

var _test_root: String
var _registry_path: String
var _save_root: String
var _settings_path: String
var _cache_root: String
var _test_index := 0


func before_test() -> void:
	GDSQLModels.clear_context()
	_test_index += 1
	_test_root = create_temp_dir("gdsql_runtime_node_%d" % _test_index)
	_registry_path = _test_root.path_join("registry.cfg")
	_save_root = _test_root.path_join("save")
	_settings_path = _test_root.path_join("settings.cfg")
	_cache_root = _test_root.path_join("cache/effective_content")
	_create_save_database()
	_save_registry_snapshot()


func after_test() -> void:
	GDSQLModels.clear_context()


func test_scene_bootstraps_the_runtime_with_periodic_policy() -> void:
	var runtime_node := _create_runtime_node()

	var started := runtime_node.start()
	var policy := runtime_node.get_runtime() \
			.get_persistence_coordinator() \
			.get_policy(&"save_1")

	assert_bool(started.is_successful()).is_true()
	assert_object(runtime_node.get_runtime()).is_not_null()
	assert_object(runtime_node.get_start_result()).is_same(started)
	assert_bool(runtime_node.is_started()).is_true()
	assert_bool(runtime_node.database(GDSQLDatabaseRegistry.SAVE_ROLE).is_successful()).is_true()
	assert_int(policy.mode).is_equal(GDSQLCheckpointPolicy.Mode.PERIODIC)
	assert_float(policy.interval_seconds).is_equal(30.0)
	assert_float(
		(runtime_node.get_node("%CheckpointTimer") as Timer).time_left,
	).is_greater(0.0)
	runtime_node.stop(false)


func test_managed_profile_activates_configured_effective_content_on_start() -> void:
	var base_root := _create_managed_base()
	_configure_managed_profile(base_root)
	var runtime_node := _create_runtime_node()

	var started := runtime_node.start()
	var content := runtime_node.database(GDSQLDatabaseRegistry.CONTENT_ROLE).get_database()
	var selected := content.execute(content.table(&"items").select().build())

	assert_bool(started.is_successful()).is_true()
	assert_str(String(content.database_name)).is_equal("effective_content")
	assert_int(selected.get_returned_rows()).is_equal(1)
	assert_str(selected.rows[0].get_value(&"name")).is_equal("Iron Sword")
	assert_object(runtime_node.get_content_activation_result()).is_not_null()
	assert_bool(runtime_node.get_content_activation_result().was_rebuilt()).is_true()
	assert_int(runtime_node.get_save_content_compatibility_report().status).is_equal(
		GDSQLSaveContentCompatibilityReport.Status.UNTRACKED,
	)
	assert_bool(
		runtime_node.get_save_content_compatibility_report().requires_policy_decision(),
	).is_true()
	assert_array(_diagnostic_codes(started)).not_contains(
		["GDSQL_DIRECT_SETUP_CONTENT_DATABASE"],
	)
	runtime_node.stop(false)


func test_managed_start_exposes_exact_save_compatibility_before_runtime_started() -> void:
	var base_root := _create_managed_base()
	_configure_managed_profile(base_root)
	var preparation_node := _create_runtime_node()
	assert_bool(preparation_node.start().is_successful()).is_true()
	var active_manifest := preparation_node.get_content_activation_result() \
			.cache_result.manifest
	assert_bool(
		GDSQLConfigFileSaveContentManifestStore.new(_save_root) \
				.save_manifest(GDSQLSaveContentManifest.from_cache_manifest(active_manifest)) \
				.is_successful(),
	).is_true()
	preparation_node.stop(false)
	var runtime_node := _create_runtime_node()
	var reports: Array[GDSQLSaveContentCompatibilityReport] = []
	runtime_node.save_content_compatibility_checked.connect(
		func(report: GDSQLSaveContentCompatibilityReport) -> void:
			reports.append(report),
	)

	var started := runtime_node.start()
	var report := runtime_node.get_save_content_compatibility_report()

	assert_bool(started.is_successful()).is_true()
	assert_int(report.status).is_equal(GDSQLSaveContentCompatibilityReport.Status.EXACT)
	assert_bool(report.requires_policy_decision()).is_false()
	assert_int(reports.size()).is_equal(1)
	assert_object(reports[0]).is_same(report)
	runtime_node.stop(false)


func test_managed_save_slot_selection_refreshes_compatibility_report() -> void:
	var second_save_root := _test_root.path_join("save_2")
	_create_save_database(&"save_2", second_save_root)
	var registry_store := GDSQLConfigFileDatabaseRegistryStore.new(_registry_path)
	var snapshot := registry_store.load_snapshot().get_value() \
			as GDSQLDatabaseRegistrySnapshot
	snapshot.registrations.append(
		GDSQLDatabaseRegistration.new(
			&"save_2",
			&"save_2",
			second_save_root,
			GDSQLStorageBackendIds.IN_MEMORY,
		),
	)
	assert_bool(registry_store.save_snapshot(snapshot).is_successful()).is_true()
	_configure_managed_profile(_create_managed_base())
	var runtime_node := _create_runtime_node()
	assert_bool(runtime_node.start().is_successful()).is_true()
	var active_manifest := runtime_node.get_content_activation_result().cache_result.manifest
	assert_bool(
		GDSQLConfigFileSaveContentManifestStore.new(second_save_root) \
				.save_manifest(GDSQLSaveContentManifest.from_cache_manifest(active_manifest)) \
				.is_successful(),
	).is_true()

	var selected := runtime_node.select_save_slot(&"save_2")
	var report := runtime_node.get_save_content_compatibility_report()

	assert_bool(selected.is_successful()).is_true()
	assert_int(report.status).is_equal(GDSQLSaveContentCompatibilityReport.Status.EXACT)
	assert_bool(report.requires_policy_decision()).is_false()
	runtime_node.stop(false)


func test_failed_managed_activation_does_not_expose_a_partial_runtime() -> void:
	assert_bool(
		GDSQLConfigFileSetupProfileStore.new(_settings_path) \
				.save_profile(GDSQLSetupProfile.Kind.MANAGED) \
				.is_successful(),
	).is_true()
	assert_bool(
		GDSQLConfigFileManagedContentConfigurationStore.new(_settings_path) \
				.save_configuration(
					GDSQLManagedContentConfiguration.new(_test_root.path_join("missing")),
				) \
				.is_successful(),
	).is_true()
	var runtime_node := _create_runtime_node()

	var started := runtime_node.start()

	assert_bool(started.is_successful()).is_false()
	assert_bool(runtime_node.is_started()).is_false()
	assert_object(runtime_node.get_runtime()).is_null()
	assert_object(runtime_node.get_content_activation_result()).is_not_null()
	assert_object(GDSQLModels.get_context()).is_null()
	assert_array(_diagnostic_codes(started)).contains(
		["GDSQL_CONTENT_PACKAGE_MANIFEST_NOT_FOUND"],
	)


func test_timer_checkpoint_transfers_committed_rows_to_durable_storage() -> void:
	var runtime_node := _create_runtime_node()
	assert_bool(runtime_node.start().is_successful()).is_true()
	var save := runtime_node.database(GDSQLDatabaseRegistry.SAVE_ROLE).get_database()
	assert_bool(
		save.execute(
			save.table(&"heroes") \
					.update() \
					.set_value(&"name", "Paladin") \
					.where(GDSQLExpr.column(&"id").equals(1)) \
					.build(),
		).is_successful(),
	).is_true()

	(runtime_node.get_node("%CheckpointTimer") as Timer).timeout.emit()
	var durable := GDSQLDatabase.open(&"save_1", _save_root).get_database()
	var selected := durable.execute(durable.table(&"heroes").select().build())

	assert_str(selected.rows[0].get_value(&"name")).is_equal("Paladin")
	runtime_node.stop(false)


func test_stop_checkpoints_and_releases_the_runtime_context() -> void:
	var runtime_node := _create_runtime_node()
	assert_bool(runtime_node.start().is_successful()).is_true()
	var save := runtime_node.database(GDSQLDatabaseRegistry.SAVE_ROLE).get_database()
	assert_bool(
		save.execute(
			save.table(&"heroes") \
					.update() \
					.set_value(&"name", "Ranger") \
					.where(GDSQLExpr.column(&"id").equals(1)) \
					.build(),
		).is_successful(),
	).is_true()

	var stopped := runtime_node.stop()
	var durable := GDSQLDatabase.open(&"save_1", _save_root).get_database()
	var selected := durable.execute(durable.table(&"heroes").select().build())

	assert_bool(stopped.is_successful()).is_true()
	assert_array(stopped.checkpointed_databases).contains_exactly([&"save_1"])
	assert_str(selected.rows[0].get_value(&"name")).is_equal("Ranger")
	assert_object(runtime_node.get_runtime()).is_null()
	assert_bool(runtime_node.is_started()).is_false()
	assert_object(GDSQLModels.get_context()).is_null()


func test_operations_before_start_return_structured_diagnostics() -> void:
	var runtime_node := auto_free(GDSQLRuntimeNode.new()) as GDSQLRuntimeNode

	var database := runtime_node.database(GDSQLDatabaseRegistry.CONTENT_ROLE)
	var checkpoint := runtime_node.checkpoint_now()

	assert_bool(database.is_successful()).is_false()
	assert_str(String(database.diagnostics.entries[0].code)).is_equal(
		"GDSQL_RUNTIME_NOT_STARTED",
	)
	assert_bool(checkpoint.is_successful()).is_false()
	assert_str(String(checkpoint.diagnostics.entries[0].code)).is_equal(
		"GDSQL_RUNTIME_NOT_STARTED",
	)


func _create_runtime_node() -> GDSQLRuntimeNode:
	var runtime_node := auto_free(RUNTIME_NODE_SCENE.instantiate()) \
			as GDSQLRuntimeNode
	runtime_node.auto_start = false
	runtime_node.registry_path = _registry_path
	runtime_node.setup_settings_path = _settings_path
	runtime_node.managed_cache_root = _cache_root
	add_child(runtime_node)
	return runtime_node


func _create_managed_base() -> String:
	var base_root := _test_root.path_join("content/base")
	var scaffolded := GDSQLConfigFileContentPackageScaffolder.new().scaffold(
		base_root,
		GDSQLContentPackageManifest.new(
			&"base.game",
			"Base Game",
			"1.0.0",
			GDSQLContentPackageKind.Kind.BASE_GAME,
		),
	)
	assert_bool(scaffolded.is_successful()).is_true()
	var source := scaffolded.get_value() as GDSQLContentPackageSource
	var database := GDSQLDatabase.create(&"content", source.get_data_root()).get_database()
	var items := GDSQLTableDefinition.new(&"items", &"id")
	items.add_column(GDSQLColumnDefinition.new(&"id", TYPE_STRING_NAME, false))
	items.add_column(GDSQLColumnDefinition.new(&"name", TYPE_STRING, false))
	assert_bool(database.create_table(items).is_successful()).is_true()
	assert_bool(
		database.insert(
			&"items",
			{ &"id": &"iron_sword", &"name": "Iron Sword" },
		).is_successful(),
	).is_true()
	return base_root


func _create_save_database(
		database_name: StringName = &"save_1",
		data_root: String = "",
) -> void:
	var save_root := _save_root if data_root.is_empty() else data_root
	var database := GDSQLDatabase.create(database_name, save_root).get_database()
	var heroes := GDSQLTableDefinition.new(&"heroes", &"id")
	heroes.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true))
	heroes.add_column(GDSQLColumnDefinition.new(&"name", TYPE_STRING, false))
	assert_bool(database.create_table(heroes).is_successful()).is_true()
	assert_bool(
		database.insert(&"heroes", { &"id": 1, &"name": "Knight" }).is_successful(),
	).is_true()


func _configure_managed_profile(base_root: String) -> void:
	assert_bool(
		GDSQLConfigFileSetupProfileStore.new(_settings_path) \
				.save_profile(GDSQLSetupProfile.Kind.MANAGED) \
				.is_successful(),
	).is_true()
	assert_bool(
		GDSQLConfigFileManagedContentConfigurationStore.new(_settings_path) \
				.save_configuration(GDSQLManagedContentConfiguration.new(base_root)) \
				.is_successful(),
	).is_true()


func _save_registry_snapshot() -> void:
	var snapshot := GDSQLDatabaseRegistrySnapshot.new()
	snapshot.registrations.append(
		GDSQLDatabaseRegistration.new(
			&"save_1",
			&"save_1",
			_save_root,
			GDSQLStorageBackendIds.IN_MEMORY,
		),
	)
	snapshot.role_bindings.append(
		GDSQLDatabaseRoleBinding.new(GDSQLDatabaseRegistry.SAVE_ROLE, &"save_1"),
	)
	assert_bool(
		GDSQLConfigFileDatabaseRegistryStore.new(_registry_path) \
				.save_snapshot(snapshot) \
				.is_successful(),
	).is_true()


func _diagnostic_codes(result: GDSQLOperationResult) -> Array[String]:
	var codes: Array[String] = []
	for diagnostic in result.diagnostics.entries:
		codes.append(String(diagnostic.code))
	return codes
