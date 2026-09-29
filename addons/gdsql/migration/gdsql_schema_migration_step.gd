class_name GDSQLSchemaMigrationStep
extends RefCounted
## One ordered table alteration group inside a forward schema migration.

var table_name: StringName
var alterations: Array[GDSQLTableAlteration] = []


func _init(
		target_table: StringName = &"",
		requested_alterations: Array[GDSQLTableAlteration] = [],
) -> void:
	table_name = target_table
	alterations = requested_alterations.duplicate()


func is_valid() -> bool:
	if table_name == &"" or not String(table_name).is_valid_identifier() \
			or alterations.is_empty():
		return false
	for alteration in alterations:
		if alteration == null:
			return false
	return true


func is_destructive() -> bool:
	for alteration in alterations:
		if alteration != null and alteration.is_destructive():
			return true
	return false
