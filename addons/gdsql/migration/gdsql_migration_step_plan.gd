class_name GDSQLMigrationStepPlan
extends RefCounted
## Stale-safe preview for the next pending schema or data migration.

var database_name: StringName
var migration: GDSQLMigrationDefinition
var change_plan: GDSQLCatalogChangePlan
var data_steps: Array[GDSQLDataMigrationStep] = []
var data_step_affected_rows: Array[int] = []
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


static func for_data_updates(
		target_database: StringName,
		pending_migration: GDSQLMigrationDefinition,
		steps: Array[GDSQLDataMigrationStep],
		row_counts: Array[int],
		ledger_revision: int,
) -> GDSQLMigrationStepPlan:
	var plan := GDSQLMigrationStepPlan.new(
		target_database,
		pending_migration,
		null,
		ledger_revision,
	)
	plan.data_steps.assign(steps)
	plan.data_step_affected_rows.assign(row_counts)
	return plan


func is_data_update() -> bool:
	return not data_steps.is_empty()


func affected_rows() -> int:
	if is_data_update():
		var total := 0
		for row_count in data_step_affected_rows:
			total += row_count
		return total
	return change_plan.affected_rows if change_plan != null else 0


func requires_confirmation() -> bool:
	return is_data_update() or change_plan != null and change_plan.requires_confirmation()


func summaries() -> Array[String]:
	if is_data_update():
		var result: Array[String] = []
		for index in data_steps.size():
			result.append(
				"Update %d row(s) in table '%s'." % [
					data_step_affected_rows[index],
					data_steps[index].table_name,
				],
			)
		return result
	return change_plan.summaries.duplicate() if change_plan != null else []
