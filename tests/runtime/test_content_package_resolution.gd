class_name GDSQLContentPackageResolutionTest
extends GdUnitTestSuite

var _test_root: String
var _test_index := 0


func before_test() -> void:
	_test_index += 1
	_test_root = create_temp_dir("gdsql_content_resolution_%d" % _test_index)


func test_directory_discovery_supports_direct_and_nested_content_packages() -> void:
	var base_root := _test_root.path_join("base/content")
	var mods_root := _test_root.path_join("mods")
	_write_manifest(base_root, &"base.game", "base", "1.0.0")
	_write_manifest(mods_root.path_join("zeta"), &"zeta", "mod", "1.0.0")
	_write_manifest(mods_root.path_join("alpha/content"), &"alpha", "dlc", "2.0.0")
	DirAccess.make_dir_recursive_absolute(mods_root.path_join("ignored"))

	var discovered := GDSQLConfigFileContentPackageDiscovery.new().discover(
		base_root,
		[mods_root, _test_root.path_join("missing")],
	)
	var packages := discovered.get_value() as Array[GDSQLContentPackageSource]

	assert_bool(discovered.is_successful()).is_true()
	assert_array(_package_ids(packages)).contains_exactly(
		[
			&"base.game",
			&"alpha",
			&"zeta",
		],
	)
	assert_str(packages[1].get_data_root()).is_equal(
		mods_root.path_join("alpha/content/data"),
	)
	assert_str(String(discovered.diagnostics.entries[0].code)).is_equal(
		"GDSQL_CONTENT_PACKAGE_CONTAINER_UNAVAILABLE",
	)


func test_base_only_resolution_does_not_validate_disabled_package_dependencies() -> void:
	var packages: Array[GDSQLContentPackageSource] = [
		_source(&"base.game", GDSQLContentPackageKind.Kind.BASE_GAME, "1.0.0"),
		_source(
			&"optional_mod",
			GDSQLContentPackageKind.Kind.MOD,
			"1.0.0",
			0,
			{ &"missing_mod": "*" },
		),
	]

	var resolved := GDSQLContentPackageResolver.new().resolve(packages)

	assert_bool(resolved.is_successful()).is_true()
	assert_array(_package_ids(resolved.ordered_packages)).contains_exactly([&"base.game"])


func test_resolver_combines_dependencies_order_declarations_and_priority() -> void:
	var packages: Array[GDSQLContentPackageSource] = [
		_source(&"base.game", GDSQLContentPackageKind.Kind.BASE_GAME, "1.4.0"),
		_source(&"shared", GDSQLContentPackageKind.Kind.DLC, "2.1.0", 20),
		_source(&"arsenal", GDSQLContentPackageKind.Kind.MOD, "1.0.0", 10),
		_source(
			&"balance",
			GDSQLContentPackageKind.Kind.MOD,
			"1.0.0",
			5,
			{ &"base.game": "^1.2.0" },
			[&"shared"],
		),
	]

	var resolved := GDSQLContentPackageResolver.new().resolve(
		packages,
		[&"balance", &"shared", &"arsenal"],
	)

	assert_bool(resolved.is_successful()).is_true()
	assert_array(_package_ids(resolved.ordered_packages)).contains_exactly(
		[
			&"base.game",
			&"arsenal",
			&"shared",
			&"balance",
		],
	)
	assert_object(resolved.get_package(&"balance")).is_not_null()


func test_resolver_reports_missing_and_incompatible_dependencies() -> void:
	var packages: Array[GDSQLContentPackageSource] = [
		_source(&"base.game", GDSQLContentPackageKind.Kind.BASE_GAME, "1.0.0"),
		_source(
			&"future_mod",
			GDSQLContentPackageKind.Kind.MOD,
			"1.0.0",
			0,
			{ &"base.game": ">=2.0.0", &"library": "*" },
		),
	]

	var resolved := GDSQLContentPackageResolver.new().resolve(
		packages,
		[&"future_mod"],
	)
	var codes := _diagnostic_codes(resolved)

	assert_bool(resolved.is_successful()).is_false()
	assert_array(codes).contains(
		[
			"GDSQL_CONTENT_PACKAGE_DEPENDENCY_VERSION_MISMATCH",
			"GDSQL_CONTENT_PACKAGE_DEPENDENCY_MISSING",
		],
	)


func test_resolver_reports_unknown_enabled_packages_and_order_cycles() -> void:
	var packages: Array[GDSQLContentPackageSource] = [
		_source(&"base.game", GDSQLContentPackageKind.Kind.BASE_GAME, "1.0.0"),
		_source(&"alpha", GDSQLContentPackageKind.Kind.MOD, "1.0.0", 0, { }, [&"beta"]),
		_source(&"beta", GDSQLContentPackageKind.Kind.MOD, "1.0.0", 0, { }, [&"alpha"]),
	]
	var resolver := GDSQLContentPackageResolver.new()

	var unknown := resolver.resolve(packages, [&"missing"])
	var cycle := resolver.resolve(packages, [&"alpha", &"beta"])

	assert_str(String(unknown.diagnostics.entries[0].code)).is_equal(
		"GDSQL_CONTENT_PACKAGE_ENABLED_NOT_FOUND",
	)
	assert_str(String(cycle.diagnostics.entries[0].code)).is_equal(
		"GDSQL_CONTENT_PACKAGE_ORDER_CYCLE",
	)


func test_semantic_version_constraints_use_semver_precedence() -> void:
	var caret := GDSQLSemanticVersionConstraint.matches("1.9.0", "^1.2.0")
	var next_major := GDSQLSemanticVersionConstraint.matches("2.0.0", "^1.2.0")
	var range := GDSQLSemanticVersionConstraint.matches(
		"1.5.0",
		">=1.2.0 <2.0.0",
	)
	var invalid_constraint := GDSQLSemanticVersionConstraint.matches("1.0.0", "banana")
	var invalid_prerelease := GDSQLSemanticVersion.parse("1.0.0-beta.01")
	var prerelease := GDSQLSemanticVersion.parse("1.0.0-beta.2").get_value() \
			as GDSQLSemanticVersion
	var release := GDSQLSemanticVersion.parse("1.0.0").get_value() \
			as GDSQLSemanticVersion

	assert_bool(caret.get_value()).is_true()
	assert_bool(next_major.get_value()).is_false()
	assert_bool(range.get_value()).is_true()
	assert_bool(invalid_constraint.is_successful()).is_false()
	assert_bool(invalid_prerelease.is_successful()).is_false()
	assert_int(prerelease.compare(release)).is_less(0)


func _source(
		package_id: StringName,
		kind: int,
		version: String,
		priority: int = 0,
		dependencies: Dictionary = { },
		load_after: Array[StringName] = [],
		load_before: Array[StringName] = [],
) -> GDSQLContentPackageSource:
	var typed_dependencies: Array[GDSQLContentPackageDependency] = []
	for dependency_id in dependencies:
		typed_dependencies.append(
			GDSQLContentPackageDependency.new(
				StringName(dependency_id),
				String(dependencies[dependency_id]),
			),
		)
	return GDSQLContentPackageSource.new(
		"res://packages/%s" % package_id,
		GDSQLContentPackageManifest.new(
			package_id,
			String(package_id),
			version,
			kind,
			priority,
			"data",
			"assets",
			typed_dependencies,
			load_after,
			load_before,
		),
	)


func _write_manifest(
		root: String,
		package_id: StringName,
		kind: String,
		version: String,
) -> void:
	assert_int(DirAccess.make_dir_recursive_absolute(root)).is_equal(OK)
	var config := ConfigFile.new()
	config.set_value("package", "id", package_id)
	config.set_value("package", "name", String(package_id))
	config.set_value("package", "version", version)
	config.set_value("package", "kind", kind)
	assert_int(config.save(root.path_join("manifest.cfg"))).is_equal(OK)


func _package_ids(packages: Array[GDSQLContentPackageSource]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for package in packages:
		ids.append(package.manifest.package_id)
	return ids


func _diagnostic_codes(result: GDSQLOperationResult) -> Array[String]:
	var codes: Array[String] = []
	for diagnostic in result.diagnostics.entries:
		codes.append(String(diagnostic.code))
	return codes
