@abstract
class_name GDSQLMigrationRecoveryStore
extends RefCounted
## Durable backup boundary used before catalog migration execution.

@abstract
func create_backup(
		database_name: StringName,
		migration_id: String,
) -> GDSQLOperationResult


@abstract
func load_backup(
		database_name: StringName,
		migration_id: String,
) -> GDSQLOperationResult


@abstract
func restore(backup: GDSQLMigrationBackup) -> GDSQLOperationResult


@abstract
func discard(
		database_name: StringName,
		migration_id: String,
) -> GDSQLOperationResult
