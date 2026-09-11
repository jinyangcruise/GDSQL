class_name GDSQLSemanticVersion
extends RefCounted
## Comparable semantic version used by content-package compatibility checks.

const PATTERN := (
		r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
		+ r"(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?"
		+ r"(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$"
)

var major: int
var minor: int
var patch: int
var prerelease: String
var build: String


func _init(
		major_version: int = 0,
		minor_version: int = 0,
		patch_version: int = 0,
		prerelease_version: String = "",
		build_metadata: String = "",
) -> void:
	major = major_version
	minor = minor_version
	patch = patch_version
	prerelease = prerelease_version
	build = build_metadata


static func parse(value: String) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	var normalized := value.strip_edges()
	var expression := RegEx.new()
	if expression.compile(PATTERN) != OK or expression.search(normalized) == null:
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_SEMANTIC_VERSION_INVALID",
				"'%s' is not a semantic version." % value,
			),
		)
		return result
	var build_parts := normalized.split("+", true, 1)
	var core_and_prerelease := build_parts[0].split("-", true, 1)
	var prerelease_version := core_and_prerelease[1] if core_and_prerelease.size() > 1 else ""
	for identifier in prerelease_version.split(".", false):
		if identifier.is_valid_int() and identifier.length() > 1 and identifier.begins_with("0"):
			result.add_diagnostic(
				GDSQLQueryDiagnostic.new(
					&"GDSQL_SEMANTIC_VERSION_INVALID",
					"'%s' contains a numeric prerelease identifier with a leading zero." % value,
				),
			)
			return result
	var core := core_and_prerelease[0].split(".")
	result.value = GDSQLSemanticVersion.new(
		core[0].to_int(),
		core[1].to_int(),
		core[2].to_int(),
		prerelease_version,
		build_parts[1] if build_parts.size() > 1 else "",
	)
	return result


## Returns a negative value when this version precedes other, zero when equal.
func compare(other: GDSQLSemanticVersion) -> int:
	if other == null:
		return 1
	for difference in [major - other.major, minor - other.minor, patch - other.patch]:
		if difference != 0:
			return -1 if difference < 0 else 1
	if prerelease == other.prerelease:
		return 0
	if prerelease.is_empty():
		return 1
	if other.prerelease.is_empty():
		return -1
	var own_identifiers := prerelease.split(".")
	var other_identifiers := other.prerelease.split(".")
	for index in mini(own_identifiers.size(), other_identifiers.size()):
		var own := own_identifiers[index]
		var compared := other_identifiers[index]
		if own == compared:
			continue
		var own_numeric := own.is_valid_int()
		var other_numeric := compared.is_valid_int()
		if own_numeric and other_numeric:
			return -1 if own.to_int() < compared.to_int() else 1
		if own_numeric != other_numeric:
			return -1 if own_numeric else 1
		return -1 if own < compared else 1
	if own_identifiers.size() == other_identifiers.size():
		return 0
	return -1 if own_identifiers.size() < other_identifiers.size() else 1
