class_name GDSQLColumnDefinition
extends RefCounted

enum Generation {
	NONE,
	CREATED_AT,
	UPDATED_AT,
	# This policy boundary is going to allow UUID generation and more
	# storage-independent generated values.
}

var name: StringName
var data_type: Variant.Type = TYPE_NIL
var nullable: bool = true
var unique: bool = false
var auto_increment: bool = false
var default: GDSQLColumnDefault
var generation: Generation = Generation.NONE
var resource_type: GDSQLResourceTypeConstraint


static func created_at(column_name: StringName = &"created_at") -> GDSQLColumnDefinition:
	var column := GDSQLColumnDefinition.new(column_name, TYPE_INT, false)
	column.generation = Generation.CREATED_AT
	return column


static func updated_at(column_name: StringName = &"updated_at") -> GDSQLColumnDefinition:
	var column := GDSQLColumnDefinition.new(column_name, TYPE_INT, false)
	column.generation = Generation.UPDATED_AT
	return column


func _init(
		_name: StringName = &"",
		_type: Variant.Type = TYPE_NIL,
		_nullable: bool = true,
		_unique: bool = false,
		_auto_increment: bool = false,
		_default_value: Variant = null,
		_resource_type: GDSQLResourceTypeConstraint = null,
) -> void:
	name = _name
	data_type = _type
	nullable = _nullable
	unique = _unique
	auto_increment = _auto_increment
	resource_type = _resource_type
	if _default_value != null:
		set_default(_default_value)


func set_default(value: Variant) -> GDSQLColumnDefinition:
	default = GDSQLColumnDefault.new(value)
	return self


func clear_default() -> GDSQLColumnDefinition:
	default = null
	return self


func has_default() -> bool:
	return default != null


func get_default_value() -> Variant:
	return null if default == null else default.value


func accepts_value(value: Variant) -> bool:
	if value == null:
		return nullable
	if data_type == TYPE_OBJECT:
		return resource_type != null and resource_type.accepts_value(value)
	if data_type == TYPE_NIL or typeof(value) == data_type:
		return true
	return data_type == TYPE_FLOAT and typeof(value) == TYPE_INT


func has_valid_type_constraint() -> bool:
	if data_type == TYPE_OBJECT:
		return resource_type != null and resource_type.is_valid()
	return resource_type == null


func expected_type_name() -> String:
	if data_type == TYPE_OBJECT:
		return display_type_name()
	return "Variant type %s" % display_type_name()


func display_type_name() -> String:
	if data_type == TYPE_OBJECT:
		return (
			resource_type.display_name()
			if resource_type != null
			else "Unspecified Resource"
		)
	return type_string(data_type)
