class_name GDSQLMigrationPreviewResult
extends GDSQLOperationResult
## Reports validated history and the next typed step plan without mutation.

var history_plan: GDSQLMigrationPlan
var next_plan: GDSQLMigrationStepPlan


func complete(
		validated_history: GDSQLMigrationPlan,
		step_plan: GDSQLMigrationStepPlan = null,
) -> void:
	history_plan = validated_history
	next_plan = step_plan
	value = step_plan if step_plan != null else validated_history


func is_up_to_date() -> bool:
	return history_plan != null and history_plan.is_up_to_date()


func requires_confirmation() -> bool:
	return next_plan != null and next_plan.requires_confirmation()
