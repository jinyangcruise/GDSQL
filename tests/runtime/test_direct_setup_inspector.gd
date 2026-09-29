class_name GDSQLDirectSetupInspectorTest
extends GdUnitTestSuite

func test_runtime_report_identifies_missing_required_roles() -> void:
	var report := GDSQLDirectSetupInspector.inspect_runtime(
		GDSQLDatabaseRegistrySnapshot.new(),
	)

	assert_bool(report.is_ready()).is_false()
	assert_str(String(report.get_next_incomplete().id)).is_equal("content_database")
	assert_int(report.diagnostics.size()).is_equal(2)
	assert_int(report.diagnostics.entries[0].severity).is_equal(
		GDSQLQueryDiagnostic.Severity.WARNING,
	)


func test_runtime_report_accepts_safe_content_and_save_bindings() -> void:
	var snapshot := _direct_snapshot()

	var report := GDSQLDirectSetupInspector.inspect_runtime(snapshot)

	assert_bool(report.is_ready()).is_true()
	assert_bool(report.diagnostics.is_empty()).is_true()
	assert_int(report.checks.size()).is_equal(2)


func test_editor_report_tracks_content_progress_and_runtime_adapter() -> void:
	var snapshot := _direct_snapshot()
	var inspections: Array[GDSQLDatabaseInspection] = [
		_inspection(snapshot.registrations[0], 3),
		_inspection(snapshot.registrations[1], 0),
	]

	var report := GDSQLDirectSetupInspector.inspect_editor(
		snapshot,
		inspections,
		1,
		false,
	)

	assert_int(report.checks.size()).is_equal(6)
	assert_str(String(report.get_next_incomplete().id)).is_equal("runtime_adapter")
	assert_str(String(report.get_next_incomplete().next_action)).is_equal(
		"install_runtime",
	)


func test_editor_report_does_not_count_unbound_databases_as_content() -> void:
	var snapshot := GDSQLDatabaseRegistrySnapshot.new()
	var unrelated := GDSQLDatabaseRegistration.new(
		&"settings",
		&"settings",
		"user://gdsql/settings",
	)
	snapshot.registrations.append(unrelated)
	var inspections: Array[GDSQLDatabaseInspection] = [_inspection(unrelated, 2)]

	var report := GDSQLDirectSetupInspector.inspect_editor(
		snapshot,
		inspections,
		1,
		true,
	)

	assert_bool(report.get_check(GDSQLDirectSetupInspector.CONTENT_DATABASE).complete).is_false()
	assert_bool(report.get_check(GDSQLDirectSetupInspector.CONTENT_TABLE).complete).is_false()
	assert_bool(report.get_check(GDSQLDirectSetupInspector.CONTENT_ROW).complete).is_false()


func test_runtime_report_explains_unsafe_roots_and_unavailable_backends() -> void:
	var snapshot := _direct_snapshot()
	snapshot.registrations[0].data_root = "user://content"
	snapshot.registrations[1].storage_backend_id = GDSQLStorageBackendIds.BUFFERED

	var report := GDSQLDirectSetupInspector.inspect_runtime(snapshot)

	assert_str(report.checks[0].detail).contains("res://")
	assert_str(report.checks[1].detail).contains("unavailable storage backend")


func _direct_snapshot() -> GDSQLDatabaseRegistrySnapshot:
	var snapshot := GDSQLDatabaseRegistrySnapshot.new()
	snapshot.registrations.assign(
		[
			GDSQLDatabaseRegistration.new(
				&"content",
				&"content",
				"res://data",
			),
			GDSQLDatabaseRegistration.new(
				&"save_1",
				&"save_1",
				"user://gdsql/saves/save_1",
				GDSQLStorageBackendIds.IN_MEMORY,
			),
		],
	)
	snapshot.role_bindings.assign(
		[
			GDSQLDatabaseRoleBinding.new(
				GDSQLDatabaseRegistry.CONTENT_ROLE,
				&"content",
			),
			GDSQLDatabaseRoleBinding.new(
				GDSQLDatabaseRegistry.SAVE_ROLE,
				&"save_1",
			),
		],
	)
	return snapshot


func _inspection(
		registration: GDSQLDatabaseRegistration,
		rows: int,
) -> GDSQLDatabaseInspection:
	var inspection := GDSQLDatabaseInspection.new(registration, true)
	inspection.tables.append(
		GDSQLTableInspection.new(&"items", true, true, rows),
	)
	return inspection
