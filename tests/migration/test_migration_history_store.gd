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
	var restored_step := restored.steps[0] as GDSQLSchemaMigrationStep
	assert_str(restored.checksum).is_equal(migration.checksum)
	assert_int(restored_step.alterations.size()).is_equal(alterations.size())
	var restored_column := restored_step.alterations[0].column
	assert_str(restored_column.name).is_equal("level")
	assert_int(restored_column.get_default_value()).is_equal(1)
	assert_bool(restored_step.alterations[3].index.unique).is_true()
	assert_str(
		restored_step.alterations[5].foreign_key.referenced_table,
	).is_equal("classes")
	assert_array(restored_step.alterations[-1].column_names).contains_exactly(
		ordered_columns,
	)


func test_definition_serializer_round_trips_create_table_step() -> void:
	var table := GDSQLTableDefinition.new(&"inventory", &"id")
	table.add_column(GDSQLColumnDefinition.new(&"id", TYPE_INT, false, true, true))
	table.add_column(GDSQLColumnDefinition.new(&"item_id", TYPE_STRING_NAME, false))
	var index_columns: Array[StringName] = [&"item_id"]
	table.add_index(GDSQLIndexDefinition.new(&"inventory_item_idx", index_columns))
	var steps: Array[GDSQLSchemaMigrationStep] = [
		GDSQLSchemaMigrationStep.create_table(table),
	]
	var migration := GDSQLMigrationDefinition.new(
		"202609290001_create_inventory",
		"Create inventory table",
		steps,
	)

	var decoded := GDSQLMigrationDefinitionSerializer.decode(
		GDSQLMigrationDefinitionSerializer.encode(migration),
	)

	assert_bool(decoded.is_successful()).is_true()
	var restored := decoded.get_value() as GDSQLMigrationDefinition
	var restored_step := restored.steps[0] as GDSQLSchemaMigrationStep
	assert_str(restored.checksum).is_equal(migration.checksum)
	assert_int(restored_step.kind).is_equal(
		GDSQLSchemaMigrationStep.Kind.CREATE_TABLE,
	)
	assert_str(restored_step.table_definition.name).is_equal("inventory")
	assert_str(restored_step.table_definition.primary_key).is_equal("id")
	assert_int(restored_step.table_definition.columns.size()).is_equal(2)
	assert_str(restored_step.table_definition.indexes[0].name).is_equal(
		"inventory_item_idx",
	)


func test_definition_serializer_round_trips_table_lifecycle_steps() -> void:
	var steps: Array[GDSQLSchemaMigrationStep] = [
		GDSQLSchemaMigrationStep.rename_table(&"heroes", &"characters"),
		GDSQLSchemaMigrationStep.drop_table(&"legacy_heroes"),
	]
	var migration := GDSQLMigrationDefinition.new(
		"202609290001_table_lifecycle",
		"Rename and remove tables",
		steps,
	)

	var decoded := GDSQLMigrationDefinitionSerializer.decode(
		GDSQLMigrationDefinitionSerializer.encode(migration),
	)

	assert_bool(decoded.is_successful()).is_true()
	var restored := decoded.get_value() as GDSQLMigrationDefinition
	var rename_step := restored.steps[0] as GDSQLSchemaMigrationStep
	var drop_step := restored.steps[1] as GDSQLSchemaMigrationStep
	assert_str(restored.checksum).is_equal(migration.checksum)
	assert_int(rename_step.kind).is_equal(
		GDSQLSchemaMigrationStep.Kind.RENAME_TABLE,
	)
	assert_str(rename_step.table_name).is_equal("heroes")
	assert_str(rename_step.new_table_name).is_equal("characters")
	assert_int(drop_step.kind).is_equal(
		GDSQLSchemaMigrationStep.Kind.DROP_TABLE,
	)
	assert_bool(drop_step.is_destructive()).is_true()


func test_definition_serializer_round_trips_a_typed_data_update() -> void:
	var assignments: Array[GDSQLColumnAssignment] = [
		GDSQLColumnAssignment.new(
			&"name",
			GDSQLFunctionExpression.new(
				&"upper",
				[GDSQLColumnExpression.new(&"name")],
			),
		),
	]
	var predicate := GDSQLColumnExpression.new(&"id").greater_than(10)
	var migration := GDSQLMigrationDefinition.new(
		"202609290001_normalize_names",
		"Normalize hero names",
		[GDSQLDataMigrationStep.new(&"heroes", assignments, predicate)],
	)

	var decoded := GDSQLMigrationDefinitionSerializer.decode(
		GDSQLMigrationDefinitionSerializer.encode(migration),
	)

	assert_bool(decoded.is_successful()).is_true()
	var restored := decoded.get_value() as GDSQLMigrationDefinition
	assert_str(restored.checksum).is_equal(migration.checksum)
	assert_bool(restored.steps[0] is GDSQLDataMigrationStep).is_true()
	var step := restored.steps[0] as GDSQLDataMigrationStep
	assert_str(step.table_name).is_equal("heroes")
	assert_str(step.assignments[0].column).is_equal("name")
	assert_bool(step.assignments[0].expression is GDSQLFunctionExpression).is_true()
	assert_bool(step.predicate is GDSQLComparisonExpression).is_true()
	assert_bool(step.is_destructive()).is_true()


func test_data_migration_rejects_unserializable_expression_values() -> void:
	var assignments: Array[GDSQLColumnAssignment] = [
		GDSQLColumnAssignment.new(
			&"name",
			GDSQLLiteralExpression.new(Resource.new()),
		),
	]

	var step := GDSQLDataMigrationStep.new(&"heroes", assignments)

	assert_bool(step.is_valid()).is_false()


func test_definition_serializer_keeps_existing_alteration_files_readable() -> void:
	var migration := _add_level_migration("202609290001_add_level")
	var payload := GDSQLMigrationDefinitionSerializer.encode(migration)
	var steps := payload["steps"] as Array
	var legacy_step := steps[0] as Dictionary
	legacy_step.erase("kind")

	var decoded := GDSQLMigrationDefinitionSerializer.decode(payload)

	assert_bool(decoded.is_successful()).is_true()
	var restored := decoded.get_value() as GDSQLMigrationDefinition
	var restored_step := restored.steps[0] as GDSQLSchemaMigrationStep
	assert_str(restored.checksum).is_equal(migration.checksum)
	assert_int(restored_step.kind).is_equal(
		GDSQLSchemaMigrationStep.Kind.ALTER_TABLE,
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


func test_schema_state_store_advances_verified_history_with_stale_protection() -> void:
	var state_root := _history_root.path_join("states")
	var store := GDSQLConfigFileMigrationSchemaStateStore.new(state_root)
	var first := _add_level_migration("202609290001_add_level")
	var second := _add_level_migration("202609290002_add_rank", &"rank")
	var history: Array[GDSQLMigrationDefinition] = [first, second]
	var first_state := GDSQLMigrationSchemaState.from_history(
		&"game_state",
		&"game_state",
		history,
		"a".repeat(64),
		1,
	)
	var second_state := GDSQLMigrationSchemaState.from_history(
		&"game_state",
		&"game_state",
		history,
		"b".repeat(64),
	)

	assert_bool(store.save(first_state, "").is_successful()).is_true()
	var replaced_first_state := GDSQLMigrationSchemaState.from_history(
		&"game_state",
		&"game_state",
		history,
		"c".repeat(64),
		1,
	)
	var replaced := store.save(
		replaced_first_state,
		first_state.history_checksum,
	)
	assert_str(_first_code(replaced)).is_equal(
		"GDSQL_MIGRATION_SCHEMA_STATE_DIVERGED",
	)
	var stale := store.save(second_state, "")
	assert_str(_first_code(stale)).is_equal("GDSQL_MIGRATION_SCHEMA_STATE_STALE")
	assert_bool(
		store.save(second_state, first_state.history_checksum).is_successful(),
	).is_true()

	var loaded := store.load(&"game_state")
	assert_bool(loaded.is_successful()).is_true()
	var restored := loaded.get_value() as GDSQLMigrationSchemaState
	assert_int(restored.history_count).is_equal(2)
	assert_str(restored.migration_head_id).is_equal(second.migration_id)
	assert_str(restored.schema_fingerprint).is_equal("b".repeat(64))
	var rollback := store.save(first_state, second_state.history_checksum)
	assert_str(_first_code(rollback)).is_equal(
		"GDSQL_MIGRATION_SCHEMA_STATE_DIVERGED",
	)


func test_schema_state_supports_an_empty_authored_history_origin() -> void:
	var history: Array[GDSQLMigrationDefinition] = []
	var state := GDSQLMigrationSchemaState.from_history(
		&"game_state",
		&"game_state",
		history,
		"a".repeat(64),
	)

	assert_bool(state.is_valid()).is_true()
	assert_int(state.history_count).is_equal(0)
	assert_str(state.migration_head_id).is_empty()
	assert_bool(state.matches_history_prefix(history)).is_true()
	var store := GDSQLConfigFileMigrationSchemaStateStore.new(
		_history_root.path_join("origin_states"),
	)
	assert_bool(store.save(state, "").is_successful()).is_true()
	var changed_origin := GDSQLMigrationSchemaState.from_history(
		&"game_state",
		&"game_state",
		history,
		"b".repeat(64),
	)
	assert_bool(
		store.save(changed_origin, state.history_checksum).is_successful(),
	).is_true()


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
