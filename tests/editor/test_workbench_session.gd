class_name GDSQLWorkbenchSessionTest
extends GdUnitTestSuite

const TestDatabase = preload("res://tests/utils/gdsql_test_database.gd")

var _data_root: String
var _test_index := 0


func before_test() -> void:
	_test_index += 1
	_data_root = create_temp_dir("gdsql_workbench_%d" % _test_index)


func test_registration_opens_configfile_database() -> void:
	TestDatabase.create_heroes_database(_data_root)
	var registration := GDSQLDatabaseRegistration.new(
		&"project_content",
		&"game_config",
		_data_root,
		GDSQLStorageBackendIds.CONFIG_FILE,
	)
	var result := GDSQLRuntimeFactory.open_registration(registration)
	assert_bool(result.is_successful()).is_true()
	assert_str(String(result.get_database().database_name)).is_equal("game_config")


func test_in_memory_registration_hydrates_durable_rows_as_clean() -> void:
	var durable := TestDatabase.create_heroes_database(_data_root)
	TestDatabase.insert_basic_heroes(durable)
	var registration := GDSQLDatabaseRegistration.new(
		&"runtime_content",
		&"game_config",
		_data_root,
		GDSQLStorageBackendIds.IN_MEMORY,
	)
	var result := GDSQLRuntimeFactory.open_registration(registration)
	assert_bool(result.is_successful()).is_true()
	var database := result.get_database()
	var rows := database.execute(
		database.query().select().from_table(&"heroes").build(),
	)
	assert_bool(rows.is_successful()).is_true()
	assert_int(rows.rows.size()).is_equal(2)
	assert_bool((database.context.storage as GDSQLInMemoryTableStorage).is_dirty()).is_false()


func test_workbench_selects_pages_and_applies_previewed_change() -> void:
	var durable := TestDatabase.create_heroes_database(_data_root)
	TestDatabase.insert_basic_heroes(durable)
	var session := GDSQLWorkbenchSession.new()
	var registration := GDSQLDatabaseRegistration.new(
		&"project_content",
		&"game_config",
		_data_root,
		GDSQLStorageBackendIds.CONFIG_FILE,
	)
	assert_bool(session.open_registration(registration).is_successful()).is_true()
	assert_bool(session.select_table(&"heroes").is_successful()).is_true()
	assert_int(session.load_rows(1).rows.size()).is_equal(1)
	var preview := session.preview_table_change(
		[
			GDSQLTableAlteration.add_column(
				GDSQLColumnDefinition.new(&"level", TYPE_INT, false, false, false, 1),
			),
		],
	)
	assert_bool(preview.is_successful()).is_true()
	assert_bool(session.apply_pending_change().is_successful()).is_true()
	assert_object(session.selected_table.get_column(&"level")).is_not_null()


func test_explorer_reads_catalog_schema_and_table_headers() -> void:
	var database := TestDatabase.create_heroes_database(_data_root)
	TestDatabase.insert_basic_heroes(database)
	assert_bool(GDSQLDatabase.create(&"settings", _data_root).is_successful()).is_true()
	var explorer := GDSQLConfigFileDatabaseExplorer.new()
	var result := explorer.inspect_root(_data_root)
	assert_bool(result.is_successful()).is_true()
	var inspections: Array = result.get_value()
	assert_int(inspections.size()).is_equal(2)
	var content := _find_inspection(inspections, &"game_config")
	assert_object(content).is_not_null()
	var heroes := content.get_table(&"heroes")
	assert_object(heroes).is_not_null()
	assert_bool(heroes.schema_exists).is_true()
	assert_bool(heroes.storage_exists).is_true()
	assert_int(heroes.row_count).is_equal(2)
	assert_int(heroes.column_count).is_equal(2)
	assert_int(heroes.columns.size()).is_equal(2)
	assert_int(heroes.get_column(&"id").data_type).is_equal(TYPE_INT)
	assert_bool(heroes.get_column(&"name").nullable).is_false()


func test_workbench_loads_all_registrations_without_opening_rows() -> void:
	var project_root := _data_root.path_join("project")
	var save_root := _data_root.path_join("save_1")
	TestDatabase.create_heroes_database(project_root)
	TestDatabase.create_database(
		save_root,
		GDSQLTableDefinition.new(&"inventory", &"id") \
			.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true)),
		&"game_state",
	)
	var store := GDSQLConfigFileDatabaseRegistryStore.new(
		_data_root.path_join("registry.cfg"),
	)
	var registry := GDSQLDatabaseRegistry.new(store)
	var snapshot := GDSQLDatabaseRegistrySnapshot.new()
	snapshot.registrations = [
		GDSQLDatabaseRegistration.new(
			&"content",
			&"game_config",
			project_root,
		),
		GDSQLDatabaseRegistration.new(
			&"save_1",
			&"game_state",
			save_root,
		),
	]
	assert_bool(registry.save_snapshot(snapshot).is_successful()).is_true()

	var workbench := GDSQLWorkbench.new(
		registry,
		GDSQLConfigFileDatabaseExplorer.new(),
	)
	assert_bool(workbench.load().is_successful()).is_true()
	assert_int(workbench.get_registrations().size()).is_equal(2)
	assert_int(workbench.get_inspections().size()).is_equal(2)
	assert_object(workbench.active_session).is_null()
	var selected := workbench.select_registration(&"save_1")
	assert_bool(selected.is_successful()).is_true()
	assert_str(
		String(workbench.active_session.database.database_name),
	).is_equal("game_state")


func test_workbench_discovers_and_persists_known_save_children() -> void:
	var saves_root := _data_root.path_join("saves")
	for save_name in ["save_1", "save_2"]:
		TestDatabase.create_database(
			saves_root.path_join(save_name),
			GDSQLTableDefinition.new(&"state", &"id") \
				.add_column(
					GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true),
				),
			&"game_state",
		)
	var store := GDSQLConfigFileDatabaseRegistryStore.new(
		_data_root.path_join("registry.cfg"),
	)
	var registry := GDSQLDatabaseRegistry.new(store)
	assert_bool(
		registry.save_snapshot(GDSQLDatabaseRegistrySnapshot.new()).is_successful(),
	).is_true()
	var workbench := GDSQLWorkbench.new(
		registry,
		GDSQLConfigFileDatabaseExplorer.new(),
	)
	assert_bool(workbench.load().is_successful()).is_true()
	var discovered := workbench.discover_children(saves_root)
	assert_bool(discovered.is_successful()).is_true()
	assert_object(workbench.get_registration(&"save_1")).is_not_null()
	assert_object(workbench.get_registration(&"save_2")).is_not_null()
	var restored := registry.load_snapshot().get_value() \
			as GDSQLDatabaseRegistrySnapshot
	assert_int(restored.registrations.size()).is_equal(2)


func test_workbench_keeps_stale_registration_visible_as_missing() -> void:
	var store := GDSQLConfigFileDatabaseRegistryStore.new(
		_data_root.path_join("registry.cfg"),
	)
	var registry := GDSQLDatabaseRegistry.new(store)
	var snapshot := GDSQLDatabaseRegistrySnapshot.new()
	snapshot.registrations.append(
		GDSQLDatabaseRegistration.new(
			&"missing_save",
			&"game_state",
			_data_root.path_join("missing"),
		),
	)
	assert_bool(registry.save_snapshot(snapshot).is_successful()).is_true()
	var workbench := GDSQLWorkbench.new(
		registry,
		GDSQLConfigFileDatabaseExplorer.new(),
	)
	assert_bool(workbench.load().is_successful()).is_true()
	var inspection := workbench.get_inspection(&"missing_save")
	assert_object(inspection).is_not_null()
	assert_bool(inspection.catalog_exists).is_false()


func test_workbench_persists_updated_logical_database_name() -> void:
	var store := GDSQLConfigFileDatabaseRegistryStore.new(
		_data_root.path_join("registry.cfg"),
	)
	var registry := GDSQLDatabaseRegistry.new(store)
	var snapshot := GDSQLDatabaseRegistrySnapshot.new()
	snapshot.registrations.append(
		GDSQLDatabaseRegistration.new(
			&"project_content",
			&"base_content",
			_data_root,
		),
	)
	assert_bool(registry.save_snapshot(snapshot).is_successful()).is_true()
	var workbench := GDSQLWorkbench.new(
		registry,
		GDSQLConfigFileDatabaseExplorer.new(),
	)
	assert_bool(workbench.load().is_successful()).is_true()
	assert_bool(
		workbench.update_database_name(
			&"project_content",
			&"game_content",
		).is_successful(),
	).is_true()
	var restored := registry.load_snapshot().get_value() \
			as GDSQLDatabaseRegistrySnapshot
	assert_str(
		String(restored.registrations[0].database_name),
	).is_equal("game_content")


func _find_inspection(
		inspections: Array,
		database_name: StringName,
) -> GDSQLDatabaseInspection:
	for inspection in inspections:
		if inspection.registration.database_name == database_name:
			return inspection
	return null
