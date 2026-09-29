class_name GDSQLSchemaFingerprint
extends RefCounted
## Produces deterministic SHA-256 identity for one complete database schema.

const HEX_CHARACTERS := "0123456789abcdef"
const CanonicalValue = preload(
	"res://addons/gdsql/migration/gdsql_migration_canonical_value.gd"
)


static func compute(database: GDSQLDatabaseDefinition) -> String:
	if database == null or database.name == &"":
		return ""
	var tables: Array[GDSQLTableDefinition] = database.tables.duplicate()
	tables.sort_custom(
		func(left: GDSQLTableDefinition, right: GDSQLTableDefinition) -> bool:
			return String(left.name) < String(right.name),
	)
	var serialized_tables: Array = []
	for table in tables:
		serialized_tables.append(_serialize_table(table))
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if hashing.update(
		var_to_str([String(database.name), serialized_tables]).to_utf8_buffer(),
	) != OK:
		return ""
	return hashing.finish().hex_encode()


static func is_valid(value: String) -> bool:
	if value.length() != 64:
		return false
	for character in value.to_lower():
		if not HEX_CHARACTERS.contains(character):
			return false
	return true


static func _serialize_table(table: GDSQLTableDefinition) -> Array:
	if table == null:
		return []
	var columns: Array = []
	for column in table.columns:
		columns.append(_serialize_column(column))
	var indexes: Array[GDSQLIndexDefinition] = table.indexes.duplicate()
	indexes.sort_custom(
		func(left: GDSQLIndexDefinition, right: GDSQLIndexDefinition) -> bool:
			return String(left.name) < String(right.name),
	)
	var serialized_indexes: Array = []
	for index in indexes:
		serialized_indexes.append(
			[String(index.name), PackedStringArray(index.columns), index.unique],
		)
	var foreign_keys: Array[GDSQLForeignKeyDefinition] = table.foreign_keys.duplicate()
	foreign_keys.sort_custom(
		func(
				left: GDSQLForeignKeyDefinition,
				right: GDSQLForeignKeyDefinition,
		) -> bool:
			return String(left.name) < String(right.name),
	)
	var serialized_foreign_keys: Array = []
	for foreign_key in foreign_keys:
		serialized_foreign_keys.append(
			[
				String(foreign_key.name),
				String(foreign_key.column),
				String(foreign_key.referenced_table),
				String(foreign_key.referenced_column),
				foreign_key.on_delete,
				foreign_key.on_update,
			],
		)
	return [
		String(table.name),
		String(table.primary_key),
		columns,
		serialized_indexes,
		serialized_foreign_keys,
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
