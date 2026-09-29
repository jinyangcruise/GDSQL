class_name GDSQLSemanticVersionConstraint
extends RefCounted
## Evaluates common exact, comparator, caret, tilde, and AND constraints.

static func matches(version_text: String, constraint: String) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	var parsed_version := GDSQLSemanticVersion.parse(version_text)
	result.diagnostics.merge(parsed_version.diagnostics)
	if not result.is_successful():
		return result
	var version := parsed_version.get_value() as GDSQLSemanticVersion
	var normalized := constraint.strip_edges().replace(",", " ")
	if normalized.is_empty():
		return _error(constraint)
	result.value = true
	for clause in normalized.split(" ", false):
		var evaluated := _matches_clause(version, clause)
		result.diagnostics.merge(evaluated.diagnostics)
		if not evaluated.is_successful():
			result.value = false
			return result
		if not bool(evaluated.get_value()):
			result.value = false
	return result


static func _matches_clause(
		version: GDSQLSemanticVersion,
		clause: String,
) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if clause == "*":
		result.value = true
		return result
	var operator := "="
	var target_text := clause
	for candidate in [">=", "<=", ">", "<", "=", "^", "~"]:
		if clause.begins_with(candidate):
			operator = candidate
			target_text = clause.trim_prefix(candidate)
			break
	var parsed_target := GDSQLSemanticVersion.parse(target_text)
	if not parsed_target.is_successful():
		return _error(clause)
	var target := parsed_target.get_value() as GDSQLSemanticVersion
	var comparison := version.compare(target)
	match operator:
		"=":
			result.value = comparison == 0
		">=":
			result.value = comparison >= 0
		"<=":
			result.value = comparison <= 0
		">":
			result.value = comparison > 0
		"<":
			result.value = comparison < 0
		"^":
			result.value = comparison >= 0 and version.compare(_caret_upper(target)) < 0
		"~":
			result.value = comparison >= 0 \
					and version.compare(GDSQLSemanticVersion.new(target.major, target.minor + 1)) < 0
	return result


static func _caret_upper(version: GDSQLSemanticVersion) -> GDSQLSemanticVersion:
	if version.major > 0:
		return GDSQLSemanticVersion.new(version.major + 1)
	if version.minor > 0:
		return GDSQLSemanticVersion.new(0, version.minor + 1)
	return GDSQLSemanticVersion.new(0, 0, version.patch + 1)


static func _error(constraint: String) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.add_diagnostic(
		GDSQLQueryDiagnostic.new(
			&"GDSQL_SEMANTIC_VERSION_CONSTRAINT_INVALID",
			"'%s' is not a supported semantic-version constraint." % constraint,
		),
	)
	return result
