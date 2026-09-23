class_name GDSQLResourcePropertyDefinition
extends RefCounted
## One validated, filterable scalar leaf exposed by a Resource type.

var path: Array[StringName] = []
var data_type: Variant.Type = TYPE_NIL


func _init(
		property_path: Array[StringName] = [],
		property_type: Variant.Type = TYPE_NIL,
) -> void:
	path = property_path.duplicate()
	data_type = property_type


func serialized_path() -> String:
	var parts := PackedStringArray()
	for part in path:
		parts.append(String(part))
	return ":".join(parts)


func display_path() -> String:
	var parts := PackedStringArray()
	for part in path:
		parts.append(String(part))
	return " → ".join(parts)
