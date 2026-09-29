class_name GDSQLContentPackageManifest
extends RefCounted
## Storage-independent metadata for one immutable content package.

var package_id: StringName
var display_name: String
var version: String
var kind: int
var priority: int
var data_path: String
var assets_path: String
var dependencies: Array[GDSQLContentPackageDependency]
var load_after: Array[StringName]
var load_before: Array[StringName]


func _init(
		id: StringName = &"",
		name: String = "",
		package_version: String = "",
		package_kind: int = -1,
		package_priority: int = 0,
		package_data_path: String = "data",
		package_assets_path: String = "assets",
		package_dependencies: Array[GDSQLContentPackageDependency] = [],
		packages_after: Array[StringName] = [],
		packages_before: Array[StringName] = [],
) -> void:
	package_id = id
	display_name = name
	version = package_version
	kind = package_kind
	priority = package_priority
	data_path = package_data_path
	assets_path = package_assets_path
	dependencies = package_dependencies.duplicate()
	load_after = packages_after.duplicate()
	load_before = packages_before.duplicate()
