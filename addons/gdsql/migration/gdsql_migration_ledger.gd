@abstract
class_name GDSQLMigrationLedger
extends RefCounted
## Persistence boundary for ordered, append-only applied migration history.

@abstract
func load(database_name: StringName) -> GDSQLOperationResult


@abstract
func append(
		database_name: StringName,
		record: GDSQLAppliedMigration,
		expected_record_count: int,
) -> GDSQLOperationResult
