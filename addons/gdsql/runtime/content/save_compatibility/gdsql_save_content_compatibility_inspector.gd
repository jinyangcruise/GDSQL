class_name GDSQLSaveContentCompatibilityInspector
extends RefCounted
## Compares save-owned expectations with one active effective-content manifest.

static func inspect(
		expected: GDSQLSaveContentManifest,
		active: GDSQLContentCacheManifest,
) -> GDSQLSaveContentCompatibilityReport:
	var report := GDSQLSaveContentCompatibilityReport.new()
	if active == null:
		return _unavailable(report)
	if expected == null:
		return _untracked(report)
	var active_by_id: Dictionary[StringName, GDSQLContentPackageFingerprint] = { }
	for package in active.packages:
		active_by_id[package.package_id] = package
	var expected_ids: Dictionary[StringName, bool] = { }
	for package in expected.packages:
		expected_ids[package.package_id] = true
		if not active_by_id.has(package.package_id):
			report.missing_packages.append(package)
			report.diagnostics.add(
				GDSQLQueryDiagnostic.new(
					&"GDSQL_SAVE_CONTENT_PACKAGE_MISSING",
					"Save expects package '%s' (%s), but it is not active." % [
						package.package_id,
						package.version,
					],
					GDSQLQueryDiagnostic.Severity.WARNING,
				),
			)
			continue
		var active_package := active_by_id[package.package_id]
		if not package.is_equivalent_to(active_package):
			report.changed_packages.append(
				GDSQLSaveContentPackageChange.new(package, active_package),
			)
			report.diagnostics.add(
				GDSQLQueryDiagnostic.new(
					&"GDSQL_SAVE_CONTENT_PACKAGE_CHANGED",
					"Package '%s' changed from version %s to %s or has different content." % [
						package.package_id,
						package.version,
						active_package.version,
					],
					GDSQLQueryDiagnostic.Severity.WARNING,
				),
			)
	for package in active.packages:
		if not expected_ids.has(package.package_id):
			report.additional_packages.append(package)
			report.diagnostics.add(
				GDSQLQueryDiagnostic.new(
					&"GDSQL_SAVE_CONTENT_PACKAGE_ADDED",
					"Active package '%s' was not recorded by this save." % package.package_id,
					GDSQLQueryDiagnostic.Severity.INFO,
				),
			)
	if report.missing_packages.is_empty() and report.additional_packages.is_empty() \
			and not _has_same_order(expected.packages, active.packages):
		report.load_order_changed = true
		report.diagnostics.add(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_SAVE_CONTENT_LOAD_ORDER_CHANGED",
				"The active package load order differs from the order recorded by this save.",
				GDSQLQueryDiagnostic.Severity.WARNING,
			),
		)
	if not report.missing_packages.is_empty():
		report.status = GDSQLSaveContentCompatibilityReport.Status.MISSING_PACKAGES
	elif not report.changed_packages.is_empty() or not report.additional_packages.is_empty() \
			or report.load_order_changed:
		report.status = GDSQLSaveContentCompatibilityReport.Status.CHANGED
	else:
		report.status = GDSQLSaveContentCompatibilityReport.Status.EXACT
	return report


static func _has_same_order(
		expected: Array[GDSQLContentPackageFingerprint],
		active: Array[GDSQLContentPackageFingerprint],
) -> bool:
	if expected.size() != active.size():
		return false
	for index in expected.size():
		if expected[index].package_id != active[index].package_id:
			return false
	return true


static func _unavailable(
		report: GDSQLSaveContentCompatibilityReport,
) -> GDSQLSaveContentCompatibilityReport:
	report.status = GDSQLSaveContentCompatibilityReport.Status.UNAVAILABLE
	report.diagnostics.add(
		GDSQLQueryDiagnostic.new(
			&"GDSQL_ACTIVE_CONTENT_MANIFEST_REQUIRED",
			"Save compatibility requires an active effective-content manifest.",
		),
	)
	return report


static func _untracked(
		report: GDSQLSaveContentCompatibilityReport,
) -> GDSQLSaveContentCompatibilityReport:
	report.status = GDSQLSaveContentCompatibilityReport.Status.UNTRACKED
	report.diagnostics.add(
		GDSQLQueryDiagnostic.new(
			&"GDSQL_SAVE_CONTENT_MANIFEST_MISSING",
			"This save does not record an expected content package set.",
			GDSQLQueryDiagnostic.Severity.WARNING,
		),
	)
	return report
