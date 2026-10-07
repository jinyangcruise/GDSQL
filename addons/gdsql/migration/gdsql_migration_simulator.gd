@abstract
class_name GDSQLMigrationSimulator
extends RefCounted
## Previews an ordered migration against isolated state without mutating source data.

@abstract
func preview(
		database_name: StringName,
		migration: GDSQLMigrationDefinition,
		ledger_revision: int,
) -> GDSQLOperationResult
