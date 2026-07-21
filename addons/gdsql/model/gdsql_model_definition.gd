class_name GDSQLModelDefinition
extends RefCounted
## Stable metadata captured when a model script is registered.

var model_script: Script
var database_role: StringName
var table_name: StringName
var primary_key: StringName
var access_mode: GDSQLModelAccess.Mode


func _init(
		script: Script = null,
		role: StringName = &"",
		table: StringName = &"",
		key: StringName = &"id",
		mode: GDSQLModelAccess.Mode = GDSQLModelAccess.Mode.READ_ONLY,
) -> void:
	model_script = script
	database_role = role
	table_name = table
	primary_key = key
	access_mode = mode
