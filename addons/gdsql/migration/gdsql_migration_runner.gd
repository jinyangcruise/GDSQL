class_name GDSQLMigrationRunner
extends RefCounted
## Applies one previewed migration with durable rollback and ledger evidence.

var _catalog: GDSQLCatalogService
var _catalog_administration: GDSQLCatalogAdministrationService
var _ledger: GDSQLMigrationLedger
var _recovery: GDSQLMigrationRecoveryStore
var _validator: GDSQLQueryValidator
var _query_planner: GDSQLQueryPlanner
var _executor: GDSQLQueryExecutor
var _execution_context: GDSQLExecutionContext


func _init(
		catalog: GDSQLCatalogService = null,
		catalog_administration: GDSQLCatalogAdministrationService = null,
		ledger: GDSQLMigrationLedger = null,
		recovery: GDSQLMigrationRecoveryStore = null,
		validator: GDSQLQueryValidator = null,
		query_planner: GDSQLQueryPlanner = null,
		executor: GDSQLQueryExecutor = null,
		execution_context: GDSQLExecutionContext = null,
) -> void:
	_catalog = catalog
	_catalog_administration = catalog_administration
	_ledger = ledger
	_recovery = recovery
	_validator = validator
	_query_planner = query_planner
	_executor = executor
	_execution_context = execution_context


func apply(plan: GDSQLMigrationStepPlan) -> GDSQLMigrationRunResult:
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
	var applied := _apply_steps(plan)
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


func _validate_plan(plan: GDSQLMigrationStepPlan) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if _catalog == null or _catalog_administration == null \
			or _ledger == null or _recovery == null:
		return _error(
			result,
			&"GDSQL_MIGRATION_RUN_DEPENDENCY_REQUIRED",
			"Migration execution requires catalog, ledger, and recovery services.",
		)
	if plan == null or plan.migration == null \
			or not plan.migration.is_valid() or plan.expected_ledger_revision < 0:
		return _error(
			result,
			&"GDSQL_MIGRATION_RUN_PLAN_INVALID",
			"Migration execution requires a valid catalog preview.",
		)
	if plan.database_name == &"":
		return _error(
			result,
			&"GDSQL_MIGRATION_RUN_DATABASE_MISMATCH",
			"Migration execution requires a target database.",
		)
	if plan.step_previews.size() != plan.migration.steps.size():
		return _error(
			result,
			&"GDSQL_MIGRATION_RUN_PLAN_MISMATCH",
			"Migration preview does not cover every authored step.",
		)
	for index in plan.migration.steps.size():
		var authored_step := plan.migration.steps[index]
		var preview := plan.step_previews[index]
		if preview == null or preview.step == null \
				or not GDSQLMigrationChecksum.steps_match(authored_step, preview.step):
			return _error(
				result,
				&"GDSQL_MIGRATION_RUN_PLAN_MISMATCH",
				"Migration preview step %d does not match its authored operation." \
						% (index + 1),
			)
		if authored_step is GDSQLDataMigrationStep:
			if not preview.is_data() or preview.affected_rows < 0 \
					or _validator == null or _query_planner == null \
					or _executor == null or _execution_context == null:
				return _error(
					result,
					&"GDSQL_MIGRATION_RUN_PLAN_MISMATCH",
					"Data preview does not represent its authored migration step.",
				)
			continue
		var schema_step := authored_step as GDSQLSchemaMigrationStep
		if schema_step == null or not preview.is_schema() \
				or plan.database_name != preview.change_plan.database_name \
				or schema_step.table_name != preview.change_plan.table_name \
				or not _step_kind_matches_plan(schema_step, preview.change_plan) \
				or not _change_plan_matches_step(schema_step, preview.change_plan):
			return _error(
				result,
				&"GDSQL_MIGRATION_RUN_PLAN_MISMATCH",
				"Catalog preview does not represent its authored migration step.",
			)
	return result


func _apply_steps(plan: GDSQLMigrationStepPlan) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	for preview in plan.step_previews:
		var applied: GDSQLOperationResult
		if preview.is_schema():
			applied = _catalog_administration.apply_change_plan(preview.change_plan)
		else:
			applied = _apply_data_step(
				plan.database_name,
				preview.step as GDSQLDataMigrationStep,
			)
		result.diagnostics.merge(applied.diagnostics)
		if not applied.is_successful():
			return result
		if preview.is_data():
			var execution := applied as GDSQLQueryExecutionResult
			var actual_rows := int(
				execution.statistics.get("affected_rows", -1) if execution != null else -1,
			)
			if actual_rows != preview.affected_rows:
				return _error(
					result,
					&"GDSQL_MIGRATION_DATA_PREVIEW_STALE",
					(
						"Data step for table '%s' affected %d row(s), but its preview "
						+ "reported %d. Migration application cannot continue."
					) % [preview.step.table_name, actual_rows, preview.affected_rows],
				)
	return result


func _apply_data_step(
		database_name: StringName,
		data_step: GDSQLDataMigrationStep,
) -> GDSQLOperationResult:
	var validation := _validator.validate(data_step.to_query(database_name))
	if not validation.is_valid():
		var invalid := GDSQLOperationResult.new()
		invalid.diagnostics.merge(validation.diagnostics)
		return invalid
	var planning := _query_planner.create_plan(validation.bound_query)
	if not planning.is_successful() or planning.plan == null:
		var unplanned := GDSQLOperationResult.new()
		unplanned.diagnostics.merge(planning.diagnostics)
		return unplanned
	return _executor.execute(planning.plan, _execution_context)


func _change_plan_matches_step(
		authored_step: GDSQLSchemaMigrationStep,
		change_plan: GDSQLCatalogChangePlan,
) -> bool:
	var preview_step: GDSQLSchemaMigrationStep
	if change_plan.kind == GDSQLCatalogChangePlan.Kind.CREATE_TABLE:
		preview_step = GDSQLSchemaMigrationStep.create_table(
			change_plan.table_definition,
		)
	elif change_plan.kind == GDSQLCatalogChangePlan.Kind.RENAME_TABLE:
		preview_step = GDSQLSchemaMigrationStep.rename_table(
			change_plan.table_name,
			change_plan.new_table_name,
		)
	elif change_plan.kind == GDSQLCatalogChangePlan.Kind.DROP_TABLE:
		preview_step = GDSQLSchemaMigrationStep.drop_table(
			change_plan.table_name,
		)
	else:
		preview_step = GDSQLSchemaMigrationStep.new(
			change_plan.table_name,
			change_plan.alterations,
		)
	return GDSQLMigrationChecksum.steps_match(authored_step, preview_step)


func _step_kind_matches_plan(
		step: GDSQLSchemaMigrationStep,
		change_plan: GDSQLCatalogChangePlan,
) -> bool:
	return (
			step.kind == GDSQLSchemaMigrationStep.Kind.ALTER_TABLE \
					and change_plan.kind == GDSQLCatalogChangePlan.Kind.ALTER_TABLE
	) or (
			step.kind == GDSQLSchemaMigrationStep.Kind.CREATE_TABLE \
					and change_plan.kind == GDSQLCatalogChangePlan.Kind.CREATE_TABLE
	) or (
			step.kind == GDSQLSchemaMigrationStep.Kind.RENAME_TABLE \
					and change_plan.kind == GDSQLCatalogChangePlan.Kind.RENAME_TABLE
	) or (
			step.kind == GDSQLSchemaMigrationStep.Kind.DROP_TABLE \
					and change_plan.kind == GDSQLCatalogChangePlan.Kind.DROP_TABLE
	)


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
