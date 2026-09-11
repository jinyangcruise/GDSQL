class_name GDSQLContentPackageDependency
extends RefCounted
## One required package and its declared version constraint.

var package_id: StringName
var version_constraint: String


func _init(
		dependency_package_id: StringName = &"",
		dependency_version_constraint: String = "*",
) -> void:
	package_id = dependency_package_id
	version_constraint = dependency_version_constraint
