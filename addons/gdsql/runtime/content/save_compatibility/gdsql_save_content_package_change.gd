class_name GDSQLSaveContentPackageChange
extends RefCounted
## Associates a save's expected package fingerprint with its active replacement.

var expected: GDSQLContentPackageFingerprint
var active: GDSQLContentPackageFingerprint


func _init(
		expected_package: GDSQLContentPackageFingerprint = null,
		active_package: GDSQLContentPackageFingerprint = null,
) -> void:
	expected = expected_package
	active = active_package
