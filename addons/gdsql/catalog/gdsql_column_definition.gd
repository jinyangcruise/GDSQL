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


static func created_at(column_name: StringName = &"created_at") -> GDSQLColumnDefinition:
	var column := GDSQLColumnDefinition.new(column_name, TYPE_INT, false)
	column.generation = Generation.CREATED_AT
	return column


static func updated_at(column_name: StringName = &"updated_at") -> GDSQLColumnDefinition:
	var column := GDSQLColumnDefinition.new(column_name, TYPE_INT, false)
	column.generation = Generation.UPDATED_AT
	return column


func _init(
		name: StringName = &"",
		type: Variant.Type = TYPE_NIL,
		nullable: bool = true,
		unique: bool = false,
		auto_increment: bool = false,
		default_value: Variant = null,
) -> void:
	self.name = name
	self.data_type = type
	self.nullable = nullable
	self.unique = unique
	self.auto_increment = auto_increment
	if default_value != null:
		set_default(default_value)


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
		return value is Resource
	if data_type == TYPE_NIL or typeof(value) == data_type:
		return true
	return data_type == TYPE_FLOAT and typeof(value) == TYPE_INT
