class_name GDSQLMigrationBaseline
extends RefCounted
## Durable evidence that a pre-existing schema adopted an authored history head.

var through_migration_id: String
var through_checksum: String
var history_checksum: String
var adopted_at_unix_ms: int
var schema_fingerprint: String


func _init(
		migration_id: String = "",
		migration_checksum: String = "",
		prefix_checksum: String = "",
		adopted_at: int = 0,
		adopted_schema_fingerprint: String = "",
) -> void:
	through_migration_id = migration_id
	through_checksum = migration_checksum
	history_checksum = prefix_checksum
	adopted_at_unix_ms = adopted_at
	schema_fingerprint = adopted_schema_fingerprint


func is_valid() -> bool:
	var head_is_valid := (
			through_migration_id.is_empty() and through_checksum.is_empty()
	) or (
			GDSQLMigrationDefinition.is_valid_id(through_migration_id) \
					and GDSQLMigrationChecksum.is_valid(through_checksum)
	)
	return head_is_valid and GDSQLMigrationHistoryChecksum.is_valid(history_checksum) \
			and adopted_at_unix_ms > 0 \
			and GDSQLSchemaFingerprint.is_valid(schema_fingerprint)
