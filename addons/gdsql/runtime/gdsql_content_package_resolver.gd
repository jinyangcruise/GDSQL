class_name GDSQLContentPackageResolver
extends RefCounted
## Selects enabled packages and topologically orders their precedence graph.

var _manifest_validator: GDSQLContentPackageManifestValidator


func _init(validator: GDSQLContentPackageManifestValidator = null) -> void:
	_manifest_validator = validator if validator != null else GDSQLContentPackageManifestValidator.new()


func resolve(
		discovered_packages: Array[GDSQLContentPackageSource],
		enabled_package_ids: Array[StringName] = [],
) -> GDSQLContentPackageResolutionResult:
	var result := GDSQLContentPackageResolutionResult.new()
	var discovered: Dictionary[StringName, GDSQLContentPackageSource] = { }
	var base_packages: Array[GDSQLContentPackageSource] = []
	for package in discovered_packages:
		if package == null or package.manifest == null or package.package_root.is_empty():
			_add_error(
				result,
				&"GDSQL_CONTENT_PACKAGE_SOURCE_INVALID",
				"A discovered package is missing its root or manifest.",
			)
			continue
		var validated := _manifest_validator.validate(package.manifest)
		result.diagnostics.merge(validated.diagnostics)
		var package_id := package.manifest.package_id
		if discovered.has(package_id):
			_add_error(
				result,
				&"GDSQL_CONTENT_PACKAGE_ID_DUPLICATE",
				"Package id '%s' is supplied by more than one source." % package_id,
			)
			continue
		discovered[package_id] = package
		if package.manifest.kind == GDSQLContentPackageKind.Kind.BASE_GAME:
			base_packages.append(package)
	if base_packages.size() != 1:
		_add_error(
			result,
			&"GDSQL_CONTENT_BASE_PACKAGE_COUNT_INVALID",
			"Exactly one base package is required; discovered %d." % base_packages.size(),
		)
	if not result.is_successful():
		return result
	var selected: Dictionary[StringName, GDSQLContentPackageSource] = { }
	var base := base_packages[0]
	selected[base.manifest.package_id] = base
	var enabled_seen: Dictionary[StringName, bool] = { }
	for package_id in enabled_package_ids:
		if enabled_seen.has(package_id):
			_add_error(
				result,
				&"GDSQL_CONTENT_PACKAGE_ENABLED_DUPLICATE",
				"Enabled package '%s' is listed more than once." % package_id,
			)
			continue
		enabled_seen[package_id] = true
		if not discovered.has(package_id):
			_add_error(
				result,
				&"GDSQL_CONTENT_PACKAGE_ENABLED_NOT_FOUND",
				"Enabled package '%s' was not discovered." % package_id,
			)
			continue
		selected[package_id] = discovered[package_id]
	_validate_dependencies(selected, result)
	if not result.is_successful():
		return result
	var ordered := _topological_order(selected, result)
	if result.is_successful():
		result.set_packages(ordered)
	return result


func _validate_dependencies(
		selected: Dictionary[StringName, GDSQLContentPackageSource],
		result: GDSQLContentPackageResolutionResult,
) -> void:
	for package_id in selected:
		var package := selected[package_id]
		for dependency in package.manifest.dependencies:
			if not selected.has(dependency.package_id):
				_add_error(
					result,
					&"GDSQL_CONTENT_PACKAGE_DEPENDENCY_MISSING",
					"Package '%s' requires enabled package '%s' (%s)." % [
						package_id,
						dependency.package_id,
						dependency.version_constraint,
					],
				)
				continue
			var dependency_package := selected[dependency.package_id]
			var compatible := GDSQLSemanticVersionConstraint.matches(
				dependency_package.manifest.version,
				dependency.version_constraint,
			)
			result.diagnostics.merge(compatible.diagnostics)
			if compatible.is_successful() and not bool(compatible.get_value()):
				_add_error(
					result,
					&"GDSQL_CONTENT_PACKAGE_DEPENDENCY_VERSION_MISMATCH",
					"Package '%s' requires '%s' %s, but %s is selected." % [
						package_id,
						dependency.package_id,
						dependency.version_constraint,
						dependency_package.manifest.version,
					],
				)


func _topological_order(
		selected: Dictionary[StringName, GDSQLContentPackageSource],
		result: GDSQLContentPackageResolutionResult,
) -> Array[GDSQLContentPackageSource]:
	var outgoing: Dictionary[StringName, Array] = { }
	var incoming: Dictionary[StringName, int] = { }
	for package_id in selected:
		outgoing[package_id] = []
		incoming[package_id] = 0
	var base_id := &""
	for package_id in selected:
		var package := selected[package_id]
		if package.manifest.kind == GDSQLContentPackageKind.Kind.BASE_GAME:
			base_id = package_id
		for dependency in package.manifest.dependencies:
			_add_edge(dependency.package_id, package_id, outgoing, incoming)
		for previous_id in package.manifest.load_after:
			if selected.has(previous_id):
				_add_edge(previous_id, package_id, outgoing, incoming)
		for next_id in package.manifest.load_before:
			if selected.has(next_id):
				_add_edge(package_id, next_id, outgoing, incoming)
	for package_id in selected:
		if package_id != base_id:
			_add_edge(base_id, package_id, outgoing, incoming)
	var emitted: Dictionary[StringName, bool] = { }
	var ordered: Array[GDSQLContentPackageSource] = []
	while ordered.size() < selected.size():
		var available: Array[GDSQLContentPackageSource] = []
		for package_id in selected:
			if not emitted.has(package_id) and incoming[package_id] == 0:
				available.append(selected[package_id])
		if available.is_empty():
			var remaining: Array[String] = []
			for package_id in selected:
				if not emitted.has(package_id):
					remaining.append(String(package_id))
			remaining.sort()
			_add_error(
				result,
				&"GDSQL_CONTENT_PACKAGE_ORDER_CYCLE",
				"Package load order contains a cycle involving: %s." % ", ".join(remaining),
			)
			return []
		available.sort_custom(_package_precedes)
		var next := available[0]
		var next_id := next.manifest.package_id
		emitted[next_id] = true
		ordered.append(next)
		for dependent_id in outgoing[next_id]:
			incoming[dependent_id] -= 1
	return ordered


func _add_edge(
		before: StringName,
		after: StringName,
		outgoing: Dictionary[StringName, Array],
		incoming: Dictionary[StringName, int],
) -> void:
	var targets: Array = outgoing[before]
	if after in targets:
		return
	targets.append(after)
	outgoing[before] = targets
	incoming[after] += 1


func _package_precedes(
		left: GDSQLContentPackageSource,
		right: GDSQLContentPackageSource,
) -> bool:
	if left.manifest.priority != right.manifest.priority:
		return left.manifest.priority < right.manifest.priority
	return String(left.manifest.package_id) < String(right.manifest.package_id)


func _add_error(
		result: GDSQLContentPackageResolutionResult,
		code: StringName,
		message: String,
) -> void:
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
