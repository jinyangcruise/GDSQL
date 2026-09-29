class_name GDSQLMigrationSchemaState
extends RefCounted
## Project-owned evidence that one migration-history prefix produces a schema.

var migration_stream: StringName
var database_name: StringName
var history_count: int
var migration_head_id: String
var history_checksum: String
var schema_fingerprint: String


func _init(
		stream: StringName = &"",
		logical_database_name: StringName = &"",
		authored_history_count: int = 0,
		head_id: String = "",
		authored_history_checksum: String = "",
		expected_schema_fingerprint: String = "",
) -> void:
	migration_stream = stream
	database_name = logical_database_name
	history_count = authored_history_count
	migration_head_id = head_id
	history_checksum = authored_history_checksum
	schema_fingerprint = expected_schema_fingerprint


static func from_history(
		stream: StringName,
		logical_database_name: StringName,
		history: Array[GDSQLMigrationDefinition],
		expected_schema_fingerprint: String,
		through_count: int = -1,
) -> GDSQLMigrationSchemaState:
	var count := history.size() if through_count < 0 else through_count
	var head_id := history[count - 1].migration_id if count > 0 and count <= history.size() else ""
	return GDSQLMigrationSchemaState.new(
		stream,
		logical_database_name,
		count,
		head_id,
		GDSQLMigrationHistoryChecksum.compute(history, count),
		expected_schema_fingerprint,
	)


func is_valid() -> bool:
	if migration_stream == &"" or not String(migration_stream).is_valid_identifier() \
			or database_name == &"" or not String(database_name).is_valid_identifier() \
			or history_count < 0 \
			or not GDSQLMigrationHistoryChecksum.is_valid(history_checksum) \
			or not GDSQLSchemaFingerprint.is_valid(schema_fingerprint):
		return false
	if history_count == 0:
		return migration_head_id.is_empty()
	return GDSQLMigrationDefinition.is_valid_id(migration_head_id)


func matches_history_prefix(history: Array[GDSQLMigrationDefinition]) -> bool:
	if not is_valid() or history_count > history.size():
		return false
	if history_count > 0 and history[history_count - 1].migration_id != migration_head_id:
		return false
	return GDSQLMigrationHistoryChecksum.compute(history, history_count) == history_checksum
