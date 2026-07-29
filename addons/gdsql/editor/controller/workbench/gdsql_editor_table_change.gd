class_name GDSQLEditorTableChange
extends RefCounted
## Typed editor intent grouping alterations for one existing table.

var table_name: StringName
var alterations: Array[GDSQLTableAlteration] = []


func _init(
		target_table: StringName = &"",
		requested_alterations: Array[GDSQLTableAlteration] = [],
) -> void:
	table_name = target_table
	alterations = requested_alterations.duplicate()
