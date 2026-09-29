class_name GDSQLContentPackageManifestValidator
extends RefCounted
## Validates manifest-local identity, paths, dependencies, and order declarations.

func validate(manifest: GDSQLContentPackageManifest) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if manifest == null:
		return _error(
			&"GDSQL_CONTENT_PACKAGE_MANIFEST_REQUIRED",
			"A content package manifest is required.",
		)
	if not _is_valid_package_id(manifest.package_id):
		_add_error(
			result,
			&"GDSQL_CONTENT_PACKAGE_ID_INVALID",
			"Package id '%s' must use lowercase letters, numbers, '.', '_' or '-'." \
					% manifest.package_id,
		)
	if manifest.display_name.strip_edges().is_empty():
		_add_error(
			result,
			&"GDSQL_CONTENT_PACKAGE_NAME_REQUIRED",
			"Package '%s' requires a display name." % manifest.package_id,
		)
	if not GDSQLSemanticVersion.parse(manifest.version).is_successful():
		_add_error(
			result,
			&"GDSQL_CONTENT_PACKAGE_VERSION_INVALID",
			"Package '%s' requires a semantic version such as 1.0.0." % manifest.package_id,
		)
	if not GDSQLContentPackageKind.is_valid(manifest.kind):
		_add_error(
			result,
			&"GDSQL_CONTENT_PACKAGE_KIND_INVALID",
			"Package '%s' must declare kind 'base', 'dlc', or 'mod'." % manifest.package_id,
		)
	_validate_relative_path(result, manifest.package_id, "data", manifest.data_path)
	_validate_relative_path(result, manifest.package_id, "assets", manifest.assets_path)
	_validate_dependencies(result, manifest)
	_validate_order(result, manifest)
	if result.is_successful():
		result.value = manifest
	return result


func _validate_dependencies(
		result: GDSQLOperationResult,
		manifest: GDSQLContentPackageManifest,
) -> void:
	var seen: Dictionary[StringName, bool] = { }
	for dependency in manifest.dependencies:
		if dependency == null or not _is_valid_package_id(dependency.package_id):
			_add_error(
				result,
				&"GDSQL_CONTENT_PACKAGE_DEPENDENCY_INVALID",
				"Package '%s' contains an invalid dependency id." % manifest.package_id,
			)
			continue
		if dependency.package_id == manifest.package_id:
			_add_error(
				result,
				&"GDSQL_CONTENT_PACKAGE_SELF_DEPENDENCY",
				"Package '%s' cannot depend on itself." % manifest.package_id,
			)
		if seen.has(dependency.package_id):
			_add_error(
				result,
				&"GDSQL_CONTENT_PACKAGE_DEPENDENCY_DUPLICATE",
				"Package '%s' declares dependency '%s' more than once." % [
					manifest.package_id,
					dependency.package_id,
				],
			)
		seen[dependency.package_id] = true
		if dependency.version_constraint.strip_edges().is_empty():
			_add_error(
				result,
				&"GDSQL_CONTENT_PACKAGE_DEPENDENCY_VERSION_REQUIRED",
				"Dependency '%s' requires a version constraint." % dependency.package_id,
			)
		elif not GDSQLSemanticVersionConstraint.matches(
			manifest.version,
			dependency.version_constraint,
		).is_successful():
			_add_error(
				result,
				&"GDSQL_CONTENT_PACKAGE_DEPENDENCY_CONSTRAINT_INVALID",
				"Dependency '%s' uses unsupported version constraint '%s'." % [
					dependency.package_id,
					dependency.version_constraint,
				],
			)


func _validate_order(
		result: GDSQLOperationResult,
		manifest: GDSQLContentPackageManifest,
) -> void:
	var after := _validate_order_list(result, manifest, manifest.load_after, "after")
	var before := _validate_order_list(result, manifest, manifest.load_before, "before")
	for package_id in after:
		if before.has(package_id):
			_add_error(
				result,
				&"GDSQL_CONTENT_PACKAGE_ORDER_CONFLICT",
				"Package '%s' cannot load both before and after '%s'." % [
					manifest.package_id,
					package_id,
				],
			)


func _validate_order_list(
		result: GDSQLOperationResult,
		manifest: GDSQLContentPackageManifest,
		package_ids: Array[StringName],
		relation: String,
) -> Dictionary[StringName, bool]:
	var seen: Dictionary[StringName, bool] = { }
	for package_id in package_ids:
		if not _is_valid_package_id(package_id):
			_add_error(
				result,
				&"GDSQL_CONTENT_PACKAGE_ORDER_ID_INVALID",
				"Package '%s' contains an invalid load-%s id." % [
					manifest.package_id,
					relation,
				],
			)
			continue
		if package_id == manifest.package_id:
			_add_error(
				result,
				&"GDSQL_CONTENT_PACKAGE_SELF_ORDER",
				"Package '%s' cannot load %s itself." % [manifest.package_id, relation],
			)
		if seen.has(package_id):
			_add_error(
				result,
				&"GDSQL_CONTENT_PACKAGE_ORDER_DUPLICATE",
				"Package '%s' repeats '%s' in load-%s." % [
					manifest.package_id,
					package_id,
					relation,
				],
			)
		seen[package_id] = true
	return seen


func _validate_relative_path(
		result: GDSQLOperationResult,
		package_id: StringName,
		field_name: String,
		path: String,
) -> void:
	var normalized := path.strip_edges().replace("\\", "/")
	if normalized.is_empty() \
			or normalized.is_absolute_path() \
			or normalized.begins_with("res://") \
			or normalized.begins_with("user://") \
			or ".." in normalized.split("/", false):
		_add_error(
			result,
			&"GDSQL_CONTENT_PACKAGE_PATH_INVALID",
			"Package '%s' %s path must stay relative to its package root." % [
				package_id,
				field_name,
			],
		)


func _is_valid_package_id(package_id: StringName) -> bool:
	var value := String(package_id)
	if value.is_empty():
		return false
	for index in value.length():
		var code := value.unicode_at(index)
		var valid := (code >= 97 and code <= 122) \
				or (code >= 48 and code <= 57) \
				or code in [45, 46, 95]
		if not valid:
			return false
	return value.unicode_at(0) not in [45, 46]


func _add_error(
		result: GDSQLOperationResult,
		code: StringName,
		message: String,
) -> void:
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))


func _error(code: StringName, message: String) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	_add_error(result, code, message)
	return result
