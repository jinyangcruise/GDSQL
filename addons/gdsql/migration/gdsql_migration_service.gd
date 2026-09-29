class_name GDSQLMigrationService
extends RefCounted
## Supported orchestration boundary for migration preview, apply, and recovery.

var _ledger: GDSQLMigrationLedger
var _history_planner: GDSQLMigrationPlanner
var _catalog_planner: GDSQLMigrationCatalogPlanner
var _runner: GDSQLMigrationRunner
var _recovery: GDSQLMigrationRecoveryStore


func _init(
		ledger: GDSQLMigrationLedger = null,
		history_planner: GDSQLMigrationPlanner = null,
		catalog_planner: GDSQLMigrationCatalogPlanner = null,
		runner: GDSQLMigrationRunner = null,
		recovery: GDSQLMigrationRecoveryStore = null,
) -> void:
	_ledger = ledger
	_history_planner = history_planner
	_catalog_planner = catalog_planner
	_runner = runner
	_recovery = recovery


func preview(
		database_name: StringName,
		history: Array[GDSQLMigrationDefinition],
) -> GDSQLMigrationPreviewResult:
	var result := GDSQLMigrationPreviewResult.new()
	if _ledger == null or _history_planner == null or _catalog_planner == null:
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
	var planned := _history_planner.plan(history, loaded.get_value())
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


func _error(
		result: GDSQLOperationResult,
		code: StringName,
		message: String,
) -> void:
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
