class_name GDSQLMigrationRunResult
extends GDSQLOperationResult
## Reports migration application and any automatic recovery outcome.

var backup: GDSQLMigrationBackup
var applied_migration: GDSQLAppliedMigration
var recovered: bool
var backup_retained: bool


func complete(record: GDSQLAppliedMigration) -> void:
	applied_migration = record
	value = record
