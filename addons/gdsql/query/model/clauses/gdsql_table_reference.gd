class_name GDSQLTableReference
extends GDSQLQuerySource

var database_name: StringName
var table_name: StringName
var alias: StringName


func _init(table: StringName = &"", database: StringName = &"", alias: StringName = &"") -> void:
	self.table_name = table
	self.database_name = database
	self.alias = alias
