class_name GDSQLMigrationStartupCoordinator
extends RefCounted
## Brings one durable database to its trusted project schema head before use.

var _history_store: GDSQLMigrationHistoryStore
var _schema_state_store: GDSQLMigrationSchemaStateStore


func _init(
		history_store: GDSQLMigrationHistoryStore,
		schema_state_store: GDSQLMigrationSchemaStateStore,
) -> void:
	_history_store = history_store
	_schema_state_store = schema_state_store


func prepare(
		registration: GDSQLDatabaseRegistration,
		database: GDSQLDatabase,
) -> GDSQLMigrationStartupResult:
	var result := GDSQLMigrationStartupResult.new()
	if _history_store == null or _schema_state_store == null:
		return _error(
			result,
			&"GDSQL_MIGRATION_STARTUP_DEPENDENCY_REQUIRED",
			"Migration startup requires project history and schema-state stores.",
		)
	if registration == null or database == null \
			or registration.migration_stream == &"" \
			or registration.database_name != database.database_name:
		return _error(
			result,
			&"GDSQL_MIGRATION_STARTUP_REGISTRATION_INVALID",
			"Migration startup requires a matching durable database registration.",
		)
	var loaded_history := _history_store.load(registration.migration_stream)
	result.diagnostics.merge(loaded_history.diagnostics)
	if not loaded_history.is_successful():
		return result
	var history := loaded_history.get_value() as Array[GDSQLMigrationDefinition]
	var loaded_state := _schema_state_store.load(registration.migration_stream)
	result.diagnostics.merge(loaded_state.diagnostics)
	if not loaded_state.is_successful():
		return result
	var schema_state := loaded_state.get_value() as GDSQLMigrationSchemaState
	if schema_state == null:
		if history.is_empty():
			result.complete(database, false, 0)
			return result
		return _error(
			result,
			&"GDSQL_MIGRATION_SCHEMA_STATE_REQUIRED",
			"Authored migration history requires trusted project schema state before runtime startup.",
		)
	if schema_state.database_name != database.database_name \
			or not schema_state.matches_history_prefix(history):
		return _error(
			result,
			&"GDSQL_MIGRATION_SCHEMA_STATE_HISTORY_MISMATCH",
			"Runtime migration schema state does not match its database and authored history.",
		)
	var target_history: Array[GDSQLMigrationDefinition] = []
	for index in schema_state.history_count:
		target_history.append(history[index])
	if not _may_persist_runtime_ledger(registration.data_root):
		var project_fingerprint := _schema_fingerprint(database)
		if project_fingerprint.is_empty():
			return _error(
				result,
				&"GDSQL_MIGRATION_SCHEMA_FINGERPRINT_FAILED",
				"Runtime migration could not fingerprint the project database schema.",
			)
		if project_fingerprint != schema_state.schema_fingerprint:
			return _error(
				result,
				&"GDSQL_MIGRATION_PROJECT_SCHEMA_OUTDATED",
				(
						"Project database '%s' is not at its trusted migration head. "
						+ "Apply pending migrations in the editor before running or exporting."
				) % registration.database_name,
			)
		result.complete(database, true, target_history.size())
		return result
	var recovered := database.recover_pending_migrations(history)
	result.diagnostics.merge(recovered.diagnostics)
	if not recovered.is_successful():
		return result
	result.recovered_migration_ids = recovered.get_value() as PackedStringArray
	var current_fingerprint := _schema_fingerprint(database)
	if current_fingerprint.is_empty():
		return _error(
			result,
			&"GDSQL_MIGRATION_SCHEMA_FINGERPRINT_FAILED",
			"Runtime migration could not fingerprint the durable database schema.",
		)
	if current_fingerprint == schema_state.schema_fingerprint:
		var adopted := database.adopt_migration_baseline_if_current(
			target_history,
			schema_state,
		)
		result.diagnostics.merge(adopted.diagnostics)
		if not adopted.is_successful():
			return result
		result.baseline_adopted = bool(adopted.get_value())
	for iteration in target_history.size() + 1:
		var preview := database.preview_migrations(target_history)
		result.diagnostics.merge(preview.diagnostics)
		if not preview.is_successful():
			return result
		if preview.is_up_to_date():
			break
		if preview.next_plan == null:
			return _error(
				result,
				&"GDSQL_MIGRATION_STARTUP_PLAN_REQUIRED",
				"Runtime migration did not produce the next required catalog plan.",
			)
		var applied := database.apply_migration(preview.next_plan)
		result.diagnostics.merge(applied.diagnostics)
		if not applied.is_successful():
			return result
		result.applied_migration_ids.append(preview.next_plan.migration.migration_id)
		if iteration == target_history.size():
			return _error(
				result,
				&"GDSQL_MIGRATION_STARTUP_DID_NOT_CONVERGE",
				"Runtime migration did not reach the trusted project schema head.",
			)
	if _schema_fingerprint(database) != schema_state.schema_fingerprint:
		return _error(
			result,
			&"GDSQL_MIGRATION_STARTUP_TARGET_MISMATCH",
			"The migrated database schema does not match trusted project schema state.",
		)
	result.complete(database, true, target_history.size())
	return result


func _schema_fingerprint(database: GDSQLDatabase) -> String:
	return GDSQLSchemaFingerprint.compute(
		database.context.catalog.get_database(database.database_name),
	)


func _may_persist_runtime_ledger(data_root: String) -> bool:
	return not data_root.simplify_path().begins_with("res://")


func _error(
		result: GDSQLMigrationStartupResult,
		code: StringName,
		message: String,
) -> GDSQLMigrationStartupResult:
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
