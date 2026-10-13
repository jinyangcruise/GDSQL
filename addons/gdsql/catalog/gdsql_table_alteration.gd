class_name GDSQLTableAlteration
extends RefCounted
## Describes one typed, storage-independent table schema change.
##
## Column type replacement is expressed as add, data migration, and drop so
## conversion and destructive effects remain explicit.

enum Kind {
	ADD_COLUMN,
	RENAME_COLUMN,
	DROP_COLUMN,
	ADD_INDEX,
	DROP_INDEX,
	ADD_FOREIGN_KEY,
	DROP_FOREIGN_KEY,
	SET_COLUMN_DEFAULT,
	CLEAR_COLUMN_DEFAULT,
	SET_COLUMN_NULLABLE,
	SET_COLUMN_UNIQUE,
	SET_COLUMN_AUTO_INCREMENT,
	SET_COLUMN_GENERATION,
	SET_RESOURCE_OWNERSHIP,
	REORDER_COLUMNS,
}

var kind: Kind
var column: GDSQLColumnDefinition
var column_name: StringName
var new_column_name: StringName
var index: GDSQLIndexDefinition
var index_name: StringName
var foreign_key: GDSQLForeignKeyDefinition
var foreign_key_name: StringName
var value: Variant
var enabled: bool
var generation: GDSQLColumnDefinition.Generation
var resource_ownership := GDSQLResourceOwnership.Mode.OWNED
var column_names: Array[StringName] = []


static func add_column(column_definition: GDSQLColumnDefinition) -> GDSQLTableAlteration:
	var alteration := GDSQLTableAlteration.new()
	alteration.kind = Kind.ADD_COLUMN
	alteration.column = column_definition
	return alteration


static func rename_column(
		current_name: StringName,
		new_name: StringName,
) -> GDSQLTableAlteration:
	var alteration := GDSQLTableAlteration.new()
	alteration.kind = Kind.RENAME_COLUMN
	alteration.column_name = current_name
	alteration.new_column_name = new_name
	return alteration


static func drop_column(column_to_drop: StringName) -> GDSQLTableAlteration:
	var alteration := GDSQLTableAlteration.new()
	alteration.kind = Kind.DROP_COLUMN
	alteration.column_name = column_to_drop
	return alteration


static func add_index(index_definition: GDSQLIndexDefinition) -> GDSQLTableAlteration:
	var alteration := GDSQLTableAlteration.new()
	alteration.kind = Kind.ADD_INDEX
	alteration.index = index_definition
	return alteration


static func drop_index(index_to_drop: StringName) -> GDSQLTableAlteration:
	var alteration := GDSQLTableAlteration.new()
	alteration.kind = Kind.DROP_INDEX
	alteration.index_name = index_to_drop
	return alteration


static func add_foreign_key(
		foreign_key_definition: GDSQLForeignKeyDefinition,
) -> GDSQLTableAlteration:
	var alteration := GDSQLTableAlteration.new()
	alteration.kind = Kind.ADD_FOREIGN_KEY
	alteration.foreign_key = foreign_key_definition
	return alteration


static func drop_foreign_key(foreign_key_to_drop: StringName) -> GDSQLTableAlteration:
	var alteration := GDSQLTableAlteration.new()
	alteration.kind = Kind.DROP_FOREIGN_KEY
	alteration.foreign_key_name = foreign_key_to_drop
	return alteration


static func set_column_default(
		target_column: StringName,
		default_value: Variant,
) -> GDSQLTableAlteration:
	var alteration := GDSQLTableAlteration.new()
	alteration.kind = Kind.SET_COLUMN_DEFAULT
	alteration.column_name = target_column
	alteration.value = default_value
	return alteration


static func clear_column_default(target_column: StringName) -> GDSQLTableAlteration:
	var alteration := GDSQLTableAlteration.new()
	alteration.kind = Kind.CLEAR_COLUMN_DEFAULT
	alteration.column_name = target_column
	return alteration


static func set_column_nullable(
		target_column: StringName,
		is_nullable: bool,
) -> GDSQLTableAlteration:
	var alteration := GDSQLTableAlteration.new()
	alteration.kind = Kind.SET_COLUMN_NULLABLE
	alteration.column_name = target_column
	alteration.enabled = is_nullable
	return alteration


static func set_column_unique(
		target_column: StringName,
		is_unique: bool,
) -> GDSQLTableAlteration:
	var alteration := GDSQLTableAlteration.new()
	alteration.kind = Kind.SET_COLUMN_UNIQUE
	alteration.column_name = target_column
	alteration.enabled = is_unique
	return alteration


static func set_column_auto_increment(
		target_column: StringName,
		is_auto_increment: bool,
) -> GDSQLTableAlteration:
	var alteration := GDSQLTableAlteration.new()
	alteration.kind = Kind.SET_COLUMN_AUTO_INCREMENT
	alteration.column_name = target_column
	alteration.enabled = is_auto_increment
	return alteration


static func set_column_generation(
		target_column: StringName,
		generation_policy: GDSQLColumnDefinition.Generation,
) -> GDSQLTableAlteration:
	var alteration := GDSQLTableAlteration.new()
	alteration.kind = Kind.SET_COLUMN_GENERATION
	alteration.column_name = target_column
	alteration.generation = generation_policy
	return alteration


static func set_resource_ownership(
		target_column: StringName,
		ownership: GDSQLResourceOwnership.Mode,
) -> GDSQLTableAlteration:
	var alteration := GDSQLTableAlteration.new()
	alteration.kind = Kind.SET_RESOURCE_OWNERSHIP
	alteration.column_name = target_column
	alteration.resource_ownership = ownership
	return alteration


static func reorder_columns(ordered_names: Array[StringName]) -> GDSQLTableAlteration:
	var alteration := GDSQLTableAlteration.new()
	alteration.kind = Kind.REORDER_COLUMNS
	alteration.column_names = ordered_names.duplicate()
	return alteration


func is_destructive() -> bool:
	return kind == Kind.DROP_COLUMN


func is_valid() -> bool:
	match kind:
		Kind.ADD_COLUMN:
			return _is_valid_column(column)
		Kind.RENAME_COLUMN:
			return _is_valid_name(column_name) and _is_valid_name(new_column_name)
		Kind.DROP_COLUMN, Kind.SET_COLUMN_DEFAULT, Kind.CLEAR_COLUMN_DEFAULT, \
		Kind.SET_COLUMN_NULLABLE, Kind.SET_COLUMN_UNIQUE, \
		Kind.SET_COLUMN_AUTO_INCREMENT:
			return _is_valid_name(column_name)
		Kind.ADD_INDEX:
			return _is_valid_index(index)
		Kind.DROP_INDEX:
			return _is_valid_name(index_name)
		Kind.ADD_FOREIGN_KEY:
			return _is_valid_foreign_key(foreign_key)
		Kind.DROP_FOREIGN_KEY:
			return _is_valid_name(foreign_key_name)
		Kind.SET_COLUMN_GENERATION:
			return _is_valid_name(column_name) \
					and generation >= GDSQLColumnDefinition.Generation.NONE \
					and generation <= GDSQLColumnDefinition.Generation.UPDATED_AT
		Kind.SET_RESOURCE_OWNERSHIP:
			return _is_valid_name(column_name) \
					and GDSQLResourceOwnership.is_valid(resource_ownership)
		Kind.REORDER_COLUMNS:
			var seen: Dictionary[StringName, bool] = { }
			for ordered_name in column_names:
				if not _is_valid_name(ordered_name) or seen.has(ordered_name):
					return false
				seen[ordered_name] = true
			return not column_names.is_empty()
	return false


func _is_valid_column(candidate: GDSQLColumnDefinition) -> bool:
	return candidate != null \
			and _is_valid_name(candidate.name) \
			and candidate.data_type > TYPE_NIL \
			and candidate.data_type < TYPE_MAX \
			and candidate.has_valid_type_constraint() \
			and candidate.generation >= GDSQLColumnDefinition.Generation.NONE \
			and candidate.generation <= GDSQLColumnDefinition.Generation.UPDATED_AT


func _is_valid_index(candidate: GDSQLIndexDefinition) -> bool:
	if candidate == null or not _is_valid_name(candidate.name) \
			or candidate.columns.is_empty():
		return false
	var seen: Dictionary[StringName, bool] = { }
	for indexed_column in candidate.columns:
		if not _is_valid_name(indexed_column) or seen.has(indexed_column):
			return false
		seen[indexed_column] = true
	return true


func _is_valid_foreign_key(candidate: GDSQLForeignKeyDefinition) -> bool:
	return candidate != null \
			and _is_valid_name(candidate.name) \
			and _is_valid_name(candidate.column) \
			and _is_valid_name(candidate.referenced_table) \
			and _is_valid_name(candidate.referenced_column) \
			and candidate.on_delete == GDSQLForeignKeyDefinition.Action.RESTRICT \
			and candidate.on_update == GDSQLForeignKeyDefinition.Action.RESTRICT


func _is_valid_name(candidate: StringName) -> bool:
	return candidate != &"" and String(candidate).is_valid_identifier()


func describe() -> String:
	match kind:
		Kind.ADD_COLUMN:
			return "Add column '%s'." % (column.name if column != null else &"")
		Kind.RENAME_COLUMN:
			return "Rename column '%s' to '%s'." % [column_name, new_column_name]
		Kind.DROP_COLUMN:
			return "Drop column '%s' and its stored values." % column_name
		Kind.ADD_INDEX:
			return "Add index '%s'." % (index.name if index != null else &"")
		Kind.DROP_INDEX:
			return "Drop index '%s'." % index_name
		Kind.ADD_FOREIGN_KEY:
			return "Add foreign key '%s'." % (
					foreign_key.name if foreign_key != null else &""
			)
		Kind.DROP_FOREIGN_KEY:
			return "Drop foreign key '%s'." % foreign_key_name
		Kind.SET_COLUMN_DEFAULT:
			return "Set the default for column '%s'." % column_name
		Kind.CLEAR_COLUMN_DEFAULT:
			return "Clear the default for column '%s'." % column_name
		Kind.SET_COLUMN_NULLABLE:
			return "Set column '%s' nullable to %s." % [column_name, enabled]
		Kind.SET_COLUMN_UNIQUE:
			return "Set column '%s' unique to %s." % [column_name, enabled]
		Kind.SET_COLUMN_AUTO_INCREMENT:
			return "Set column '%s' auto increment to %s." % [column_name, enabled]
		Kind.SET_COLUMN_GENERATION:
			return "Set the generation policy for column '%s'." % column_name
		Kind.SET_RESOURCE_OWNERSHIP:
			return "Set Resource ownership for column '%s' to %s." % [
				column_name,
				GDSQLResourceOwnership.display_name(resource_ownership),
			]
		Kind.REORDER_COLUMNS:
			return "Set the table column display order."
	return "Unknown table alteration."
