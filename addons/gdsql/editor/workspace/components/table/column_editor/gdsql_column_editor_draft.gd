class_name GDSQLEditorColumnDraft
extends RefCounted
## Typed local schema draft for one scene-backed column editor row.

var original: GDSQLColumnDefinition
var name := ""
var data_type: Variant.Type = TYPE_INT
var resource_type: GDSQLResourceTypeConstraint
var resource_prototype: Resource
var nullable := true
var unique := false
var auto_increment := false
var has_default := false
var default_value: Variant
var default_valid := true
var default_modified := false
var generation := GDSQLColumnDefinition.Generation.NONE
var remove := false
var is_primary := false


static func create_new(primary: bool = false) -> GDSQLEditorColumnDraft:
	var draft := GDSQLEditorColumnDraft.new()
	draft.name = "id" if primary else ""
	draft.nullable = not primary
	draft.unique = primary
	draft.auto_increment = primary
	draft.is_primary = primary
	return draft


static func from_definition(
		column: GDSQLColumnDefinition,
		primary: bool = false,
) -> GDSQLEditorColumnDraft:
	var draft := GDSQLEditorColumnDraft.new()
	draft.original = column
	draft.name = String(column.name)
	draft.data_type = column.data_type
	draft.resource_type = column.resource_type
	draft.resource_prototype = (
		column.resource_type.instantiate_prototype()
		if column.resource_type != null
		else null
	)
	draft.nullable = column.nullable
	draft.unique = column.unique
	draft.auto_increment = column.auto_increment
	draft.has_default = column.has_default()
	draft.default_value = column.get_default_value()
	draft.generation = column.generation
	draft.is_primary = primary
	return draft


func get_column_name() -> StringName:
	return StringName(name.strip_edges())


func reset_for_type(selected_type: Variant.Type) -> void:
	data_type = selected_type
	resource_type = null
	resource_prototype = null
	has_default = false
	default_value = null
	default_valid = true
	default_modified = false
	generation = GDSQLColumnDefinition.Generation.NONE


func duplicate_resource_prototype() -> Resource:
	var prototype := resource_prototype
	if prototype == null and resource_type != null:
		prototype = resource_type.instantiate_prototype()
	return prototype.duplicate(true) as Resource if prototype != null else null


func build_definition() -> GDSQLColumnDefinition:
	var definition := GDSQLColumnDefinition.new(
		get_column_name(),
		data_type,
		nullable,
		unique,
		auto_increment,
	)
	definition.resource_type = resource_type
	definition.generation = generation
	if has_default:
		definition.set_default(default_value)
	return definition


func build_alterations() -> Array[GDSQLTableAlteration]:
	var alterations: Array[GDSQLTableAlteration] = []
	if original == null:
		if not remove:
			alterations.append(GDSQLTableAlteration.add_column(build_definition()))
		return alterations
	if remove:
		alterations.append(GDSQLTableAlteration.drop_column(original.name))
		return alterations
	if nullable != original.nullable:
		alterations.append(GDSQLTableAlteration.set_column_nullable(original.name, nullable))
	if unique != original.unique:
		alterations.append(GDSQLTableAlteration.set_column_unique(original.name, unique))
	if auto_increment != original.auto_increment:
		alterations.append(
			GDSQLTableAlteration.set_column_auto_increment(original.name, auto_increment),
		)
	if has_default:
		if not original.has_default() or default_modified \
				or default_value != original.get_default_value():
			alterations.append(
				GDSQLTableAlteration.set_column_default(original.name, default_value),
			)
	elif original.has_default():
		alterations.append(GDSQLTableAlteration.clear_column_default(original.name))
	if generation != original.generation:
		alterations.append(
			GDSQLTableAlteration.set_column_generation(original.name, generation),
		)
	if get_column_name() != original.name:
		alterations.append(
			GDSQLTableAlteration.rename_column(original.name, get_column_name()),
		)
	return alterations


func get_validation_errors() -> Array[String]:
	var errors: Array[String] = []
	var column_name := get_column_name()
	if column_name == &"":
		errors.append("A column name is required.")
	elif not String(column_name).is_valid_identifier():
		errors.append("Column '%s' must be a valid identifier." % column_name)
	var definition := build_definition()
	if not definition.has_valid_type_constraint():
		errors.append("Column '%s' requires a concrete Resource subtype." % column_name)
	if auto_increment and data_type != TYPE_INT:
		errors.append("Auto-increment column '%s' must use TYPE_INT." % column_name)
	if generation != GDSQLColumnDefinition.Generation.NONE:
		if data_type != TYPE_INT:
			errors.append("Generated column '%s' must use TYPE_INT." % column_name)
		if auto_increment:
			errors.append("Column '%s' cannot be generated and auto-incremented." % column_name)
		if has_default:
			errors.append("Generated column '%s' cannot declare a static default." % column_name)
	if has_default and (not default_valid or not definition.accepts_value(default_value)):
		errors.append(
			"Default for column '%s' must be a valid %s value."
			% [column_name, definition.expected_type_name()],
		)
	return errors
