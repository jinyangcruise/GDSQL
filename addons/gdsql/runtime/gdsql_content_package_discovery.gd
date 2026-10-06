@abstract
class_name GDSQLContentPackageDiscovery
extends RefCounted
## Boundary for discovering typed packages from explicit source locations.

@abstract
func discover(
		base_package_root: String,
		package_container_roots: Array[String],
) -> GDSQLOperationResult


func _tr(message: StringName) -> StringName:
	return TranslationServer.get_or_add_domain(&"GDSQL").translate(message)
