class_name GDSQLDatabaseRoleBinding
extends RefCounted
## Associates one logical database role with a durable registration name.

var role: StringName
var registration_name: StringName


func _init(
		logical_role: StringName = &"",
		selected_registration_name: StringName = &"",
) -> void:
	role = logical_role
	registration_name = selected_registration_name
