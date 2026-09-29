@abstract
class_name GDSQLContentPackageManifestStore
extends RefCounted
## Boundary for loading a typed package manifest from a package source root.

@abstract
func load_manifest(package_root: String) -> GDSQLOperationResult
