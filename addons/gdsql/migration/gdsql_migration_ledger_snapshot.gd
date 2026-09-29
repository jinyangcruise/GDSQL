class_name GDSQLMigrationLedgerSnapshot
extends RefCounted
## Ordered applied migration records loaded from one database ledger.

var records: Array[GDSQLAppliedMigration] = []
var baseline: GDSQLMigrationBaseline


func _init(
		applied_records: Array[GDSQLAppliedMigration] = [],
		adopted_baseline: GDSQLMigrationBaseline = null,
) -> void:
	records = applied_records.duplicate()
	baseline = adopted_baseline


func find(migration_id: String) -> GDSQLAppliedMigration:
	for record in records:
		if record != null and record.migration_id == migration_id:
			return record
	return null


func last_id() -> String:
	if not records.is_empty():
		return records[-1].migration_id
	return baseline.through_migration_id if baseline != null else ""


func revision() -> int:
	return records.size() + (1 if baseline != null else 0)


func last_schema_fingerprint() -> String:
	if not records.is_empty():
		return records[-1].schema_fingerprint
	return baseline.schema_fingerprint if baseline != null else ""
