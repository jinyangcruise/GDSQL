class_name GDSQLColumnId
extends RefCounted

var table_id: GDSQLTableId
var column_name: StringName


func _init(table: GDSQLTableId = null, column: StringName = &"") -> void:
	self.table_id = table
	self.column_name = column
