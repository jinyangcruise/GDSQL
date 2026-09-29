class_name GDSQLMigrationChecksum
extends RefCounted
## Produces a deterministic SHA-256 identity for one authored migration.

const CanonicalValue = preload(
	"res://addons/gdsql/migration/gdsql_migration_canonical_value.gd"
)
const HEX_CHARACTERS := "0123456789abcdef"


static func compute(migration: GDSQLMigrationDefinition) -> String:
	if migration == null:
		return ""
	var serialized_steps: Array = []
	for step in migration.steps:
		serialized_steps.append(_serialize_step(step))
	var payload := var_to_str(
		[
			migration.migration_id,
			migration.description,
			serialized_steps,
		],
	).to_utf8_buffer()
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK \
			or hashing.update(payload) != OK:
		return ""
	return hashing.finish().hex_encode()


static func is_valid(value: String) -> bool:
	if value.length() != 64:
		return false
	for character in value.to_lower():
		if not HEX_CHARACTERS.contains(character):
			return false
	return true


static func _serialize_step(step: GDSQLSchemaMigrationStep) -> Array:
	if step == null:
		return []
	var alterations: Array = []
	for alteration in step.alterations:
		alterations.append(_serialize_alteration(alteration))
	return [String(step.table_name), alterations]


static func _serialize_alteration(alteration: GDSQLTableAlteration) -> Array:
	if alteration == null:
		return []
	return [
		alteration.kind,
		_serialize_column(alteration.column),
		String(alteration.column_name),
		String(alteration.new_column_name),
		_serialize_index(alteration.index),
		String(alteration.index_name),
		_serialize_foreign_key(alteration.foreign_key),
		String(alteration.foreign_key_name),
		CanonicalValue.serialize(alteration.value),
		alteration.enabled,
		alteration.generation,
		alteration.resource_ownership,
		PackedStringArray(alteration.column_names),
	]


static func _serialize_column(column: GDSQLColumnDefinition) -> Array:
	if column == null:
		return []
	return [
		String(column.name),
		column.data_type,
		column.nullable,
		column.unique,
		column.auto_increment,
		column.generation,
		column.resource_ownership,
		column.has_default(),
		CanonicalValue.serialize(column.get_default_value()) if column.has_default() else null,
		String(column.resource_type.resource_class) if column.resource_type != null else "",
		column.resource_type.script_path if column.resource_type != null else "",
	]


static func _serialize_index(index: GDSQLIndexDefinition) -> Array:
	if index == null:
		return []
	return [String(index.name), PackedStringArray(index.columns), index.unique]


static func _serialize_foreign_key(foreign_key: GDSQLForeignKeyDefinition) -> Array:
	if foreign_key == null:
		return []
	return [
		String(foreign_key.name),
		String(foreign_key.column),
		String(foreign_key.referenced_table),
		String(foreign_key.referenced_column),
		foreign_key.on_delete,
		foreign_key.on_update,
	]
