class_name GDSQLContentPackageResolutionResult
extends GDSQLOperationResult
## Deterministically ordered package sources selected for effective content.

var ordered_packages: Array[GDSQLContentPackageSource] = []


func set_packages(packages: Array[GDSQLContentPackageSource]) -> void:
	ordered_packages = packages.duplicate()
	value = ordered_packages


func get_package(package_id: StringName) -> GDSQLContentPackageSource:
	for package in ordered_packages:
		if package.manifest != null and package.manifest.package_id == package_id:
			return package
	return null
