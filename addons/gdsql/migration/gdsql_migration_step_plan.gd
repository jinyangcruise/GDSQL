class_name GDSQLMigrationStepPlan
extends RefCounted
## Stale-safe preview for the next pending schema or data migration.

var database_name: StringName
var migration: GDSQLMigrationDefinition
var change_plan: GDSQLCatalogChangePlan
var data_step: GDSQLDataMigrationStep
var data_affected_rows: int
var expected_ledger_revision: int


func _init(
		target_database: StringName = &"",
		pending_migration: GDSQLMigrationDefinition = null,
		catalog_change_plan: GDSQLCatalogChangePlan = null,
		ledger_revision: int = 0,
) -> void:
	database_name = target_database
	migration = pending_migration
	change_plan = catalog_change_plan
	expected_ledger_revision = ledger_revision


static func for_data_update(
		target_database: StringName,
		pending_migration: GDSQLMigrationDefinition,
		step: GDSQLDataMigrationStep,
		row_count: int,
		ledger_revision: int,
) -> GDSQLMigrationStepPlan:
	var plan := GDSQLMigrationStepPlan.new(
		target_database,
		pending_migration,
		null,
		ledger_revision,
	)
	plan.data_step = step
	plan.data_affected_rows = row_count
	return plan


func is_data_update() -> bool:
	return data_step != null


func affected_rows() -> int:
	return data_affected_rows if is_data_update() \
	else change_plan.affected_rows if change_plan != null else 0


func requires_confirmation() -> bool:
	return is_data_update() or change_plan != null and change_plan.requires_confirmation()


func summaries() -> Array[String]:
	if is_data_update():
		return [
			"Update %d row(s) in table '%s'." \
					% [data_affected_rows, data_step.table_name],
		]
	return change_plan.summaries.duplicate() if change_plan != null else []
