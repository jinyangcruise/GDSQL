class_name GDSQLConfigFileMigrationLedger
extends GDSQLMigrationLedger
## ConfigFile implementation of an append-only per-database migration ledger.

const FORMAT_VERSION := 1
const METADATA_SECTION := "migration_ledger"
const RECORD_PREFIX := "migration:"

var _path_resolver: GDSQLDatabasePathResolver


func _init(path_resolver: GDSQLDatabasePathResolver) -> void:
	assert(path_resolver != null)
	_path_resolver = path_resolver


func load(database_name: StringName) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if not _path_resolver.is_valid_name(database_name):
		return _error(result, &"GDSQL_MIGRATION_DATABASE_INVALID", "")
	var path := _path_resolver.resolve_migration_ledger_path(database_name)
	var config := ConfigFile.new()
	var load_error := config.load(path)
	if load_error == ERR_FILE_NOT_FOUND:
		result.value = GDSQLMigrationLedgerSnapshot.new()
		return result
	if load_error != OK \
			or int(config.get_value(METADATA_SECTION, "format_version", 0)) != FORMAT_VERSION:
		return _error(result, &"GDSQL_MIGRATION_LEDGER_UNREADABLE", path)
	var order: Variant = config.get_value(
		METADATA_SECTION,
		"order",
		PackedStringArray(),
	)
	if not order is PackedStringArray and not order is Array:
		return _error(result, &"GDSQL_MIGRATION_LEDGER_INVALID", path)
	var records: Array[GDSQLAppliedMigration] = []
	var seen: Dictionary[String, bool] = { }
	var previous_id := ""
	for id_value in order:
		var migration_id := String(id_value)
		var section := RECORD_PREFIX + migration_id
		var record := GDSQLAppliedMigration.new(
			migration_id,
			String(config.get_value(section, "checksum", "")),
			int(config.get_value(section, "applied_at_unix_ms", 0)),
			String(config.get_value(section, "schema_fingerprint", "")),
		)
		if seen.has(migration_id) or not config.has_section(section) \
				or not record.is_valid() \
				or not previous_id.is_empty() and migration_id <= previous_id:
			return _error(result, &"GDSQL_MIGRATION_LEDGER_INVALID", path)
		seen[migration_id] = true
		previous_id = migration_id
		records.append(record)
	for section_name in config.get_sections():
		if section_name.begins_with(RECORD_PREFIX) \
				and not seen.has(section_name.trim_prefix(RECORD_PREFIX)):
			return _error(result, &"GDSQL_MIGRATION_LEDGER_INVALID", path)
	result.value = GDSQLMigrationLedgerSnapshot.new(records)
	return result


func append(
		database_name: StringName,
		record: GDSQLAppliedMigration,
		expected_record_count: int,
) -> GDSQLOperationResult:
	var loaded := self.load(database_name)
	if not loaded.is_successful():
		return loaded
	var snapshot := loaded.get_value() as GDSQLMigrationLedgerSnapshot
	var result := GDSQLOperationResult.new()
	var path := _path_resolver.resolve_migration_ledger_path(database_name)
	if not DirAccess.dir_exists_absolute(
			ProjectSettings.globalize_path(path.get_base_dir()),
	):
		return _error(result, &"GDSQL_MIGRATION_DATABASE_NOT_FOUND", path)
	if record == null or not record.is_valid():
		return _error(result, &"GDSQL_MIGRATION_RECORD_INVALID", path)
	if snapshot.records.size() != expected_record_count:
		return _error(result, &"GDSQL_MIGRATION_LEDGER_STALE", path)
	if snapshot.find(record.migration_id) != null \
			or not snapshot.last_id().is_empty() and record.migration_id <= snapshot.last_id():
		return _error(result, &"GDSQL_MIGRATION_APPEND_ORDER_INVALID", path)
	var config := ConfigFile.new()
	if FileAccess.file_exists(path) and config.load(path) != OK:
		return _error(result, &"GDSQL_MIGRATION_LEDGER_UNREADABLE", path)
	config.set_value(METADATA_SECTION, "format_version", FORMAT_VERSION)
	var order := PackedStringArray()
	for applied in snapshot.records:
		order.append(applied.migration_id)
	order.append(record.migration_id)
	config.set_value(METADATA_SECTION, "order", order)
	var section := RECORD_PREFIX + record.migration_id
	config.set_value(section, "checksum", record.checksum)
	config.set_value(section, "applied_at_unix_ms", record.applied_at_unix_ms)
	config.set_value(section, "schema_fingerprint", record.schema_fingerprint)
	if config.save(path) != OK:
		return _error(result, &"GDSQL_MIGRATION_LEDGER_SAVE_FAILED", path)
	result.value = record
	return result


func _error(
		result: GDSQLOperationResult,
		code: StringName,
		path: String,
) -> GDSQLOperationResult:
	result.add_diagnostic(
		GDSQLQueryDiagnostic.new(
			code,
			"Could not use migration ledger%s." % (
				" '%s'" % path if not path.is_empty() else ""
			),
		),
	)
	return result
