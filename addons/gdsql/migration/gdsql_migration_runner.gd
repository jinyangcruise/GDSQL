class_name GDSQLMigrationRunner
extends RefCounted
## Applies one previewed migration with durable rollback and ledger evidence.

var _catalog: GDSQLCatalogService
var _catalog_administration: GDSQLCatalogAdministrationService
var _ledger: GDSQLMigrationLedger
var _recovery: GDSQLMigrationRecoveryStore


func _init(
		catalog: GDSQLCatalogService = null,
		catalog_administration: GDSQLCatalogAdministrationService = null,
		ledger: GDSQLMigrationLedger = null,
		recovery: GDSQLMigrationRecoveryStore = null,
) -> void:
	_catalog = catalog
	_catalog_administration = catalog_administration
	_ledger = ledger
	_recovery = recovery


func apply(plan: GDSQLMigrationCatalogPlan) -> GDSQLMigrationRunResult:
	var result := GDSQLMigrationRunResult.new()
	var validation := _validate_plan(plan)
	result.diagnostics.merge(validation.diagnostics)
	if not result.is_successful():
		return result
	var loaded := _ledger.load(plan.database_name)
	result.diagnostics.merge(loaded.diagnostics)
	if not result.is_successful():
		return result
	var ledger := loaded.get_value() as GDSQLMigrationLedgerSnapshot
	if ledger == null or ledger.revision() != plan.expected_ledger_revision:
		return _error(
			result,
			&"GDSQL_MIGRATION_RUN_PLAN_STALE",
			"Applied migration history changed after this migration was previewed.",
		)
	var current_fingerprint := GDSQLSchemaFingerprint.compute(
		_catalog.get_database(plan.database_name),
	)
	if current_fingerprint.is_empty():
		return _error(
			result,
			&"GDSQL_MIGRATION_SCHEMA_FINGERPRINT_FAILED",
			"Could not fingerprint the current database schema.",
		)
	var previous_fingerprint := ledger.last_schema_fingerprint()
	if not previous_fingerprint.is_empty() \
			and previous_fingerprint != current_fingerprint:
		return _error(
			result,
			&"GDSQL_MIGRATION_SCHEMA_DRIFT",
			"The current database schema differs from its last applied migration.",
		)
	var backup_result := _recovery.create_backup(
		plan.database_name,
		plan.migration.migration_id,
	)
	result.diagnostics.merge(backup_result.diagnostics)
	if not result.is_successful():
		return result
	result.backup = backup_result.get_value() as GDSQLMigrationBackup
	result.backup_retained = true
	var applied := _catalog_administration.apply_change_plan(plan.change_plan)
	result.diagnostics.merge(applied.diagnostics)
	if not applied.is_successful():
		_recover(result)
		return result
	var resulting_fingerprint := GDSQLSchemaFingerprint.compute(
		_catalog.get_database(plan.database_name),
	)
	if resulting_fingerprint.is_empty():
		_error(
			result,
			&"GDSQL_MIGRATION_SCHEMA_FINGERPRINT_FAILED",
			"Could not fingerprint the migrated database schema.",
		)
		_recover(result)
		return result
	var record := GDSQLAppliedMigration.new(
		plan.migration.migration_id,
		plan.migration.checksum,
		int(Time.get_unix_time_from_system() * 1000.0),
		resulting_fingerprint,
	)
	var appended := _ledger.append(
		plan.database_name,
		record,
		plan.expected_ledger_revision,
	)
	result.diagnostics.merge(appended.diagnostics)
	if not appended.is_successful():
		_recover(result)
		return result
	result.complete(record)
	_discard_backup(result)
	return result


func _validate_plan(plan: GDSQLMigrationCatalogPlan) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if _catalog == null or _catalog_administration == null \
			or _ledger == null or _recovery == null:
		return _error(
			result,
			&"GDSQL_MIGRATION_RUN_DEPENDENCY_REQUIRED",
			"Migration execution requires catalog, ledger, and recovery services.",
		)
	if plan == null or plan.migration == null or plan.change_plan == null \
			or not plan.migration.is_valid() or plan.expected_ledger_revision < 0:
		return _error(
			result,
			&"GDSQL_MIGRATION_RUN_PLAN_INVALID",
			"Migration execution requires a valid catalog preview.",
		)
	if plan.database_name == &"" \
			or plan.database_name != plan.change_plan.database_name:
		return _error(
			result,
			&"GDSQL_MIGRATION_RUN_DATABASE_MISMATCH",
			"Migration and catalog plans must target the same database.",
		)
	if plan.migration.steps.size() != 1:
		return _error(
			result,
			&"GDSQL_MIGRATION_RUN_PLAN_INVALID",
			"Migration v1 execution requires exactly one table step.",
		)
	var step := plan.migration.steps[0]
	if step.table_name != plan.change_plan.table_name \
			or not _change_plan_matches_migration(plan):
		return _error(
			result,
			&"GDSQL_MIGRATION_RUN_PLAN_MISMATCH",
			"Catalog preview does not represent the authored migration.",
		)
	return result


func _change_plan_matches_migration(plan: GDSQLMigrationCatalogPlan) -> bool:
	var preview_step := GDSQLSchemaMigrationStep.new(
		plan.change_plan.table_name,
		plan.change_plan.alterations,
	)
	var preview_steps: Array[GDSQLSchemaMigrationStep] = [preview_step]
	var preview_definition := GDSQLMigrationDefinition.new(
		plan.migration.migration_id,
		plan.migration.description,
		preview_steps,
	)
	return preview_definition.checksum == plan.migration.checksum


func _recover(result: GDSQLMigrationRunResult) -> void:
	var restored := _recovery.restore(result.backup)
	if not restored.is_successful():
		result.diagnostics.merge(restored.diagnostics)
		return
	result.recovered = true
	_discard_backup(result)


func _discard_backup(result: GDSQLMigrationRunResult) -> void:
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
) -> GDSQLOperationResult:
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
