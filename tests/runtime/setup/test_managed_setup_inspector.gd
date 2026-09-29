class_name GDSQLManagedSetupInspectorTest
extends GdUnitTestSuite


func test_managed_report_orders_the_complete_setup_path() -> void:
	var source := _base_source()
	var inspection := _base_inspection(2)
	var cache := GDSQLContentCacheManifest.new(
		&"content",
		&"effective_content",
		[GDSQLContentPackageFingerprint.new(&"base.game", "1.0.0", "hash")],
	)

	var report := GDSQLManagedSetupInspector.inspect_editor(
		source,
		inspection,
		cache,
		_save_snapshot(),
		1,
		true,
	)

	assert_bool(report.is_ready()).is_true()
	assert_int(report.checks.size()).is_equal(7)
	assert_array(_check_ids(report)).contains_exactly(
		[
			&"base_package",
			&"base_table",
			&"base_row",
			&"effective_cache",
			&"active_save",
			&"model_binding",
			&"runtime_adapter",
		],
	)


func test_managed_report_points_to_base_package_setup_first() -> void:
	var report := GDSQLManagedSetupInspector.inspect_editor(
		null,
		null,
		null,
		GDSQLDatabaseRegistrySnapshot.new(),
		0,
		false,
	)

	assert_bool(report.is_ready()).is_false()
	assert_str(String(report.get_next_incomplete().id)).is_equal("base_package")
	assert_str(String(report.get_next_incomplete().next_action)).is_equal(
		"open_managed_content",
	)


func _base_source() -> GDSQLContentPackageSource:
	return GDSQLContentPackageSource.new(
		"res://content/base",
		GDSQLContentPackageManifest.new(
			&"base.game",
			"Base Game",
			"1.0.0",
			GDSQLContentPackageKind.Kind.BASE_GAME,
		),
	)


func _base_inspection(rows: int) -> GDSQLDatabaseInspection:
	var inspection := GDSQLDatabaseInspection.new(
		GDSQLDatabaseRegistration.new(
			&"base_content",
			&"content",
			"res://content/base/data",
		),
		true,
	)
	inspection.tables.append(GDSQLTableInspection.new(&"items", true, true, rows))
	return inspection


func _save_snapshot() -> GDSQLDatabaseRegistrySnapshot:
	var snapshot := GDSQLDatabaseRegistrySnapshot.new()
	snapshot.registrations.append(
		GDSQLDatabaseRegistration.new(
			&"save_1",
			&"save_1",
			"user://gdsql/saves/save_1",
		),
	)
	snapshot.role_bindings.append(
		GDSQLDatabaseRoleBinding.new(GDSQLDatabaseRegistry.SAVE_ROLE, &"save_1"),
	)
	return snapshot


func _check_ids(report: GDSQLManagedSetupReport) -> Array[StringName]:
	var ids: Array[StringName] = []
	for check in report.checks:
		ids.append(check.id)
	return ids
