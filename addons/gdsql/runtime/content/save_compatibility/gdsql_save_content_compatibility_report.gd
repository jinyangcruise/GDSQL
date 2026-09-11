class_name GDSQLSaveContentCompatibilityReport
extends RefCounted
## Describes package-set differences without choosing a game's load policy.

enum Status {
	UNAVAILABLE,
	UNTRACKED,
	EXACT,
	CHANGED,
	MISSING_PACKAGES,
}

var status := Status.UNAVAILABLE
var missing_packages: Array[GDSQLContentPackageFingerprint] = []
var changed_packages: Array[GDSQLSaveContentPackageChange] = []
var additional_packages: Array[GDSQLContentPackageFingerprint] = []
var load_order_changed := false
var diagnostics := GDSQLDiagnostics.new()


func can_resolve_expected_packages() -> bool:
	return status in [Status.EXACT, Status.CHANGED]


func requires_policy_decision() -> bool:
	return status != Status.EXACT
