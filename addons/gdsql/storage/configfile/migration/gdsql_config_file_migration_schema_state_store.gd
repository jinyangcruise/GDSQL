class_name GDSQLConfigFileMigrationSchemaStateStore
extends GDSQLMigrationSchemaStateStore
## ConfigFile persistence for project-owned migration schema evidence.

const DEFAULT_ROOT := "res://.gdsql/migration_states"
const FORMAT_VERSION := 1
const STATE_SECTION := "schema_state"

var state_root: String


func _init(root: String = DEFAULT_ROOT) -> void:
	state_root = root.trim_suffix("/")


func load(migration_stream: StringName) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if not _is_valid_stream(migration_stream):
		return _error(
			result,
			&"GDSQL_MIGRATION_STREAM_INVALID",
			"Migration schema state requires a valid stream identifier.",
		)
	var path := _state_path(migration_stream)
	var backup_path := path + ".previous"
	if not FileAccess.file_exists(path) and FileAccess.file_exists(backup_path) \
			and DirAccess.rename_absolute(
				ProjectSettings.globalize_path(backup_path),
				ProjectSettings.globalize_path(path),
			) != OK:
		return _error(
			result,
			&"GDSQL_MIGRATION_SCHEMA_STATE_RECOVERY_FAILED",
			"Could not recover interrupted migration schema state '%s'." % path,
		)
	var config := ConfigFile.new()
	var load_error := config.load(path)
	if load_error == ERR_FILE_NOT_FOUND:
		return result
	if load_error != OK \
			or int(config.get_value(STATE_SECTION, "format_version", 0)) != FORMAT_VERSION:
		return _error(
			result,
			&"GDSQL_MIGRATION_SCHEMA_STATE_UNREADABLE",
			"Could not read migration schema state '%s'." % path,
		)
	var state := GDSQLMigrationSchemaState.new(
		StringName(config.get_value(STATE_SECTION, "migration_stream", &"")),
		StringName(config.get_value(STATE_SECTION, "database_name", &"")),
		int(config.get_value(STATE_SECTION, "history_count", -1)),
		String(config.get_value(STATE_SECTION, "migration_head_id", "")),
		String(config.get_value(STATE_SECTION, "history_checksum", "")),
		String(config.get_value(STATE_SECTION, "schema_fingerprint", "")),
	)
	if not state.is_valid() or state.migration_stream != migration_stream:
		return _error(
			result,
			&"GDSQL_MIGRATION_SCHEMA_STATE_INVALID",
			"Migration schema state '%s' is invalid." % path,
		)
	result.value = state
	return result


func save(
		state: GDSQLMigrationSchemaState,
		expected_previous_history_checksum: String,
) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if state == null or not state.is_valid():
		return _error(
			result,
			&"GDSQL_MIGRATION_SCHEMA_STATE_INVALID",
			"Only valid migration schema state can be persisted.",
		)
	var loaded := self.load(state.migration_stream)
	result.diagnostics.merge(loaded.diagnostics)
	if not loaded.is_successful():
		return result
	var previous := loaded.get_value() as GDSQLMigrationSchemaState
	if previous == null:
		if not expected_previous_history_checksum.is_empty():
			return _stale(result)
	else:
		if previous.history_checksum != expected_previous_history_checksum:
			return _stale(result)
		if state.database_name != previous.database_name \
				or state.history_count < previous.history_count:
			return _error(
				result,
				&"GDSQL_MIGRATION_SCHEMA_STATE_DIVERGED",
				"Migration schema state cannot change database identity or move backward.",
			)
		if state.history_count == previous.history_count \
				and state.history_count > 0 \
				and (
						state.history_checksum != previous.history_checksum \
								or state.migration_head_id != previous.migration_head_id \
								or state.schema_fingerprint != previous.schema_fingerprint
				):
			return _error(
				result,
				&"GDSQL_MIGRATION_SCHEMA_STATE_DIVERGED",
				"Migration schema state cannot replace evidence for an existing history position.",
			)
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(state_root),
	)
	if directory_error != OK:
		return _error(
			result,
			&"GDSQL_MIGRATION_SCHEMA_STATE_DIRECTORY_FAILED",
			"Could not prepare migration schema-state directory '%s'." % state_root,
		)
	var path := _state_path(state.migration_stream)
	var staging_path := path + ".building"
	if FileAccess.file_exists(staging_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(staging_path))
	var config := ConfigFile.new()
	config.set_value(STATE_SECTION, "format_version", FORMAT_VERSION)
	config.set_value(STATE_SECTION, "migration_stream", state.migration_stream)
	config.set_value(STATE_SECTION, "database_name", state.database_name)
	config.set_value(STATE_SECTION, "history_count", state.history_count)
	config.set_value(STATE_SECTION, "migration_head_id", state.migration_head_id)
	config.set_value(STATE_SECTION, "history_checksum", state.history_checksum)
	config.set_value(STATE_SECTION, "schema_fingerprint", state.schema_fingerprint)
	if config.save(staging_path) != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(staging_path))
		return _error(
			result,
			&"GDSQL_MIGRATION_SCHEMA_STATE_SAVE_FAILED",
			"Could not stage migration schema state '%s'." % path,
		)
	var global_path := ProjectSettings.globalize_path(path)
	var global_staging_path := ProjectSettings.globalize_path(staging_path)
	var backup_path := path + ".previous"
	var global_backup_path := ProjectSettings.globalize_path(backup_path)
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(global_backup_path)
	var had_previous := FileAccess.file_exists(path)
	if had_previous and DirAccess.rename_absolute(global_path, global_backup_path) != OK:
		DirAccess.remove_absolute(global_staging_path)
		return _error(
			result,
			&"GDSQL_MIGRATION_SCHEMA_STATE_SAVE_FAILED",
			"Could not replace migration schema state '%s'." % path,
		)
	if DirAccess.rename_absolute(global_staging_path, global_path) != OK:
		if had_previous:
			DirAccess.rename_absolute(global_backup_path, global_path)
		DirAccess.remove_absolute(global_staging_path)
		return _error(
			result,
			&"GDSQL_MIGRATION_SCHEMA_STATE_SAVE_FAILED",
			"Could not activate migration schema state '%s'." % path,
		)
	if had_previous:
		DirAccess.remove_absolute(global_backup_path)
	result.value = state
	return result


func _state_path(migration_stream: StringName) -> String:
	return state_root.path_join(String(migration_stream) + ".cfg")


func _is_valid_stream(migration_stream: StringName) -> bool:
	return migration_stream != &"" \
			and String(migration_stream).is_valid_identifier()


func _stale(result: GDSQLOperationResult) -> GDSQLOperationResult:
	return _error(
		result,
		&"GDSQL_MIGRATION_SCHEMA_STATE_STALE",
		"Migration schema state changed before it could be persisted.",
	)


func _error(
		result: GDSQLOperationResult,
		code: StringName,
		message: String,
) -> GDSQLOperationResult:
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
