class_name GDSQLEditorWhereField
extends RefCounted
## One selectable table column or Resource-property leaf in the WHERE editor.

var column_name: StringName
var property_path: Array[StringName] = []
var data_type: Variant.Type = TYPE_NIL
var nullable := true


func _init(
		target_column: StringName = &"",
		target_path: Array[StringName] = [],
		target_type: Variant.Type = TYPE_NIL,
		is_nullable: bool = true,
) -> void:
	column_name = target_column
	property_path = target_path.duplicate()
	data_type = target_type
	nullable = is_nullable


func key() -> String:
	return String(column_name) + (
			":" + serialized_property_path() if not property_path.is_empty() else ""
	)


func display_name() -> String:
	var parts := PackedStringArray([String(column_name)])
	for part in property_path:
		parts.append(String(part))
	return " → ".join(parts)


func serialized_property_path() -> String:
	var parts := PackedStringArray()
	for part in property_path:
		parts.append(String(part))
	return ":".join(parts)


func expression() -> GDSQLQueryExpression:
	if property_path.is_empty():
		return GDSQLExpr.column(column_name)
	return GDSQLExpr.resource_property(column_name, property_path)
