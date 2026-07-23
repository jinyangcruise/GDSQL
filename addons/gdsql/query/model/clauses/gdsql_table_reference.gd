class_name GDSQLTableReference
extends GDSQLQuerySource

var database_name: StringName
var table_name: StringName
var alias: StringName


func _init(
		_table: StringName = &"",
		_database: StringName = &"",
		_alias: StringName = &"",
) -> void:
	table_name = _table
	database_name = _database
	alias = _alias
