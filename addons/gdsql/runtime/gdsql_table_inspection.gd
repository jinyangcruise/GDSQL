class_name GDSQLTableInspection
extends RefCounted
## Lightweight table metadata used for discovery and editor navigation.
##
## Inspection reads schema and storage headers without materializing rows.

var name: StringName
var schema_exists: bool
var storage_exists: bool
var row_count: int
var column_count: int
var index_count: int


func _init(
		table_name: StringName = &"",
		has_schema: bool = false,
		has_storage: bool = false,
		rows: int = 0,
		columns: int = 0,
		indexes: int = 0,
) -> void:
	name = table_name
	schema_exists = has_schema
	storage_exists = has_storage
	row_count = rows
	column_count = columns
	index_count = indexes
