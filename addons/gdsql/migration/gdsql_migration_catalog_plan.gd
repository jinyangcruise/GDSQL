class_name GDSQLMigrationCatalogPlan
extends RefCounted
## Stale-safe catalog preview for the next pending migration.

var database_name: StringName
var migration: GDSQLMigrationDefinition
var change_plan: GDSQLCatalogChangePlan
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


func affected_rows() -> int:
	return change_plan.affected_rows if change_plan != null else 0


func requires_confirmation() -> bool:
	return change_plan != null and change_plan.requires_confirmation()


func summaries() -> Array[String]:
	return change_plan.summaries.duplicate() if change_plan != null else []
