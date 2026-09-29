class_name GDSQLMigrationPlan
extends RefCounted
## Dry-run history result before catalog-specific schema previews are built.

var pending: Array[GDSQLMigrationDefinition] = []
var applied_count: int
var destructive: bool


func _init(
		pending_migrations: Array[GDSQLMigrationDefinition] = [],
		current_applied_count: int = 0,
) -> void:
	pending = pending_migrations.duplicate()
	applied_count = current_applied_count
	for migration in pending:
		destructive = destructive or migration.is_destructive()


func is_up_to_date() -> bool:
	return pending.is_empty()
