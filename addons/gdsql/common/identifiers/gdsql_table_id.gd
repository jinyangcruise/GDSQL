class_name GDSQLTableId
extends RefCounted

var database_name: StringName
var table_name: StringName


func _init(_database: StringName = &"", _table: StringName = &"") -> void:
	database_name = _database
	table_name = _table
