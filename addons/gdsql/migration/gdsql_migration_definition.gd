class_name GDSQLMigrationDefinition
extends RefCounted
## Immutable-by-convention project-authored forward schema history entry.
##
## The stored checksum detects any alteration after the definition is created.

const MAX_ID_LENGTH := 128
const ALLOWED_ID_CHARACTERS := \
		"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-."

var migration_id: String
var description: String
var steps: Array[GDSQLMigrationStep] = []
var checksum: String


func _init(
		stable_id: String = "",
		summary: String = "",
		migration_steps: Array = [],
) -> void:
	migration_id = stable_id
	description = summary
	for step in migration_steps:
		if step is GDSQLMigrationStep:
			steps.append(step)
	checksum = GDSQLMigrationChecksum.compute(self)


func is_valid() -> bool:
	if not is_valid_id(migration_id) or description.strip_edges().is_empty() \
			or steps.is_empty() or checksum.is_empty():
		return false
	for step in steps:
		if step == null or not step.is_valid():
			return false
	return has_valid_checksum()


func has_valid_checksum() -> bool:
	return not checksum.is_empty() and checksum == GDSQLMigrationChecksum.compute(self)


func is_destructive() -> bool:
	for step in steps:
		if step != null and step.is_destructive():
			return true
	return false


static func is_valid_id(value: String) -> bool:
	if value.is_empty() or value.length() > MAX_ID_LENGTH:
		return false
	for character in value:
		if not ALLOWED_ID_CHARACTERS.contains(character):
			return false
	return true
