class_name GDSQLMigrationStepPlan
extends RefCounted
## Stale-safe ordered preview for the next pending migration.

var database_name: StringName
var migration: GDSQLMigrationDefinition
var change_plan: GDSQLCatalogChangePlan
var step_previews: Array[GDSQLMigrationStepPreview] = []
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
	if pending_migration != null and catalog_change_plan != null \
			and pending_migration.steps.size() == 1 \
			and pending_migration.steps[0] is GDSQLSchemaMigrationStep:
		step_previews.append(
			GDSQLMigrationStepPreview.for_schema(
				pending_migration.steps[0] as GDSQLSchemaMigrationStep,
				catalog_change_plan,
			),
		)


static func for_steps(
		target_database: StringName,
		pending_migration: GDSQLMigrationDefinition,
		previews: Array[GDSQLMigrationStepPreview],
		ledger_revision: int,
) -> GDSQLMigrationStepPlan:
	var plan := GDSQLMigrationStepPlan.new(
		target_database,
		pending_migration,
		null,
		ledger_revision,
	)
	plan.step_previews.assign(previews)
	if previews.size() == 1 and previews[0].is_schema():
		plan.change_plan = previews[0].change_plan
	for preview in previews:
		if preview.is_data():
			plan.data_steps.append(preview.step as GDSQLDataMigrationStep)
			plan.data_step_affected_rows.append(preview.affected_rows)
	return plan


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
	for index in steps.size():
		plan.step_previews.append(
			GDSQLMigrationStepPreview.for_data(steps[index], row_counts[index]),
		)
	return plan


func is_data_update() -> bool:
	return not step_previews.is_empty() and data_steps.size() == step_previews.size()


func affected_rows() -> int:
	if not step_previews.is_empty():
		var total := 0
		for preview in step_previews:
			total += preview.affected_rows
		return total
	return change_plan.affected_rows if change_plan != null else 0


func requires_confirmation() -> bool:
	if not step_previews.is_empty():
		for preview in step_previews:
			if preview.requires_confirmation():
				return true
		return false
	return change_plan != null and change_plan.requires_confirmation()


func summaries() -> Array[String]:
	if not step_previews.is_empty():
		var result: Array[String] = []
		for preview in step_previews:
			result.append_array(preview.summaries())
		return result
	return change_plan.summaries.duplicate() if change_plan != null else []
