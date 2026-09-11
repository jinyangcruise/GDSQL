class_name GDSQLContentRowProvenance
extends RefCounted
## Identifies the package operation that contributed to one content row history.

var table_name: StringName
var identity: Variant
var package_id: StringName
var package_version: String
var operation_kind: GDSQLContentRowOperation.Kind


func _init(
		table: StringName = &"",
		row_identity: Variant = null,
		source_package_id: StringName = &"",
		source_package_version: String = "",
		operation: GDSQLContentRowOperation.Kind = GDSQLContentRowOperation.Kind.UPSERT,
) -> void:
	table_name = table
	identity = row_identity
	package_id = source_package_id
	package_version = source_package_version
	operation_kind = operation


func is_removal() -> bool:
	return operation_kind == GDSQLContentRowOperation.Kind.REMOVE
