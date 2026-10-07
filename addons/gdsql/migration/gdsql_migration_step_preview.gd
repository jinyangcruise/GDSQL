class_name GDSQLMigrationStepPreview
extends RefCounted
## One authored migration step paired with its non-mutating preview evidence.

var step: GDSQLMigrationStep
var change_plan: GDSQLCatalogChangePlan
var affected_rows: int


func _init(
		authored_step: GDSQLMigrationStep = null,
		catalog_plan: GDSQLCatalogChangePlan = null,
		row_count: int = 0,
) -> void:
	step = authored_step
	change_plan = catalog_plan
	affected_rows = row_count


static func for_schema(
		authored_step: GDSQLSchemaMigrationStep,
		catalog_plan: GDSQLCatalogChangePlan,
) -> GDSQLMigrationStepPreview:
	return GDSQLMigrationStepPreview.new(
		authored_step,
		catalog_plan,
		catalog_plan.affected_rows if catalog_plan != null else 0,
	)


static func for_data(
		authored_step: GDSQLDataMigrationStep,
		row_count: int,
) -> GDSQLMigrationStepPreview:
	return GDSQLMigrationStepPreview.new(authored_step, null, row_count)


func is_schema() -> bool:
	return step is GDSQLSchemaMigrationStep and change_plan != null


func is_data() -> bool:
	return step is GDSQLDataMigrationStep and change_plan == null


func requires_confirmation() -> bool:
	return is_data() or change_plan != null and change_plan.requires_confirmation()


func summaries() -> Array[String]:
	if is_data():
		return [
			"Update %d row(s) in table '%s'." % [affected_rows, step.table_name],
		]
	return change_plan.summaries.duplicate() if change_plan != null else []
