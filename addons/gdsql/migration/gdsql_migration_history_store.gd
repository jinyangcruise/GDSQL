@abstract
class_name GDSQLMigrationHistoryStore
extends RefCounted
## Project-owned append-only source history, separate from applied ledgers.

@abstract
func load(migration_stream: StringName) -> GDSQLOperationResult


@abstract
func append(
		migration_stream: StringName,
		migration: GDSQLMigrationDefinition,
		expected_definition_count: int,
) -> GDSQLOperationResult
