class_name GDSQLDatabaseRegistryTest
extends GdUnitTestSuite

var _data_root: String
var _test_index := 0


func before_test() -> void:
	_test_index += 1
	_data_root = create_temp_dir("gdsql_database_registry_%d" % _test_index)


func test_registers_and_resolves_database_names_and_roles() -> void:
	var database := _create_database(&"game_content")
	var registry := GDSQLDatabaseRegistry.new()

	assert_bool(registry.register(&"base_content", database).is_successful()).is_true()
	assert_bool(
		registry.bind_role(GDSQLDatabaseRegistry.CONTENT_ROLE, &"base_content")
		.is_successful(),
	).is_true()
	assert_object(registry.resolve(&"base_content").get_database()).is_same(database)
	assert_object(
		registry.resolve_role(GDSQLDatabaseRegistry.CONTENT_ROLE).get_database(),
	).is_same(database)


func test_rebinding_a_role_selects_another_registered_database() -> void:
	var save_one := _create_database(&"save_one")
	var save_two := _create_database(&"save_two")
	var registry := GDSQLDatabaseRegistry.new()
	registry.register(&"slot_1", save_one)
	registry.register(&"slot_2", save_two)

	registry.bind_role(GDSQLDatabaseRegistry.SAVE_ROLE, &"slot_1")
	registry.bind_role(GDSQLDatabaseRegistry.SAVE_ROLE, &"slot_2")

	assert_object(
		registry.resolve_role(GDSQLDatabaseRegistry.SAVE_ROLE).get_database(),
	).is_same(save_two)
	assert_bool(registry.is_registered(&"slot_1")).is_true()


func test_reports_invalid_lifecycle_operations_and_clears_stale_roles() -> void:
	var database := _create_database(&"settings")
	var registry := GDSQLDatabaseRegistry.new()
	registry.register(&"settings", database)
	registry.bind_role(GDSQLDatabaseRegistry.SETTINGS_ROLE, &"settings")

	var duplicate := registry.register(&"settings", database)
	var missing := registry.bind_role(&"analytics", &"missing")
	var removed := registry.unregister(&"settings")

	assert_str(String(duplicate.diagnostics.entries[0].code)).is_equal(
		"GDSQL_DATABASE_ALREADY_REGISTERED",
	)
	assert_str(String(missing.diagnostics.entries[0].code)).is_equal(
		"GDSQL_DATABASE_NOT_REGISTERED",
	)
	assert_object(removed.get_database()).is_same(database)
	assert_bool(registry.is_role_bound(GDSQLDatabaseRegistry.SETTINGS_ROLE)).is_false()
	assert_str(
		String(
			registry.resolve_role(GDSQLDatabaseRegistry.SETTINGS_ROLE)
			.diagnostics.entries[0].code,
		),
	).is_equal("GDSQL_DATABASE_ROLE_NOT_BOUND")


func test_config_file_store_preserves_editor_visible_registry_metadata() -> void:
	var registry_path := _data_root.path_join("databases.cfg")
	var store := GDSQLConfigFileDatabaseRegistryStore.new(registry_path)
	var registry := GDSQLDatabaseRegistry.new(store)
	var snapshot := GDSQLDatabaseRegistrySnapshot.new()
	snapshot.registrations.append(
		GDSQLDatabaseRegistration.new(
			&"save_1",
			&"game_state",
			"user://gdsql/saves/save_1",
			GDSQLStorageBackendIds.CONFIG_FILE,
		),
	)
	snapshot.role_bindings.append(GDSQLDatabaseRoleBinding.new(&"save", &"save_1"))

	var saved := registry.save_snapshot(snapshot)
	var loaded := registry.load_snapshot()
	var restored := loaded.get_value() as GDSQLDatabaseRegistrySnapshot

	assert_bool(saved.is_successful()).is_true()
	assert_bool(loaded.is_successful()).is_true()
	assert_int(restored.registrations.size()).is_equal(1)
	assert_str(String(restored.registrations[0].name)).is_equal("save_1")
	assert_str(restored.registrations[0].data_root).is_equal(
		"user://gdsql/saves/save_1",
	)
	assert_str(String(restored.registrations[0].storage_backend_id)).is_equal(
		"configfile",
	)
	assert_str(String(restored.role_bindings[0].role)).is_equal("save")


func test_storage_backend_ids_supply_ui_options_and_labels() -> void:
	assert_array(GDSQLStorageBackendIds.get_all()).contains_exactly(
		[
			GDSQLStorageBackendIds.CONFIG_FILE,
			GDSQLStorageBackendIds.PAGED_BINARY,
			GDSQLStorageBackendIds.IN_MEMORY,
			GDSQLStorageBackendIds.BUFFERED,
		],
	)
	assert_bool(
		GDSQLStorageBackendIds.is_valid(GDSQLStorageBackendIds.CONFIG_FILE),
	).is_true()
	assert_bool(GDSQLStorageBackendIds.is_valid(&"unknown")).is_false()
	assert_str(
		GDSQLStorageBackendIds.get_display_name(
			GDSQLStorageBackendIds.PAGED_BINARY,
		),
	).is_equal("Paged binary")


func _create_database(database_name: StringName) -> GDSQLDatabase:
	var result := GDSQLDatabase.create(database_name, _data_root)
	assert(result.is_successful(), "Test database creation failed.")
	return result.get_database()
