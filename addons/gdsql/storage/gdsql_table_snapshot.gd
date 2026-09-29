class_name GDSQLTableSnapshot
extends RefCounted

var rows: Array[GDSQLRowRecord] = []
var primary_key: StringName
var row_count: int = 0
var next_auto_increment: int = 1


func find_by_primary_key(key: Variant) -> GDSQLRowRecord:
	for row in rows:
		if row.get_value(primary_key) == key:
			return row
	return null
