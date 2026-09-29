class_name GDSQLContentPackageFingerprint
extends RefCounted
## Stable cache identity for one package in resolved load order.

var package_id: StringName
var version: String
var content_hash: String


func _init(
		id: StringName = &"",
		package_version: String = "",
		package_content_hash: String = "",
) -> void:
	package_id = id
	version = package_version
	content_hash = package_content_hash


func is_equivalent_to(other: GDSQLContentPackageFingerprint) -> bool:
	return other != null and package_id == other.package_id \
			and version == other.version and content_hash == other.content_hash
