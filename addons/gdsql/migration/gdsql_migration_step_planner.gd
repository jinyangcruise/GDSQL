class_name GDSQLMigrationStepPlanner
extends RefCounted
## Composes the next history entry with catalog validation without mutating it.

var _catalog_administration: GDSQLCatalogAdministrationService
var _validator: GDSQLQueryValidator
var _query_planner: GDSQLQueryPlanner
var _executor: GDSQLQueryExecutor
var _execution_context: GDSQLExecutionContext


func _init(
		catalog_administration: GDSQLCatalogAdministrationService = null,
		validator: GDSQLQueryValidator = null,
		query_planner: GDSQLQueryPlanner = null,
		executor: GDSQLQueryExecutor = null,
		execution_context: GDSQLExecutionContext = null,
) -> void:
	_catalog_administration = catalog_administration
	_validator = validator
	_query_planner = query_planner
	_executor = executor
	_execution_context = execution_context


func preview_next(
		database_name: StringName,
		history_plan: GDSQLMigrationPlan,
) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if _catalog_administration == null:
		return _error(
			result,
			&"GDSQL_MIGRATION_CATALOG_REQUIRED",
			"Migration preview requires catalog administration.",
		)
	if database_name == &"":
		return _error(
			result,
			&"GDSQL_MIGRATION_DATABASE_REQUIRED",
			"Migration preview requires a target database.",
		)
	if history_plan == null:
		return _error(
			result,
			&"GDSQL_MIGRATION_PLAN_REQUIRED",
			"Migration preview requires a validated history plan.",
		)
	if history_plan.is_up_to_date():
		return _error(
			result,
			&"GDSQL_MIGRATION_NOT_PENDING",
			"The migration history is already up to date.",
		)
	var migration := history_plan.pending[0]
	if migration.steps.size() > 1:
		return _preview_data_updates(
			result,
			database_name,
			migration,
			history_plan.ledger_revision,
		)
	var step := migration.steps[0]
	if step is GDSQLDataMigrationStep:
		var data_steps: Array[GDSQLDataMigrationStep] = [step]
		return _preview_data_updates(
			result,
			database_name,
			migration,
			history_plan.ledger_revision,
			data_steps,
		)
	var schema_step := step as GDSQLSchemaMigrationStep
	if schema_step == null:
		return _error(
			result,
			&"GDSQL_MIGRATION_STEP_UNSUPPORTED",
			"Migration uses an unsupported step type.",
		)
	var preview: GDSQLOperationResult
	match schema_step.kind:
		GDSQLSchemaMigrationStep.Kind.ALTER_TABLE:
			preview = _catalog_administration.preview_alter_table(
				database_name,
				schema_step.table_name,
				schema_step.alterations,
			)
		GDSQLSchemaMigrationStep.Kind.CREATE_TABLE:
			preview = _catalog_administration.preview_create_table(
				database_name,
				schema_step.table_definition,
			)
		GDSQLSchemaMigrationStep.Kind.RENAME_TABLE:
			preview = _catalog_administration.preview_rename_table(
				database_name,
				schema_step.table_name,
				schema_step.new_table_name,
			)
		GDSQLSchemaMigrationStep.Kind.DROP_TABLE:
			preview = _catalog_administration.preview_drop_table(
				database_name,
				schema_step.table_name,
			)
		_:
			return _error(
				result,
				&"GDSQL_MIGRATION_STEP_UNSUPPORTED",
				"Migration uses an unsupported catalog lifecycle operation.",
			)
	result.diagnostics.merge(preview.diagnostics)
	if not preview.is_successful():
		return result
	var change_plan := preview.get_value() as GDSQLCatalogChangePlan
	if change_plan == null:
		return _error(
			result,
			&"GDSQL_MIGRATION_CATALOG_PLAN_MISSING",
			"Catalog validation did not produce a migration change plan.",
		)
	result.value = GDSQLMigrationStepPlan.new(
		database_name,
		migration,
		change_plan,
		history_plan.ledger_revision,
	)
	return result


func _preview_data_updates(
		result: GDSQLOperationResult,
		database_name: StringName,
		migration: GDSQLMigrationDefinition,
		ledger_revision: int,
		known_steps: Array[GDSQLDataMigrationStep] = [],
) -> GDSQLOperationResult:
	var steps: Array[GDSQLDataMigrationStep] = []
	if not known_steps.is_empty():
		steps.assign(known_steps)
	else:
		var target_tables: Dictionary[StringName, bool] = {}
		for migration_step in migration.steps:
			var data_step := migration_step as GDSQLDataMigrationStep
			if data_step == null:
				return _error(
					result,
					&"GDSQL_MIGRATION_MULTI_STEP_PREVIEW_UNSUPPORTED",
					(
						"Migration '%s' mixes schema and data steps or contains "
						+ "multiple schema steps. "
						+ "Dependent schema batches require catalog simulation."
					) % migration.migration_id,
				)
			if target_tables.has(data_step.table_name):
				return _error(
					result,
					&"GDSQL_MIGRATION_DATA_TABLE_REPEATED",
					(
						"Multi-table data migration '%s' targets table '%s' more than once. "
						+ "Combine those updates so preview counts remain stable."
					) % [migration.migration_id, data_step.table_name],
				)
			target_tables[data_step.table_name] = true
			steps.append(data_step)
	if _validator == null or _query_planner == null or _executor == null \
			or _execution_context == null:
		return _error(
			result,
			&"GDSQL_MIGRATION_DATA_PIPELINE_REQUIRED",
			"Data migration preview requires the canonical query pipeline.",
		)
	var row_counts: Array[int] = []
	for step in steps:
		var counted := _preview_data_update_count(database_name, step)
		result.diagnostics.merge(counted.diagnostics)
		if not counted.is_successful():
			return result
		row_counts.append(int(counted.get_value()))
	result.value = GDSQLMigrationStepPlan.for_data_updates(
		database_name,
		migration,
		steps,
		row_counts,
		ledger_revision,
	)
	return result


func _preview_data_update_count(
		database_name: StringName,
		step: GDSQLDataMigrationStep,
) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	var prepared := _prepare(step.to_query(database_name))
	result.diagnostics.merge(prepared.diagnostics)
	if not prepared.is_successful():
		return result
	var count_query := GDSQLQuery.new(database_name).table(step.table_name).select() \
			.count(null, &"row_count")
	if step.predicate != null:
		count_query.where(step.predicate)
	var counted := _execute(count_query.build())
	result.diagnostics.merge(counted.diagnostics)
	if not counted.is_successful() or counted.rows == null \
			or counted.rows.rows.size() != 1:
		return _error(
			result,
			&"GDSQL_MIGRATION_DATA_COUNT_FAILED",
			"Data migration preview could not count the affected rows.",
		)
	var row_count := int(counted.rows.rows[0].get_value(&"row_count"))
	result.value = row_count
	return result


func _prepare(query: GDSQLQuerySpec) -> GDSQLQueryPlanningResult:
	var validation := _validator.validate(query)
	if not validation.is_valid():
		var result := GDSQLQueryPlanningResult.new()
		result.diagnostics.merge(validation.diagnostics)
		return result
	return _query_planner.create_plan(validation.bound_query)


func _execute(query: GDSQLQuerySpec) -> GDSQLQueryExecutionResult:
	var planning := _prepare(query)
	if not planning.is_successful() or planning.plan == null:
		var result := GDSQLQueryExecutionResult.new()
		result.diagnostics.merge(planning.diagnostics)
		return result
	return _executor.execute(planning.plan, _execution_context)


func _error(
		result: GDSQLOperationResult,
		code: StringName,
		message: String,
) -> GDSQLOperationResult:
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
