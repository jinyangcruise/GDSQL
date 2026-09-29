class_name GDSQLConfigFileMigrationHistoryStore
extends GDSQLMigrationHistoryStore
## One immutable ConfigFile per project-authored migration definition.

const DEFAULT_ROOT := "res://.gdsql/migrations"
const MIGRATION_SECTION := "migration"
const DEFINITION_KEY := "definition"
const FILE_EXTENSION := ".cfg"

var history_root: String


func _init(root: String = DEFAULT_ROOT) -> void:
	history_root = root.trim_suffix("/")


func load(migration_stream: StringName) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	var history: Array[GDSQLMigrationDefinition] = []
	result.value = history
	if not _is_valid_stream(migration_stream):
		return _error(
			result,
			&"GDSQL_MIGRATION_STREAM_INVALID",
			"Migration history requires a valid stream identifier.",
		)
	var stream_path := _stream_path(migration_stream)
	var directory := DirAccess.open(stream_path)
	if directory == null:
		return result
	var files: Array[String] = []
	for file_name in directory.get_files():
		if file_name.ends_with(FILE_EXTENSION):
			files.append(file_name)
	files.sort()
	var previous_id := ""
	for file_name in files:
		var config := ConfigFile.new()
		var path := stream_path.path_join(file_name)
		if config.load(path) != OK:
			return _error(
				result,
				&"GDSQL_MIGRATION_HISTORY_LOAD_FAILED",
				"Could not read authored migration '%s'." % path,
			)
		var payload: Variant = config.get_value(
			MIGRATION_SECTION,
			DEFINITION_KEY,
			null,
		)
		if not payload is Dictionary:
			return _error(
				result,
				&"GDSQL_MIGRATION_HISTORY_FILE_INVALID",
				"Authored migration '%s' has no typed definition." % path,
			)
		var decoded := GDSQLMigrationDefinitionSerializer.decode(payload)
		result.diagnostics.merge(decoded.diagnostics)
		if not decoded.is_successful():
			return result
		var migration := decoded.get_value() as GDSQLMigrationDefinition
		if file_name.get_basename() != migration.migration_id:
			return _error(
				result,
				&"GDSQL_MIGRATION_HISTORY_ID_MISMATCH",
				"Migration file '%s' does not match definition '%s'." \
						% [file_name, migration.migration_id],
			)
		if not previous_id.is_empty() and migration.migration_id <= previous_id:
			return _error(
				result,
				&"GDSQL_MIGRATION_ORDER_INVALID",
				"Authored migration IDs must be unique and strictly increasing.",
			)
		previous_id = migration.migration_id
		history.append(migration)
	result.value = history
	return result


func append(
		migration_stream: StringName,
		migration: GDSQLMigrationDefinition,
		expected_definition_count: int,
) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if migration == null or not migration.is_valid():
		return _error(
			result,
			&"GDSQL_MIGRATION_DEFINITION_INVALID",
			"Only a valid migration definition can extend authored history.",
		)
	var loaded := self.load(migration_stream)
	result.diagnostics.merge(loaded.diagnostics)
	if not loaded.is_successful():
		return result
	var history := loaded.get_value() as Array[GDSQLMigrationDefinition]
	if expected_definition_count < 0 or history.size() != expected_definition_count:
		return _error(
			result,
			&"GDSQL_MIGRATION_HISTORY_STALE",
			"Authored migration history changed before the new entry was saved.",
		)
	if not history.is_empty() \
			and migration.migration_id <= history[-1].migration_id:
		return _error(
			result,
			&"GDSQL_MIGRATION_ORDER_INVALID",
			"A new migration ID must sort after the current history head '%s'." \
					% history[-1].migration_id,
		)
	var stream_path := _stream_path(migration_stream)
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(stream_path),
	)
	if directory_error != OK:
		return _error(
			result,
			&"GDSQL_MIGRATION_HISTORY_DIRECTORY_FAILED",
			"Could not prepare authored migration directory '%s'." % stream_path,
		)
	var path := stream_path.path_join(migration.migration_id + FILE_EXTENSION)
	if FileAccess.file_exists(path):
		return _error(
			result,
			&"GDSQL_MIGRATION_HISTORY_DUPLICATE",
			"Authored migration '%s' already exists." % migration.migration_id,
		)
	var staging_path := path + ".building"
	if FileAccess.file_exists(staging_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(staging_path))
	var config := ConfigFile.new()
	config.set_value(
		MIGRATION_SECTION,
		DEFINITION_KEY,
		GDSQLMigrationDefinitionSerializer.encode(migration),
	)
	if config.save(staging_path) != OK:
		return _error(
			result,
			&"GDSQL_MIGRATION_HISTORY_SAVE_FAILED",
			"Could not stage authored migration '%s'." % migration.migration_id,
		)
	if DirAccess.rename_absolute(
		ProjectSettings.globalize_path(staging_path),
		ProjectSettings.globalize_path(path),
	) != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(staging_path))
		return _error(
			result,
			&"GDSQL_MIGRATION_HISTORY_SAVE_FAILED",
			"Could not activate authored migration '%s'." % migration.migration_id,
		)
	result.value = migration
	return result


func _stream_path(migration_stream: StringName) -> String:
	return history_root.path_join(String(migration_stream))


func _is_valid_stream(migration_stream: StringName) -> bool:
	return migration_stream != &"" \
			and String(migration_stream).is_valid_identifier()


func _error(
		result: GDSQLOperationResult,
		code: StringName,
		message: String,
) -> GDSQLOperationResult:
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
