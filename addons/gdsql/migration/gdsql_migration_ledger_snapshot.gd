class_name GDSQLMigrationLedgerSnapshot
extends RefCounted
## Ordered applied migration records loaded from one database ledger.

var records: Array[GDSQLAppliedMigration] = []


func _init(applied_records: Array[GDSQLAppliedMigration] = []) -> void:
	records = applied_records.duplicate()


func find(migration_id: String) -> GDSQLAppliedMigration:
	for record in records:
		if record != null and record.migration_id == migration_id:
			return record
	return null


func last_id() -> String:
	return records[-1].migration_id if not records.is_empty() else ""
