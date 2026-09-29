class_name GDSQLMigrationHistoryStoreTest
extends GdUnitTestSuite

var _history_root: String
var _test_index := 0


func before_test() -> void:
	_test_index += 1
	_history_root = create_temp_dir("gdsql_migration_history_%d" % _test_index)


func test_definition_serializer_round_trips_every_schema_alteration_shape() -> void:
	var added_column := GDSQLColumnDefinition.new(
		&"level",
		TYPE_INT,
		false,
		false,
		false,
		1,
	)
	var index_columns: Array[StringName] = [&"level"]
	var ordered_columns: Array[StringName] = [&"id", &"name", &"level"]
	var alterations: Array[GDSQLTableAlteration] = [
		GDSQLTableAlteration.add_column(added_column),
		GDSQLTableAlteration.rename_column(&"title", &"display_name"),
		GDSQLTableAlteration.drop_column(&"legacy"),
		GDSQLTableAlteration.add_index(
			GDSQLIndexDefinition.new(&"level_idx", index_columns, true),
		),
		GDSQLTableAlteration.drop_index(&"legacy_idx"),
		GDSQLTableAlteration.add_foreign_key(
			GDSQLForeignKeyDefinition.new(
				&"heroes_class_id_classes_id_fk",
				&"class_id",
				&"classes",
				&"id",
			),
		),
		GDSQLTableAlteration.drop_foreign_key(&"legacy_fk"),
		GDSQLTableAlteration.set_column_default(&"level", 2),
		GDSQLTableAlteration.clear_column_default(&"title"),
		GDSQLTableAlteration.set_column_nullable(&"title", false),
		GDSQLTableAlteration.set_column_unique(&"slug", true),
		GDSQLTableAlteration.set_column_auto_increment(&"id", true),
		GDSQLTableAlteration.set_column_generation(
			&"updated_at",
			GDSQLColumnDefinition.Generation.UPDATED_AT,
		),
		GDSQLTableAlteration.set_resource_ownership(
			&"portrait",
			GDSQLResourceOwnership.Mode.REFERENCED,
		),
		GDSQLTableAlteration.reorder_columns(ordered_columns),
	]
	var migration := _migration("202609290001_all_shapes", alterations)

	var decoded := GDSQLMigrationDefinitionSerializer.decode(
		GDSQLMigrationDefinitionSerializer.encode(migration),
	)

	assert_bool(decoded.is_successful()).is_true()
	var restored := decoded.get_value() as GDSQLMigrationDefinition
	assert_str(restored.checksum).is_equal(migration.checksum)
	assert_int(restored.steps[0].alterations.size()).is_equal(alterations.size())
	var restored_column := restored.steps[0].alterations[0].column
	assert_str(restored_column.name).is_equal("level")
	assert_int(restored_column.get_default_value()).is_equal(1)
	assert_bool(restored.steps[0].alterations[3].index.unique).is_true()
	assert_str(
		restored.steps[0].alterations[5].foreign_key.referenced_table,
	).is_equal("classes")
	assert_array(restored.steps[0].alterations[-1].column_names).contains_exactly(
		ordered_columns,
	)


func test_history_store_appends_ordered_files_and_rejects_stale_writers() -> void:
	var store := _store()
	var first := _add_level_migration("202609290001_add_level")
	var second := _add_level_migration("202609290002_add_rank", &"rank")

	assert_bool(store.append(&"game_state", first, 0).is_successful()).is_true()
	var stale := store.append(&"game_state", second, 0)
	assert_str(_first_code(stale)).is_equal("GDSQL_MIGRATION_HISTORY_STALE")
	assert_bool(store.append(&"game_state", second, 1).is_successful()).is_true()

	var loaded := store.load(&"game_state")
	assert_bool(loaded.is_successful()).is_true()
	var history := loaded.get_value() as Array[GDSQLMigrationDefinition]
	assert_int(history.size()).is_equal(2)
	assert_str(history[0].migration_id).is_equal(first.migration_id)
	assert_str(history[1].migration_id).is_equal(second.migration_id)
	assert_bool(
		FileAccess.file_exists(
			_history_root.path_join("game_state/%s.cfg" % first.migration_id),
		),
	).is_true()


func test_history_store_detects_changed_authored_files() -> void:
	var store := _store()
	var migration := _add_level_migration("202609290001_add_level")
	assert_bool(store.append(&"content", migration, 0).is_successful()).is_true()
	var path := _history_root.path_join(
		"content/%s.cfg" % migration.migration_id,
	)
	var config := ConfigFile.new()
	assert_int(config.load(path)).is_equal(OK)
	var payload := config.get_value("migration", "definition") as Dictionary
	payload["description"] = "Edited after recording"
	config.set_value("migration", "definition", payload)
	assert_int(config.save(path)).is_equal(OK)

	var loaded := store.load(&"content")

	assert_bool(loaded.is_successful()).is_false()
	assert_str(_first_code(loaded)).is_equal(
		"GDSQL_MIGRATION_HISTORY_CHECKSUM_MISMATCH",
	)


func test_registration_defaults_and_persists_a_stable_migration_stream() -> void:
	var registry_path := _history_root.path_join("databases.cfg")
	var legacy := ConfigFile.new()
	legacy.set_value("database:save_1", "database_name", &"game_state")
	legacy.set_value("database:save_1", "data_root", "user://gdsql/saves/save_1")
	legacy.set_value(
		"database:save_1",
		"storage_backend_id",
		GDSQLStorageBackendIds.CONFIG_FILE,
	)
	assert_int(legacy.save(registry_path)).is_equal(OK)
	var store := GDSQLConfigFileDatabaseRegistryStore.new(registry_path)
	var loaded := store.load_snapshot()
	var snapshot := loaded.get_value() as GDSQLDatabaseRegistrySnapshot

	assert_str(snapshot.registrations[0].migration_stream).is_equal("game_state")
	snapshot.registrations[0].migration_stream = &"player_state_v1"
	snapshot.registrations[0].database_name = &"renamed_state"
	assert_bool(store.save_snapshot(snapshot).is_successful()).is_true()
	var reopened := store.load_snapshot().get_value() as GDSQLDatabaseRegistrySnapshot
	assert_str(reopened.registrations[0].database_name).is_equal("renamed_state")
	assert_str(reopened.registrations[0].migration_stream).is_equal(
		"player_state_v1",
	)


func _store() -> GDSQLConfigFileMigrationHistoryStore:
	return GDSQLConfigFileMigrationHistoryStore.new(_history_root)


func _add_level_migration(
		migration_id: String,
		column_name: StringName = &"level",
) -> GDSQLMigrationDefinition:
	var alterations: Array[GDSQLTableAlteration] = [
		GDSQLTableAlteration.add_column(
			GDSQLColumnDefinition.new(
				column_name,
				TYPE_INT,
				false,
				false,
				false,
				1,
			),
		),
	]
	return _migration(migration_id, alterations)


func _migration(
		migration_id: String,
		alterations: Array[GDSQLTableAlteration],
) -> GDSQLMigrationDefinition:
	var steps: Array[GDSQLSchemaMigrationStep] = [
		GDSQLSchemaMigrationStep.new(&"heroes", alterations),
	]
	return GDSQLMigrationDefinition.new(
		migration_id,
		"Migration %s" % migration_id,
		steps,
	)


func _first_code(result: GDSQLOperationResult) -> String:
	return String(result.diagnostics.entries[0].code)
