class_name GDSQLStorageReadRequest
extends RefCounted
## Describes the values required from a storage read without prescribing how a
## backend finds or physically decodes them.

var required_columns: Array[StringName] = []
var all_columns := true
var preserve_resource_references := false
var batch_size := -1
var cursor: GDSQLStorageReadCursor


static func all(preserve_references: bool = false) -> GDSQLStorageReadRequest:
	var request := GDSQLStorageReadRequest.new()
	request.preserve_resource_references = preserve_references
	return request


static func for_columns(
	columns: Array[StringName],
	preserve_references: bool = false,
) -> GDSQLStorageReadRequest:
	var request := GDSQLStorageReadRequest.new()
	request.required_columns = columns.duplicate()
	request.all_columns = false
	request.preserve_resource_references = preserve_references
	return request


func includes_column(column: StringName) -> bool:
	return all_columns or required_columns.has(column)


## Returns a separate bounded request. The original column and Resource
## materialization intent is preserved so callers can safely reuse it.
func bounded(
		max_rows: int,
		start_cursor: GDSQLStorageReadCursor = null,
) -> GDSQLStorageReadRequest:
	var request := duplicate_request()
	request.batch_size = max_rows
	request.cursor = (
		start_cursor.duplicate_cursor()
		if start_cursor != null
		else null
	)
	return request


func duplicate_request() -> GDSQLStorageReadRequest:
	var request := GDSQLStorageReadRequest.new()
	request.required_columns = required_columns.duplicate()
	request.all_columns = all_columns
	request.preserve_resource_references = preserve_resource_references
	request.batch_size = batch_size
	request.cursor = cursor.duplicate_cursor() if cursor != null else null
	return request


func is_bounded() -> bool:
	return batch_size > 0
