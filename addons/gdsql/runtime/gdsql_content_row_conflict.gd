class_name GDSQLContentRowConflict
extends RefCounted
## Reports deterministic replacement of one package-owned row by a later layer.

var table_name: StringName
var identity: Variant
var previous: GDSQLContentRowProvenance
var replacement: GDSQLContentRowProvenance


func _init(
		table: StringName = &"",
		row_identity: Variant = null,
		previous_origin: GDSQLContentRowProvenance = null,
		replacement_origin: GDSQLContentRowProvenance = null,
) -> void:
	table_name = table
	identity = row_identity
	previous = previous_origin
	replacement = replacement_origin
