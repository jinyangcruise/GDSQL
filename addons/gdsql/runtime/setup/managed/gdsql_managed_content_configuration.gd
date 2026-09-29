class_name GDSQLManagedContentConfiguration
extends RefCounted
## Typed project configuration for managed-content package discovery.

const DEFAULT_BASE_PACKAGE_ROOT := "res://content/base"

var base_package_root: String
var package_container_roots: Array[String]
var enabled_package_ids: Array[StringName]


static func create_default() -> GDSQLManagedContentConfiguration:
	return GDSQLManagedContentConfiguration.new(
		DEFAULT_BASE_PACKAGE_ROOT,
		["res://content/packages", "user://gdsql/mods"],
	)


func _init(
		base_root: String = DEFAULT_BASE_PACKAGE_ROOT,
		package_roots: Array[String] = [],
		enabled_ids: Array[StringName] = [],
) -> void:
	base_package_root = base_root
	package_container_roots = package_roots.duplicate()
	enabled_package_ids = enabled_ids.duplicate()
