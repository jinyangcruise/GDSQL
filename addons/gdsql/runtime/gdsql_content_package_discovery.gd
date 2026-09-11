@abstract
class_name GDSQLContentPackageDiscovery
extends RefCounted
## Boundary for discovering typed packages from explicit source locations.

@abstract
func discover(
		base_package_root: String,
		package_container_roots: Array[String],
) -> GDSQLOperationResult
