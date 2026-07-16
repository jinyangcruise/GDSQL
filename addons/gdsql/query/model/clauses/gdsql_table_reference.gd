class_name GDSQLTableReference
extends GDSQLQuerySource

var database_name: StringName
var table_name: StringName
var alias: StringName


func _init(p_table: StringName = &"", p_database: StringName = &"", p_alias: StringName = &"") -> void:
	table_name = p_table
	database_name = p_database
	alias = p_alias
