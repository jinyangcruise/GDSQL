@abstract
class_name GDSQLMigrationSchemaStateStore
extends RefCounted
## Persists trusted project-owned schema evidence by migration stream.

@abstract
func load(migration_stream: StringName) -> GDSQLOperationResult


@abstract
func save(
		state: GDSQLMigrationSchemaState,
		expected_previous_history_checksum: String,
) -> GDSQLOperationResult
