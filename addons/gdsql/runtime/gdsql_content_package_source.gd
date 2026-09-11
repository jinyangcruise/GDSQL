class_name GDSQLContentPackageSource
extends RefCounted
## Associates validated package metadata with its immutable source root.

var package_root: String
var manifest: GDSQLContentPackageManifest


func _init(
		root: String = "",
		package_manifest: GDSQLContentPackageManifest = null,
) -> void:
	package_root = root
	manifest = package_manifest


func get_data_root() -> String:
	return package_root.path_join(manifest.data_path) if manifest != null else ""


func get_assets_root() -> String:
	return package_root.path_join(manifest.assets_path) if manifest != null else ""
