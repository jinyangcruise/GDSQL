class_name GDSQLSaveContentCompatibilityTest
extends GdUnitTestSuite

var _test_root: String
var _test_index := 0


func before_test() -> void:
	_test_index += 1
	_test_root = create_temp_dir("gdsql_save_content_%d" % _test_index)


func test_save_manifest_round_trips_the_active_package_set() -> void:
	var active := _cache_manifest(
		[
			_package(&"base.game", "1.0.0", "base_hash"),
			_package(&"mod.items", "2.1.0", "mod_hash"),
		],
	)
	var expected := GDSQLSaveContentManifest.from_cache_manifest(active)
	var store := GDSQLConfigFileSaveContentManifestStore.new(_test_root)

	var saved := store.save_manifest(expected)
	var loaded := store.load_manifest()
	var restored := loaded.get_value() as GDSQLSaveContentManifest

	assert_bool(saved.is_successful()).is_true()
	assert_bool(loaded.is_successful()).is_true()
	assert_str(String(restored.effective_database_name)).is_equal("effective_content")
	assert_int(restored.packages.size()).is_equal(2)
	assert_str(String(restored.packages[1].package_id)).is_equal("mod.items")
	assert_str(restored.packages[1].content_hash).is_equal("mod_hash")


func test_inspector_reports_missing_changed_and_added_packages() -> void:
	var expected := GDSQLSaveContentManifest.new(
		&"effective_content",
		[
			_package(&"base.game", "1.0.0", "old_base"),
			_package(&"mod.items", "2.1.0", "mod_hash"),
		],
	)
	var active := _cache_manifest(
		[
			_package(&"base.game", "1.1.0", "new_base"),
			_package(&"mod.cosmetics", "1.0.0", "cosmetic_hash"),
		],
	)

	var report := GDSQLSaveContentCompatibilityInspector.inspect(expected, active)

	assert_int(report.status).is_equal(
		GDSQLSaveContentCompatibilityReport.Status.MISSING_PACKAGES,
	)
	assert_str(String(report.missing_packages[0].package_id)).is_equal("mod.items")
	assert_str(String(report.changed_packages[0].active.package_id)).is_equal("base.game")
	assert_str(String(report.additional_packages[0].package_id)).is_equal("mod.cosmetics")
	assert_bool(report.can_resolve_expected_packages()).is_false()
	assert_bool(report.requires_policy_decision()).is_true()


func test_untracked_save_and_exact_match_have_distinct_status() -> void:
	var active := _cache_manifest([_package(&"base.game", "1.0.0", "base_hash")])
	var untracked := GDSQLSaveContentCompatibilityInspector.inspect(null, active)
	var exact := GDSQLSaveContentCompatibilityInspector.inspect(
		GDSQLSaveContentManifest.from_cache_manifest(active),
		active,
	)

	assert_int(untracked.status).is_equal(
		GDSQLSaveContentCompatibilityReport.Status.UNTRACKED,
	)
	assert_bool(untracked.requires_policy_decision()).is_true()
	assert_int(exact.status).is_equal(GDSQLSaveContentCompatibilityReport.Status.EXACT)
	assert_bool(exact.can_resolve_expected_packages()).is_true()
	assert_bool(exact.requires_policy_decision()).is_false()


func test_load_order_change_requires_a_policy_decision() -> void:
	var base := _package(&"base.game", "1.0.0", "base_hash")
	var mod := _package(&"mod.items", "1.0.0", "mod_hash")
	var expected := GDSQLSaveContentManifest.new(&"effective_content", [base, mod])
	var active := _cache_manifest([mod, base])

	var report := GDSQLSaveContentCompatibilityInspector.inspect(expected, active)

	assert_int(report.status).is_equal(GDSQLSaveContentCompatibilityReport.Status.CHANGED)
	assert_bool(report.load_order_changed).is_true()
	assert_bool(report.can_resolve_expected_packages()).is_true()
	assert_bool(report.requires_policy_decision()).is_true()


func _cache_manifest(
		packages: Array[GDSQLContentPackageFingerprint],
) -> GDSQLContentCacheManifest:
	return GDSQLContentCacheManifest.new(
		&"game_content",
		&"effective_content",
		packages,
	)


func _package(
		package_id: StringName,
		version: String,
		content_hash: String,
) -> GDSQLContentPackageFingerprint:
	return GDSQLContentPackageFingerprint.new(package_id, version, content_hash)
