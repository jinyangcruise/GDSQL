class_name GDSQLMigrationRecoveryResult
extends GDSQLOperationResult
## Reports how a durable backup left by an interrupted migration was resolved.

enum Status {
	RESTORED,
	COMMITTED_BACKUP_DISCARDED,
}

var status: Status
var backup: GDSQLMigrationBackup
var backup_retained: bool


func complete(
		recovery_status: Status,
		recovered_backup: GDSQLMigrationBackup,
) -> void:
	status = recovery_status
	backup = recovered_backup
	value = recovered_backup


func restored_database() -> bool:
	return status == Status.RESTORED
