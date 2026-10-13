class_name GDSQLMigrationPlanner
extends RefCounted
## Validates immutable authored history against an append-only applied ledger.

func plan(
		migrations: Array[GDSQLMigrationDefinition],
		ledger: GDSQLMigrationLedgerSnapshot,
) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if ledger == null:
		return _error(
			result,
			&"GDSQL_MIGRATION_LEDGER_REQUIRED",
			"Migration planning requires an applied-history snapshot.",
		)
	var previous_id := ""
	for migration in migrations:
		if migration == null or not migration.is_valid():
			return _error(
				result,
				&"GDSQL_MIGRATION_DEFINITION_INVALID",
				"Migration history contains an invalid or modified definition.",
			)
		if not previous_id.is_empty() and migration.migration_id <= previous_id:
			return _error(
				result,
				&"GDSQL_MIGRATION_ORDER_INVALID",
				"Migration IDs must be unique and strictly increasing.",
			)
		previous_id = migration.migration_id
	var baseline_count := 0
	if ledger.baseline != null:
		if not ledger.baseline.is_valid():
			return _error(
				result,
				&"GDSQL_MIGRATION_BASELINE_INVALID",
				"The migration ledger contains an invalid adopted baseline.",
			)
		var baseline_index := -1
		if not ledger.baseline.through_migration_id.is_empty():
			baseline_index = _find_migration(
				migrations,
				ledger.baseline.through_migration_id,
			)
			if baseline_index < 0:
				return _error(
					result,
					&"GDSQL_MIGRATION_BASELINE_HISTORY_MISSING",
					"The adopted migration baseline is absent from project history.",
				)
			if migrations[baseline_index].checksum != ledger.baseline.through_checksum:
				return _error(
					result,
					&"GDSQL_MIGRATION_BASELINE_CHECKSUM_MISMATCH",
					"The adopted migration baseline changed after adoption.",
				)
		var history_checksum := GDSQLMigrationHistoryChecksum.compute(
			migrations,
			baseline_index + 1,
		)
		if history_checksum != ledger.baseline.history_checksum:
			return _error(
				result,
				&"GDSQL_MIGRATION_BASELINE_HISTORY_CHANGED",
				"The adopted migration-history prefix changed after adoption.",
			)
		baseline_count = baseline_index + 1
	if baseline_count + ledger.records.size() > migrations.size():
		return _error(
			result,
			&"GDSQL_MIGRATION_HISTORY_MISSING",
			"The database contains applied migrations absent from project history.",
		)
	for index in ledger.records.size():
		var applied := ledger.records[index]
		if applied == null or not applied.is_valid():
			return _error(
				result,
				&"GDSQL_MIGRATION_LEDGER_INVALID",
				"The applied migration ledger contains an invalid record.",
			)
		var authored := migrations[baseline_count + index]
		if authored.migration_id != applied.migration_id:
			return _error(
				result,
				&"GDSQL_MIGRATION_HISTORY_DIVERGED",
				"Applied migration '%s' is not the expected history entry '%s'." % [
					applied.migration_id,
					authored.migration_id,
				],
			)
		if authored.checksum != applied.checksum:
			return _error(
				result,
				&"GDSQL_MIGRATION_CHECKSUM_MISMATCH",
				"Applied migration '%s' was changed after application." \
						% authored.migration_id,
			)
	var pending: Array[GDSQLMigrationDefinition] = []
	var applied_count := baseline_count + ledger.records.size()
	for index in range(applied_count, migrations.size()):
		pending.append(migrations[index])
	result.value = GDSQLMigrationPlan.new(
		pending,
		applied_count,
		ledger.revision(),
	)
	return result


func _find_migration(
		history: Array[GDSQLMigrationDefinition],
		migration_id: String,
) -> int:
	for index in history.size():
		if history[index].migration_id == migration_id:
			return index
	return -1


func _error(
		result: GDSQLOperationResult,
		code: StringName,
		message: String,
) -> GDSQLOperationResult:
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
