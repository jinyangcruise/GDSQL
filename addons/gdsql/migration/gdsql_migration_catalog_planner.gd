class_name GDSQLMigrationCatalogPlanner
extends RefCounted
## Composes the next history entry with catalog validation without mutating it.

var _catalog_administration: GDSQLCatalogAdministrationService


func _init(
		catalog_administration: GDSQLCatalogAdministrationService = null,
) -> void:
	_catalog_administration = catalog_administration


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
	if migration.steps.size() != 1:
		return _error(
			result,
			&"GDSQL_MIGRATION_MULTI_STEP_PREVIEW_UNSUPPORTED",
			(
					"Migration '%s' has %d table steps; the initial dry-run boundary "
					+ "requires one table step per migration."
			) % [migration.migration_id, migration.steps.size()],
		)
	var step := migration.steps[0]
	var preview := _catalog_administration.preview_alter_table(
		database_name,
		step.table_name,
		step.alterations,
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
	result.value = GDSQLMigrationCatalogPlan.new(
		database_name,
		migration,
		change_plan,
		history_plan.ledger_revision,
	)
	return result


func _error(
		result: GDSQLOperationResult,
		code: StringName,
		message: String,
) -> GDSQLOperationResult:
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
