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
	if ledger.records.size() > migrations.size():
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
		var authored := migrations[index]
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
	for index in range(ledger.records.size(), migrations.size()):
		pending.append(migrations[index])
	result.value = GDSQLMigrationPlan.new(pending, ledger.records.size())
	return result


func _error(
		result: GDSQLOperationResult,
		code: StringName,
		message: String,
) -> GDSQLOperationResult:
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
