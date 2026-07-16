class_name GDSQLColumnDefinition
extends RefCounted

var name: StringName
var data_type: Variant.Type = TYPE_NIL
var nullable: bool = true
var unique: bool = false
var auto_increment: bool = false
var default_value: Variant


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
	self.default_value = default_value
