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
	SET_COLUMN_DEFAULT,
	CLEAR_COLUMN_DEFAULT,
	SET_COLUMN_NULLABLE,
	SET_COLUMN_UNIQUE,
	SET_COLUMN_AUTO_INCREMENT,
	SET_COLUMN_GENERATION,
}

var kind: Kind
var column: GDSQLColumnDefinition
var column_name: StringName
var new_column_name: StringName
var index: GDSQLIndexDefinition
var index_name: StringName
var value: Variant
var enabled: bool
var generation: GDSQLColumnDefinition.Generation


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


func is_destructive() -> bool:
	return kind == Kind.DROP_COLUMN


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
	return "Unknown table alteration."
