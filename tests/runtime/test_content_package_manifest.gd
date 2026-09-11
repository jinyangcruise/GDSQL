class_name GDSQLContentPackageManifestTest
extends GdUnitTestSuite

var _package_root: String
var _test_index := 0


func before_test() -> void:
	_test_index += 1
	_package_root = create_temp_dir("gdsql_content_package_%d" % _test_index)


func test_validator_accepts_a_typed_mod_manifest() -> void:
	var dependencies: Array[GDSQLContentPackageDependency] = [
		GDSQLContentPackageDependency.new(&"base.game", ">=1.0.0"),
	]
	var after: Array[StringName] = [&"base.game"]
	var manifest := GDSQLContentPackageManifest.new(
		&"expanded_arsenal",
		"Expanded Arsenal",
		"1.2.0-beta.1+release",
		GDSQLContentPackageKind.Kind.MOD,
		20,
		"data",
		"assets",
		dependencies,
		after,
	)

	var result := GDSQLContentPackageManifestValidator.new().validate(manifest)

	assert_bool(result.is_successful()).is_true()
	assert_object(result.get_value()).is_same(manifest)


func test_validator_reports_all_manifest_local_conflicts() -> void:
	var dependencies: Array[GDSQLContentPackageDependency] = [
		GDSQLContentPackageDependency.new(&"Bad Id", ""),
		GDSQLContentPackageDependency.new(&"broken", "*"),
		GDSQLContentPackageDependency.new(&"broken", "*"),
	]
	var after: Array[StringName] = [&"broken", &"broken"]
	var before: Array[StringName] = [&"broken"]
	var manifest := GDSQLContentPackageManifest.new(
		&"broken",
		"",
		"01.0",
		99,
		0,
		"../data",
		"user://assets",
		dependencies,
		after,
		before,
	)

	var result := GDSQLContentPackageManifestValidator.new().validate(manifest)
	var codes := _diagnostic_codes(result)

	assert_bool(result.is_successful()).is_false()
	assert_array(codes).contains(
		[
			"GDSQL_CONTENT_PACKAGE_NAME_REQUIRED",
			"GDSQL_CONTENT_PACKAGE_VERSION_INVALID",
			"GDSQL_CONTENT_PACKAGE_KIND_INVALID",
			"GDSQL_CONTENT_PACKAGE_PATH_INVALID",
			"GDSQL_CONTENT_PACKAGE_DEPENDENCY_INVALID",
			"GDSQL_CONTENT_PACKAGE_SELF_DEPENDENCY",
			"GDSQL_CONTENT_PACKAGE_DEPENDENCY_DUPLICATE",
			"GDSQL_CONTENT_PACKAGE_SELF_ORDER",
			"GDSQL_CONTENT_PACKAGE_ORDER_DUPLICATE",
			"GDSQL_CONTENT_PACKAGE_ORDER_CONFLICT",
		],
	)


func test_config_file_store_decodes_readable_manifest_sections() -> void:
	var config := ConfigFile.new()
	config.set_value("package", "id", "expanded_arsenal")
	config.set_value("package", "name", "Expanded Arsenal")
	config.set_value("package", "version", "1.2.0")
	config.set_value("package", "kind", "mod")
	config.set_value("package", "priority", 20)
	config.set_value("dependencies", "shared_items", ">=2.0.0")
	config.set_value("dependencies", "base.game", "^1.0.0")
	config.set_value("load_order", "after", PackedStringArray(["base.game"]))
	config.set_value("load_order", "before", ["late_balance"])
	assert_int(config.save(_package_root.path_join("manifest.cfg"))).is_equal(OK)

	var loaded := GDSQLConfigFileContentPackageManifestStore.new() \
			.load_manifest(_package_root)
	var manifest := loaded.get_value() as GDSQLContentPackageManifest

	assert_bool(loaded.is_successful()).is_true()
	assert_str(String(manifest.package_id)).is_equal("expanded_arsenal")
	assert_str(manifest.display_name).is_equal("Expanded Arsenal")
	assert_str(manifest.version).is_equal("1.2.0")
	assert_int(manifest.kind).is_equal(GDSQLContentPackageKind.Kind.MOD)
	assert_int(manifest.priority).is_equal(20)
	assert_str(String(manifest.dependencies[0].package_id)).is_equal("base.game")
	assert_str(String(manifest.dependencies[1].package_id)).is_equal("shared_items")
	assert_array(manifest.load_after).contains_exactly([&"base.game"])
	assert_array(manifest.load_before).contains_exactly([&"late_balance"])


func test_config_file_store_rejects_missing_and_malformed_manifests() -> void:
	var store := GDSQLConfigFileContentPackageManifestStore.new()
	var missing := store.load_manifest(_package_root)
	var config := ConfigFile.new()
	config.set_value("package", "id", "broken")
	config.set_value("package", "name", "Broken")
	config.set_value("package", "version", "1.0.0")
	config.set_value("package", "kind", "mod")
	config.set_value("dependencies", "base.game", 3)
	config.set_value("load_order", "after", "base.game")
	assert_int(config.save(_package_root.path_join("manifest.cfg"))).is_equal(OK)

	var malformed := store.load_manifest(_package_root)
	var codes := _diagnostic_codes(malformed)

	assert_str(String(missing.diagnostics.entries[0].code)).is_equal(
		"GDSQL_CONTENT_PACKAGE_MANIFEST_NOT_FOUND",
	)
	assert_bool(malformed.is_successful()).is_false()
	assert_array(codes).contains(
		[
			"GDSQL_CONTENT_PACKAGE_DEPENDENCY_TYPE_INVALID",
			"GDSQL_CONTENT_PACKAGE_ORDER_TYPE_INVALID",
		],
	)


func _diagnostic_codes(result: GDSQLOperationResult) -> Array[String]:
	var codes: Array[String] = []
	for diagnostic in result.diagnostics.entries:
		codes.append(String(diagnostic.code))
	return codes
