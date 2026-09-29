class_name GDSQLAppliedMigration
extends RefCounted
## Durable evidence that one exact migration reached one database schema.

const HEX_CHARACTERS := "0123456789abcdef"

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
			and _is_sha256(checksum) \
			and applied_at_unix_ms > 0 \
			and not schema_fingerprint.is_empty()


func _is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for character in value.to_lower():
		if not HEX_CHARACTERS.contains(character):
			return false
	return true
