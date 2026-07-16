class_name GDSQLTableId
extends RefCounted

var database_name: StringName
var table_name: StringName


func _init(database: StringName = &"", table: StringName = &"") -> void:
	self.database_name = database
	self.table_name = table
