class_name GDSQLAppliedMigration
extends RefCounted
## Durable evidence that one exact migration reached one database schema.

var migration_id: String
var checksum: String
var applied_at_unix_ms: int
var schema_fingerprint: String


func _init(
		stable_id: String = "",
		migration_checksum: String = "",
		applied_at: int = 0,
		resulting_schema_fingerprint: String = "",
) -> void:
	migration_id = stable_id
	checksum = migration_checksum
	applied_at_unix_ms = applied_at
	schema_fingerprint = resulting_schema_fingerprint


func is_valid() -> bool:
	return GDSQLMigrationDefinition.is_valid_id(migration_id) \
			and GDSQLMigrationChecksum.is_valid(checksum) \
			and applied_at_unix_ms > 0 \
			and GDSQLSchemaFingerprint.is_valid(schema_fingerprint)
