class_name GDSQLMigrationBackup
extends RefCounted
## Durable identity and integrity evidence for one pre-migration snapshot.

const HEX_CHARACTERS := "0123456789abcdef"

var database_name: StringName
var migration_id: String
var snapshot_fingerprint: String
var created_at_unix_ms: int


func _init(
		target_database: StringName = &"",
		target_migration_id: String = "",
		fingerprint: String = "",
		created_at: int = 0,
) -> void:
	database_name = target_database
	migration_id = target_migration_id
	snapshot_fingerprint = fingerprint
	created_at_unix_ms = created_at


func is_valid() -> bool:
	return database_name != &"" and String(database_name).is_valid_identifier() \
			and GDSQLMigrationDefinition.is_valid_id(migration_id) \
			and _is_sha256(snapshot_fingerprint) and created_at_unix_ms > 0


func _is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for character in value.to_lower():
		if not HEX_CHARACTERS.contains(character):
			return false
	return true
