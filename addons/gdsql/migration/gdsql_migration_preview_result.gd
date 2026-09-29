class_name GDSQLMigrationPreviewResult
extends GDSQLOperationResult
## Reports validated history and the next catalog plan without mutating data.

var history_plan: GDSQLMigrationPlan
var next_plan: GDSQLMigrationCatalogPlan


func complete(
		validated_history: GDSQLMigrationPlan,
		catalog_plan: GDSQLMigrationCatalogPlan = null,
) -> void:
	history_plan = validated_history
	next_plan = catalog_plan
	value = catalog_plan if catalog_plan != null else validated_history


func is_up_to_date() -> bool:
	return history_plan != null and history_plan.is_up_to_date()


func requires_confirmation() -> bool:
	return next_plan != null and next_plan.requires_confirmation()
