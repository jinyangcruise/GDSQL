class_name GDSQLStorageReadBatch
extends GDSQLOperationResult
## One bounded storage response and its opaque continuation.

var rows: Array[GDSQLRowRecord] = []
var next_cursor: GDSQLStorageReadCursor
var statistics := GDSQLStorageReadStatistics.new()


func has_more() -> bool:
	return next_cursor != null


func get_rows() -> Array[GDSQLRowRecord]:
	return rows.duplicate()


func get_next_cursor() -> GDSQLStorageReadCursor:
	return next_cursor.duplicate_cursor() if next_cursor != null else null
