class_name GDSQLRuntimeBootstrapTest
extends GdUnitTestSuite

var _test_root: String
var _registry_path: String
var _content_root: String
var _save_root: String
var _history_root: String
var _state_root: String
var _test_index := 0


func before_test() -> void:
	GDSQLModels.clear_context()
	_test_index += 1
	_test_root = create_temp_dir("gdsql_runtime_bootstrap_%d" % _test_index)
	_registry_path = _test_root.path_join("registry.cfg")
	_content_root = _test_root.path_join("content")
	_save_root = _test_root.path_join("save")
	_history_root = _test_root.path_join("migrations")
	_state_root = _test_root.path_join("migration_states")
	_create_database(&"content", _content_root)
	var save := _create_database(&"save_1", _save_root)
	assert_bool(save.insert(&"heroes", { &"id": 1, &"name": "Knight" }).is_successful()).is_true()
	_save_registry_snapshot()


func after_test() -> void:
	GDSQLModels.clear_context()


func test_bootstrap_opens_registrations_restores_roles_and_models() -> void:
	var result := _bootstrap()
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
	var runtime := _bootstrap().get_value() \
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
	var runtime := _bootstrap().get_value() \
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
	var runtime := _bootstrap().get_value() \
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

	var result := _bootstrap()

	assert_bool(result.is_successful()).is_false()
	assert_object(result.get_value()).is_null()
	assert_object(GDSQLModels.get_context()).is_null()


func test_bootstrap_migrates_durable_save_before_in_memory_hydration() -> void:
	var migration := _add_level_migration()
	var history: Array[GDSQLMigrationDefinition] = [migration]
	var alterations: Array[GDSQLTableAlteration] = [_add_level_alteration()]
	assert_bool(
		_history_store().append(&"save_1", migration, 0).is_successful(),
	).is_true()
	var target := _create_database(
		&"save_1",
		_test_root.path_join("target_save"),
	)
	assert_bool(
		target.alter_table(&"heroes", alterations).is_successful(),
	).is_true()
	_save_target_state(
		&"save_1",
		history,
		GDSQLSchemaFingerprint.compute(
			target.context.catalog.get_database(target.database_name),
		),
	)

	var result := _bootstrap()
	var runtime := result.get_value() as GDSQLRuntimeSession
	var save := runtime.database(GDSQLDatabaseRegistry.SAVE_ROLE).get_database()
	var rows := save.execute(save.table(&"heroes").select().build())

	assert_bool(result.is_successful()).is_true()
	assert_object(
		save.context.catalog.get_table(save.database_name, &"heroes").get_column(&"level"),
	).is_not_null()
	assert_int(rows.rows[0].get_value(&"level")).is_equal(1)
	var ledger := GDSQLConfigFileMigrationLedger.new(
		GDSQLDatabasePathResolver.new(_save_root),
	).load(&"save_1").get_value() as GDSQLMigrationLedgerSnapshot
	assert_str(ledger.last_id()).is_equal(migration.migration_id)


func test_bootstrap_baselines_a_writable_save_already_at_the_target_schema() -> void:
	var migration := _add_level_migration()
	var history: Array[GDSQLMigrationDefinition] = [migration]
	var alterations: Array[GDSQLTableAlteration] = [_add_level_alteration()]
	assert_bool(
		_history_store().append(&"save_1", migration, 0).is_successful(),
	).is_true()
	var save := GDSQLDatabase.open(&"save_1", _save_root).get_database()
	assert_bool(
		save.alter_table(&"heroes", alterations).is_successful(),
	).is_true()
	_save_target_state(
		&"save_1",
		history,
		GDSQLSchemaFingerprint.compute(
			save.context.catalog.get_database(save.database_name),
		),
	)

	var result := _bootstrap()
	var ledger := GDSQLConfigFileMigrationLedger.new(
		GDSQLDatabasePathResolver.new(_save_root),
	).load(&"save_1").get_value() as GDSQLMigrationLedgerSnapshot

	assert_bool(result.is_successful()).is_true()
	assert_object(ledger.baseline).is_not_null()
	assert_str(ledger.baseline.through_migration_id).is_equal(migration.migration_id)
	assert_array(ledger.records).is_empty()


func test_startup_accepts_project_content_at_the_trusted_head_without_a_ledger() -> void:
	var migration := _add_level_migration()
	var history: Array[GDSQLMigrationDefinition] = [migration]
	assert_bool(
		_history_store().append(&"content", migration, 0).is_successful(),
	).is_true()
	var content := GDSQLDatabase.open(&"content", _content_root).get_database()
	assert_bool(
		content.alter_table(&"heroes", [_add_level_alteration()]).is_successful(),
	).is_true()
	_save_schema_state(
		&"content",
		&"content",
		history,
		GDSQLSchemaFingerprint.compute(
			content.context.catalog.get_database(content.database_name),
		),
	)
	var registration := GDSQLDatabaseRegistration.new(
		&"content",
		&"content",
		"res://data",
		GDSQLStorageBackendIds.CONFIG_FILE,
		&"content",
	)

	var result := GDSQLMigrationStartupCoordinator.new(
		_history_store(),
		GDSQLConfigFileMigrationSchemaStateStore.new(_state_root),
	).prepare(registration, content)

	assert_bool(result.is_successful()).is_true()
	assert_bool(result.migration_configured).is_true()
	assert_int(result.target_history_count).is_equal(1)
	assert_bool(result.baseline_adopted).is_false()
	assert_array(result.applied_migration_ids).is_empty()
	var ledger := GDSQLConfigFileMigrationLedger.new(
		GDSQLDatabasePathResolver.new(_content_root),
	).load(&"content").get_value() as GDSQLMigrationLedgerSnapshot
	assert_object(ledger.baseline).is_null()
	assert_array(ledger.records).is_empty()


func test_startup_rejects_outdated_project_content_without_mutating_it() -> void:
	var migration := _add_level_migration()
	var history: Array[GDSQLMigrationDefinition] = [migration]
	assert_bool(
		_history_store().append(&"content", migration, 0).is_successful(),
	).is_true()
	var target := _create_database(
		&"content",
		_test_root.path_join("target_content"),
	)
	assert_bool(
		target.alter_table(&"heroes", [_add_level_alteration()]).is_successful(),
	).is_true()
	_save_schema_state(
		&"content",
		&"content",
		history,
		GDSQLSchemaFingerprint.compute(
			target.context.catalog.get_database(target.database_name),
		),
	)
	var content := GDSQLDatabase.open(&"content", _content_root).get_database()
	var registration := GDSQLDatabaseRegistration.new(
		&"content",
		&"content",
		"res://data",
		GDSQLStorageBackendIds.CONFIG_FILE,
		&"content",
	)

	var result := GDSQLMigrationStartupCoordinator.new(
		_history_store(),
		GDSQLConfigFileMigrationSchemaStateStore.new(_state_root),
	).prepare(registration, content)

	assert_bool(result.is_successful()).is_false()
	assert_str(String(result.diagnostics.entries[-1].code)).is_equal(
		"GDSQL_MIGRATION_PROJECT_SCHEMA_OUTDATED",
	)
	assert_object(
		content.context.catalog.get_table(&"content", &"heroes").get_column(&"level"),
	).is_null()
	var ledger := GDSQLConfigFileMigrationLedger.new(
		GDSQLDatabasePathResolver.new(_content_root),
	).load(&"content").get_value() as GDSQLMigrationLedgerSnapshot
	assert_object(ledger.baseline).is_null()
	assert_array(ledger.records).is_empty()


func test_bootstrap_rejects_authored_history_without_trusted_schema_state() -> void:
	assert_bool(
		_history_store().append(&"save_1", _add_level_migration(), 0).is_successful(),
	).is_true()

	var result := _bootstrap()

	assert_bool(result.is_successful()).is_false()
	assert_object(result.get_value()).is_null()
	assert_object(GDSQLModels.get_context()).is_null()
	assert_str(String(result.diagnostics.entries[-1].code)).is_equal(
		"GDSQL_MIGRATION_SCHEMA_STATE_REQUIRED",
	)


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


func _bootstrap() -> GDSQLOperationResult:
	return GDSQLRuntimeFactory.bootstrap(
		_registry_path,
		{ },
		null,
		GDSQLSetupProfile.Kind.DIRECT,
		GDSQLMigrationStartupCoordinator.new(
			_history_store(),
			GDSQLConfigFileMigrationSchemaStateStore.new(_state_root),
		),
	)


func _history_store() -> GDSQLConfigFileMigrationHistoryStore:
	return GDSQLConfigFileMigrationHistoryStore.new(_history_root)


func _add_level_migration() -> GDSQLMigrationDefinition:
	var alterations: Array[GDSQLTableAlteration] = [_add_level_alteration()]
	var steps: Array[GDSQLSchemaMigrationStep] = [
		GDSQLSchemaMigrationStep.new(&"heroes", alterations),
	]
	return GDSQLMigrationDefinition.new(
		"202609290001_add_level",
		"Add save hero level",
		steps,
	)


func _add_level_alteration() -> GDSQLTableAlteration:
	return GDSQLTableAlteration.add_column(
		GDSQLColumnDefinition.new(&"level", TYPE_INT, false, false, false, 1),
	)


func _save_target_state(
		stream: StringName,
		history: Array[GDSQLMigrationDefinition],
		fingerprint: String,
) -> void:
	_save_schema_state(stream, &"save_1", history, fingerprint)


func _save_schema_state(
		stream: StringName,
		database_name: StringName,
		history: Array[GDSQLMigrationDefinition],
		fingerprint: String,
) -> void:
	var state := GDSQLMigrationSchemaState.from_history(
		stream,
		database_name,
		history,
		fingerprint,
	)
	assert_bool(
		GDSQLConfigFileMigrationSchemaStateStore.new(_state_root) \
				.save(state, "").is_successful(),
	).is_true()
