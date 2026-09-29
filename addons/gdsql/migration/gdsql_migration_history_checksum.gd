class_name GDSQLMigrationHistoryChecksum
extends RefCounted
## Produces deterministic evidence for an authored migration-history prefix.

static func compute(
		history: Array[GDSQLMigrationDefinition],
		through_count: int,
) -> String:
	if through_count < 0 or through_count > history.size():
		return ""
	var prefix: Array = []
	for index in through_count:
		var migration := history[index]
		if migration == null or not migration.is_valid():
			return ""
		prefix.append([migration.migration_id, migration.checksum])
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK \
			or hashing.update(var_to_str(prefix).to_utf8_buffer()) != OK:
		return ""
	return hashing.finish().hex_encode()


static func is_valid(value: String) -> bool:
	return GDSQLMigrationChecksum.is_valid(value)
