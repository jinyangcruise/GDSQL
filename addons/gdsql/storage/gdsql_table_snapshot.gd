class_name GDSQLTableSnapshot
extends RefCounted

var rows: Array[GDSQLRowRecord] = []
var primary_key: StringName


func find_by_primary_key(key: Variant) -> GDSQLRowRecord:
	for row in rows:
		if row.get_value(primary_key) == key:
			return row
	return null
