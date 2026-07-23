class_name GDSQLColumnId
extends RefCounted

var table_id: GDSQLTableId
var column_name: StringName


func _init(_table: GDSQLTableId = null, _column: StringName = &"") -> void:
	table_id = _table
	column_name = _column
