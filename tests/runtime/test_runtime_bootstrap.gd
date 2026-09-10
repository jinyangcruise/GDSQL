class_name GDSQLRuntimeBootstrapTest
extends GdUnitTestSuite

var _test_root: String
var _registry_path: String
var _content_root: String
var _save_root: String
var _test_index := 0


func before_test() -> void:
	GDSQLModels.clear_context()
	_test_index += 1
	_test_root = create_temp_dir("gdsql_runtime_bootstrap_%d" % _test_index)
	_registry_path = _test_root.path_join("registry.cfg")
	_content_root = _test_root.path_join("content")
	_save_root = _test_root.path_join("save")
	_create_database(&"content", _content_root)
	var save := _create_database(&"save_1", _save_root)
	assert_bool(save.insert(&"heroes", { &"id": 1, &"name": "Knight" }).is_successful()).is_true()
	_save_registry_snapshot()


func after_test() -> void:
	GDSQLModels.clear_context()


func test_bootstrap_opens_registrations_restores_roles_and_models() -> void:
	var result := GDSQLRuntimeFactory.bootstrap(_registry_path)
	var runtime := result.get_value() as GDSQLRuntimeSession

	assert_bool(result.is_successful()).is_true()
	assert_object(runtime).is_not_null()
	assert_str(String(runtime.database(&"content").get_database().database_name)).is_equal(
		"content",
	)
	assert_str(String(runtime.database(&"save").get_database().database_name)).is_equal(
		"save_1",
	)
	assert_object(GDSQLModels.get_context()).is_same(runtime.get_model_context())
	assert_bool(runtime.get_persistence_coordinator().is_registered(&"content")).is_false()
	assert_bool(runtime.get_persistence_coordinator().is_registered(&"save_1")).is_true()

	runtime.shutdown()
	assert_object(GDSQLModels.get_context()).is_null()


func test_save_checkpoint_transfers_committed_memory_rows_to_durable_storage() -> void:
	var runtime := GDSQLRuntimeFactory.bootstrap(_registry_path).get_value() \
			as GDSQLRuntimeSession
	var save := runtime.database(GDSQLDatabaseRegistry.SAVE_ROLE).get_database()
	var updated := save.execute(
		save.table(&"heroes") \
				.update() \
				.set_value(&"name", "Paladin") \
				.where(GDSQLExpr.column(&"id").equals(1)) \
				.build(),
	)
	var checkpointed := runtime.checkpoint_save()
	var durable := GDSQLDatabase.open(&"save_1", _save_root).get_database()
	var selected := durable.execute(durable.table(&"heroes").select().build())

	assert_bool(updated.is_successful()).is_true()
	assert_bool(checkpointed.is_successful()).is_true()
	assert_array(checkpointed.checkpointed_databases).contains_exactly([&"save_1"])
	assert_str(selected.rows[0].get_value(&"name")).is_equal("Paladin")


func test_select_save_slot_checkpoints_the_previous_slot_before_rebinding() -> void:
	var second_root := _test_root.path_join("save_2")
	var second_save := _create_database(&"save_2", second_root)
	assert_bool(
		second_save.insert(&"heroes", { &"id": 1, &"name": "Mage" }).is_successful(),
	).is_true()
	_add_save_registration(&"save_2", second_root)
	var runtime := GDSQLRuntimeFactory.bootstrap(_registry_path).get_value() \
			as GDSQLRuntimeSession
	var first_save := runtime.database(GDSQLDatabaseRegistry.SAVE_ROLE).get_database()
	assert_bool(
		first_save.execute(
			first_save.table(&"heroes")
			.update()
			.set_value(&"name", "Paladin")
			.where(GDSQLExpr.column(&"id").equals(1))
			.build(),
		).is_successful(),
	).is_true()

	var selected := runtime.select_save_slot(&"save_2")
	var durable_first := GDSQLDatabase.open(&"save_1", _save_root).get_database()
	var persisted := durable_first.execute(durable_first.table(&"heroes").select().build())

	assert_bool(selected.is_successful()).is_true()
	assert_str(String(runtime.get_active_save_slot())).is_equal("save_2")
	assert_str(String(selected.get_database().database_name)).is_equal("save_2")
	assert_str(persisted.rows[0].get_value(&"name")).is_equal("Paladin")


func test_invalid_save_slot_selection_preserves_the_active_slot() -> void:
	var runtime := GDSQLRuntimeFactory.bootstrap(_registry_path).get_value() \
			as GDSQLRuntimeSession

	var selected := runtime.select_save_slot(&"missing")

	assert_bool(selected.is_successful()).is_false()
	assert_str(String(runtime.get_active_save_slot())).is_equal("save_1")
	assert_str(String(selected.diagnostics.entries[0].code)).is_equal(
		"GDSQL_DATABASE_NOT_REGISTERED",
	)


func test_failed_bootstrap_does_not_install_a_partial_model_context() -> void:
	var snapshot := GDSQLDatabaseRegistrySnapshot.new()
	snapshot.role_bindings.append(
		GDSQLDatabaseRoleBinding.new(GDSQLDatabaseRegistry.SAVE_ROLE, &"missing"),
	)
	var store := GDSQLConfigFileDatabaseRegistryStore.new(_registry_path)
	assert_bool(store.save_snapshot(snapshot).is_successful()).is_true()

	var result := GDSQLRuntimeFactory.bootstrap(_registry_path)

	assert_bool(result.is_successful()).is_false()
	assert_object(result.get_value()).is_null()
	assert_object(GDSQLModels.get_context()).is_null()


func _create_database(database_name: StringName, data_root: String) -> GDSQLDatabase:
	var database := GDSQLDatabase.create(database_name, data_root).get_database()
	var heroes := GDSQLTableDefinition.new(&"heroes", &"id")
	heroes.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true))
	heroes.add_column(GDSQLColumnDefinition.new(&"name", TYPE_STRING, false))
	assert_bool(database.create_table(heroes).is_successful()).is_true()
	return database


func _save_registry_snapshot() -> void:
	var snapshot := GDSQLDatabaseRegistrySnapshot.new()
	snapshot.registrations.append(
		GDSQLDatabaseRegistration.new(
			&"content",
			&"content",
			_content_root,
			GDSQLStorageBackendIds.CONFIG_FILE,
		),
	)
	snapshot.registrations.append(
		GDSQLDatabaseRegistration.new(
			&"save_1",
			&"save_1",
			_save_root,
			GDSQLStorageBackendIds.IN_MEMORY,
		),
	)
	snapshot.role_bindings.append(
		GDSQLDatabaseRoleBinding.new(GDSQLDatabaseRegistry.CONTENT_ROLE, &"content"),
	)
	snapshot.role_bindings.append(
		GDSQLDatabaseRoleBinding.new(GDSQLDatabaseRegistry.SAVE_ROLE, &"save_1"),
	)
	var store := GDSQLConfigFileDatabaseRegistryStore.new(_registry_path)
	assert_bool(store.save_snapshot(snapshot).is_successful()).is_true()


func _add_save_registration(registration_name: StringName, data_root: String) -> void:
	var store := GDSQLConfigFileDatabaseRegistryStore.new(_registry_path)
	var loaded := store.load_snapshot()
	assert_bool(loaded.is_successful()).is_true()
	var snapshot := loaded.get_value() as GDSQLDatabaseRegistrySnapshot
	snapshot.registrations.append(
		GDSQLDatabaseRegistration.new(
			registration_name,
			registration_name,
			data_root,
			GDSQLStorageBackendIds.IN_MEMORY,
		),
	)
	assert_bool(store.save_snapshot(snapshot).is_successful()).is_true()
