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
var primary_key: StringName
var columns: Array[GDSQLColumnDefinition] = []


func _init(
		table_name: StringName = &"",
		has_schema: bool = false,
		has_storage: bool = false,
		rows: int = 0,
		columns: int = 0,
		indexes: int = 0,
		inspected_columns: Array[GDSQLColumnDefinition] = [],
		inspected_primary_key: StringName = &"",
) -> void:
	name = table_name
	schema_exists = has_schema
	storage_exists = has_storage
	row_count = rows
	column_count = columns
	index_count = indexes
	primary_key = inspected_primary_key
	self.columns = inspected_columns.duplicate()


func get_column(column_name: StringName) -> GDSQLColumnDefinition:
	for column in columns:
		if column.name == column_name:
			return column
	return null
