class_name GDSQLMigrationStartupResult
extends GDSQLOperationResult
## Reports one durable registration's migration work before runtime opening.

var migration_configured: bool
var target_history_count: int
var baseline_adopted: bool
var recovered_migration_ids := PackedStringArray()
var applied_migration_ids := PackedStringArray()


func complete(database: GDSQLDatabase, configured: bool, target_count: int) -> void:
	migration_configured = configured
	target_history_count = target_count
	value = database
