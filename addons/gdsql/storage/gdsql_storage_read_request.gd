class_name GDSQLStorageReadRequest
extends RefCounted
## Describes the values required from a storage read without prescribing how a
## backend finds or physically decodes them.

var required_columns: Array[StringName] = []
var all_columns := true
var preserve_resource_references := false


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
