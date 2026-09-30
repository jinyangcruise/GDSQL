class_name GDSQLMigrationService
extends RefCounted
## Supported orchestration boundary for migration preview, apply, and recovery.

var _ledger: GDSQLMigrationLedger
var _history_planner: GDSQLMigrationPlanner
var _catalog_planner: GDSQLMigrationCatalogPlanner
var _runner: GDSQLMigrationRunner
var _recovery: GDSQLMigrationRecoveryStore
var _catalog: GDSQLCatalogService


func _init(
		ledger: GDSQLMigrationLedger = null,
		history_planner: GDSQLMigrationPlanner = null,
		catalog_planner: GDSQLMigrationCatalogPlanner = null,
		runner: GDSQLMigrationRunner = null,
		recovery: GDSQLMigrationRecoveryStore = null,
		catalog: GDSQLCatalogService = null,
) -> void:
	_ledger = ledger
	_history_planner = history_planner
	_catalog_planner = catalog_planner
	_runner = runner
	_recovery = recovery
	_catalog = catalog


func preview(
		database_name: StringName,
		history: Array[GDSQLMigrationDefinition],
) -> GDSQLMigrationPreviewResult:
	var result := GDSQLMigrationPreviewResult.new()
	if _ledger == null or _history_planner == null or _catalog_planner == null \
			or _catalog == null:
		_error(
			result,
			&"GDSQL_MIGRATION_SERVICE_DEPENDENCY_REQUIRED",
			"Migration preview requires ledger and planning services.",
		)
		return result
	var loaded := _ledger.load(database_name)
	result.diagnostics.merge(loaded.diagnostics)
	if not loaded.is_successful():
		return result
	var ledger := loaded.get_value() as GDSQLMigrationLedgerSnapshot
	var evidence := _validate_schema_evidence(database_name, ledger)
	result.diagnostics.merge(evidence.diagnostics)
	if not evidence.is_successful():
		return result
	var planned := _history_planner.plan(history, ledger)
	result.diagnostics.merge(planned.diagnostics)
	if not planned.is_successful():
		return result
	var history_plan := planned.get_value() as GDSQLMigrationPlan
	if history_plan.is_up_to_date():
		result.complete(history_plan)
		return result
	var previewed := _catalog_planner.preview_next(database_name, history_plan)
	result.diagnostics.merge(previewed.diagnostics)
	if not previewed.is_successful():
		return result
	result.complete(
		history_plan,
		previewed.get_value() as GDSQLMigrationCatalogPlan,
	)
	return result


func adopt_baseline(
		database_name: StringName,
		history: Array[GDSQLMigrationDefinition],
		schema_state: GDSQLMigrationSchemaState,
) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if _ledger == null or _history_planner == null or _catalog == null:
		_error(
			result,
			&"GDSQL_MIGRATION_SERVICE_DEPENDENCY_REQUIRED",
			"Migration baseline adoption requires ledger, history, and catalog services.",
		)
		return result
	if schema_state == null or not schema_state.is_valid() \
			or schema_state.database_name != database_name:
		_error(
			result,
			&"GDSQL_MIGRATION_SCHEMA_STATE_INVALID",
			"Baseline adoption requires valid project-owned schema state for this database.",
		)
		return result
	var validated := _history_planner.plan(
		history,
		GDSQLMigrationLedgerSnapshot.new(),
	)
	result.diagnostics.merge(validated.diagnostics)
	if not validated.is_successful():
		return result
	if not schema_state.matches_history_prefix(history):
		_error(
			result,
			&"GDSQL_MIGRATION_SCHEMA_STATE_HISTORY_MISMATCH",
			"Project schema state does not match the authored migration-history prefix.",
		)
		return result
	var current_fingerprint := GDSQLSchemaFingerprint.compute(
		_catalog.get_database(database_name),
	)
	if current_fingerprint.is_empty():
		_error(
			result,
			&"GDSQL_MIGRATION_SCHEMA_FINGERPRINT_FAILED",
			"Could not fingerprint the database schema for baseline adoption.",
		)
		return result
	if current_fingerprint != schema_state.schema_fingerprint:
		_error(
			result,
			&"GDSQL_MIGRATION_BASELINE_SCHEMA_MISMATCH",
			"The database schema does not match the requested migration baseline.",
		)
		return result
	var loaded := _ledger.load(database_name)
	result.diagnostics.merge(loaded.diagnostics)
	if not loaded.is_successful():
		return result
	var snapshot := loaded.get_value() as GDSQLMigrationLedgerSnapshot
	if snapshot == null or snapshot.revision() != 0:
		_error(
			result,
			&"GDSQL_MIGRATION_BASELINE_ALREADY_ESTABLISHED",
			"A migration baseline can only be adopted by an empty ledger.",
		)
		return result
	var baseline := GDSQLMigrationBaseline.new(
		schema_state.migration_head_id,
		history[schema_state.history_count - 1].checksum \
		if schema_state.history_count > 0 else "",
		schema_state.history_checksum,
		int(Time.get_unix_time_from_system() * 1000.0),
		current_fingerprint,
	)
	var adopted := _ledger.adopt_baseline(database_name, baseline, 0)
	result.diagnostics.merge(adopted.diagnostics)
	if adopted.is_successful():
		result.value = baseline
	return result


func adopt_baseline_if_current(
		database_name: StringName,
		history: Array[GDSQLMigrationDefinition],
		schema_state: GDSQLMigrationSchemaState,
) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if _ledger == null or _history_planner == null or _catalog == null:
		_error(
			result,
			&"GDSQL_MIGRATION_SERVICE_DEPENDENCY_REQUIRED",
			"Conditional baseline adoption requires ledger, history, and catalog services.",
		)
		return result
	if schema_state == null or not schema_state.is_valid() \
			or schema_state.database_name != database_name \
			or not schema_state.matches_history_prefix(history):
		_error(
			result,
			&"GDSQL_MIGRATION_SCHEMA_STATE_INVALID",
			"Conditional baseline adoption requires matching project-owned schema state.",
		)
		return result
	var current_fingerprint := GDSQLSchemaFingerprint.compute(
		_catalog.get_database(database_name),
	)
	if current_fingerprint.is_empty():
		_error(
			result,
			&"GDSQL_MIGRATION_SCHEMA_FINGERPRINT_FAILED",
			"Could not fingerprint the database schema for baseline adoption.",
		)
		return result
	if current_fingerprint != schema_state.schema_fingerprint:
		result.value = false
		return result
	var loaded := _ledger.load(database_name)
	result.diagnostics.merge(loaded.diagnostics)
	if not loaded.is_successful():
		return result
	var snapshot := loaded.get_value() as GDSQLMigrationLedgerSnapshot
	if snapshot == null:
		_error(
			result,
			&"GDSQL_MIGRATION_LEDGER_INVALID",
			"Conditional baseline adoption requires a valid applied history.",
		)
		return result
	if snapshot.revision() != 0:
		result.value = false
		return result
	var adopted := adopt_baseline(database_name, history, schema_state)
	result.diagnostics.merge(adopted.diagnostics)
	if adopted.is_successful():
		result.value = true
	return result


func apply(plan: GDSQLMigrationCatalogPlan) -> GDSQLMigrationRunResult:
	if _runner != null:
		return _runner.apply(plan)
	var result := GDSQLMigrationRunResult.new()
	_error(
		result,
		&"GDSQL_MIGRATION_SERVICE_DEPENDENCY_REQUIRED",
		"Migration application requires a migration runner.",
	)
	return result


func recover_pending(
		database_name: StringName,
		history: Array[GDSQLMigrationDefinition],
) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if _ledger == null or _history_planner == null or _recovery == null:
		_error(
			result,
			&"GDSQL_MIGRATION_SERVICE_DEPENDENCY_REQUIRED",
			"Startup recovery requires ledger, history, and recovery services.",
		)
		return result
	var validated := _history_planner.plan(
		history,
		GDSQLMigrationLedgerSnapshot.new(),
	)
	result.diagnostics.merge(validated.diagnostics)
	if not validated.is_successful():
		return result
	var authored_ids: Dictionary[String, bool] = { }
	for migration in history:
		authored_ids[migration.migration_id] = true
	var listed := _recovery.list_backups(database_name)
	result.diagnostics.merge(listed.diagnostics)
	if not listed.is_successful():
		return result
	var resolved_ids := PackedStringArray()
	for migration_id_value in listed.get_value() as PackedStringArray:
		var migration_id := String(migration_id_value)
		if not authored_ids.has(migration_id):
			_error(
				result,
				&"GDSQL_MIGRATION_RECOVERY_HISTORY_MISSING",
				"Recovery snapshot migration '%s' is absent from project history." \
						% migration_id,
			)
			return result
		var recovered := recover_interrupted(database_name, migration_id)
		result.diagnostics.merge(recovered.diagnostics)
		if not recovered.is_successful():
			return result
		resolved_ids.append(migration_id)
	result.value = resolved_ids
	return result


func recover_interrupted(
		database_name: StringName,
		migration_id: String,
) -> GDSQLMigrationRecoveryResult:
	var result := GDSQLMigrationRecoveryResult.new()
	if _ledger == null or _recovery == null:
		_error(
			result,
			&"GDSQL_MIGRATION_SERVICE_DEPENDENCY_REQUIRED",
			"Interrupted migration recovery requires ledger and recovery services.",
		)
		return result
	var loaded_backup := _recovery.load_backup(database_name, migration_id)
	result.diagnostics.merge(loaded_backup.diagnostics)
	if not loaded_backup.is_successful():
		return result
	result.backup = loaded_backup.get_value() as GDSQLMigrationBackup
	if result.backup == null or not result.backup.is_valid():
		_error(
			result,
			&"GDSQL_MIGRATION_BACKUP_INVALID",
			"Interrupted migration recovery requires a valid durable backup.",
		)
		return result
	result.backup_retained = true
	var loaded_ledger := _ledger.load(database_name)
	result.diagnostics.merge(loaded_ledger.diagnostics)
	if not loaded_ledger.is_successful():
		return result
	var snapshot := loaded_ledger.get_value() as GDSQLMigrationLedgerSnapshot
	if snapshot == null:
		_error(
			result,
			&"GDSQL_MIGRATION_LEDGER_INVALID",
			"Interrupted migration recovery requires a valid applied history.",
		)
		return result
	if snapshot.find(migration_id) != null:
		result.complete(
			GDSQLMigrationRecoveryResult.Status.COMMITTED_BACKUP_DISCARDED,
			result.backup,
		)
		_discard_backup(result)
		return result
	if not snapshot.last_id().is_empty() and snapshot.last_id() > migration_id:
		_error(
			result,
			&"GDSQL_MIGRATION_RECOVERY_HISTORY_DIVERGED",
			(
					"Migration '%s' is absent, but later migration '%s' is applied; "
					+ "automatic recovery is unsafe."
			) % [migration_id, snapshot.last_id()],
		)
		return result
	var restored := _recovery.restore(result.backup)
	result.diagnostics.merge(restored.diagnostics)
	if not restored.is_successful():
		return result
	result.complete(GDSQLMigrationRecoveryResult.Status.RESTORED, result.backup)
	_discard_backup(result)
	return result


func _discard_backup(result: GDSQLMigrationRecoveryResult) -> void:
	var discarded := _recovery.discard(
		result.backup.database_name,
		result.backup.migration_id,
	)
	if discarded.is_successful():
		result.backup_retained = false
		return
	for diagnostic in discarded.diagnostics.entries:
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_MIGRATION_BACKUP_CLEANUP_PENDING",
				diagnostic.message,
				GDSQLQueryDiagnostic.Severity.WARNING,
			),
		)


func _validate_schema_evidence(
		database_name: StringName,
		ledger: GDSQLMigrationLedgerSnapshot,
) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if ledger == null:
		_error(
			result,
			&"GDSQL_MIGRATION_LEDGER_INVALID",
			"Migration preview requires a valid applied-history snapshot.",
		)
		return result
	var recorded_fingerprint := ledger.last_schema_fingerprint()
	if recorded_fingerprint.is_empty():
		return result
	var current_fingerprint := GDSQLSchemaFingerprint.compute(
		_catalog.get_database(database_name),
	)
	if current_fingerprint.is_empty():
		_error(
			result,
			&"GDSQL_MIGRATION_SCHEMA_FINGERPRINT_FAILED",
			"Could not fingerprint the current database schema.",
		)
	elif current_fingerprint != recorded_fingerprint:
		_error(
			result,
			&"GDSQL_MIGRATION_SCHEMA_DRIFT",
			"The current database schema differs from its migration ledger.",
		)
	return result


func _error(
		result: GDSQLOperationResult,
		code: StringName,
		message: String,
) -> void:
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
