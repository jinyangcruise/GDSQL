class_name GDSQLConfigFileMigrationRecoveryStore
extends GDSQLMigrationRecoveryStore
## Fingerprinted whole-database snapshots restored through a directory swap.

const FORMAT_VERSION := 1
const MANIFEST_FILE := "manifest.cfg"
const SNAPSHOT_DIRECTORY := "snapshot"
const MANIFEST_SECTION := "migration_recovery"

var _path_resolver: GDSQLDatabasePathResolver
var _cache: GDSQLConfigFileCache


func _init(
		path_resolver: GDSQLDatabasePathResolver,
		cache: GDSQLConfigFileCache,
) -> void:
	assert(path_resolver != null)
	assert(cache != null)
	_path_resolver = path_resolver
	_cache = cache


func list_backups(database_name: StringName) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if not _path_resolver.is_valid_name(database_name):
		return _error(
			result,
			&"GDSQL_MIGRATION_BACKUP_IDENTITY_INVALID",
			"Migration recovery discovery requires a valid database identifier.",
		)
	var recovery_root := _path_resolver.resolve_migration_recovery_root(database_name)
	var directory := DirAccess.open(recovery_root)
	var migration_ids := PackedStringArray()
	if directory == null:
		result.value = migration_ids
		return result
	directory.include_hidden = true
	for directory_name in directory.get_directories():
		if directory_name.begins_with(".") or directory_name.ends_with(".building"):
			continue
		if not GDSQLMigrationDefinition.is_valid_id(directory_name):
			return _error(
				result,
				&"GDSQL_MIGRATION_BACKUP_IDENTITY_INVALID",
				"Migration recovery contains an invalid backup identifier '%s'." \
						% directory_name,
			)
		migration_ids.append(directory_name)
	migration_ids.sort()
	result.value = migration_ids
	return result


func create_backup(
		database_name: StringName,
		migration_id: String,
) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if not _is_valid_identity(database_name, migration_id):
		return _error(
			result,
			&"GDSQL_MIGRATION_BACKUP_IDENTITY_INVALID",
			"Migration backup requires valid database and migration identifiers.",
		)
	var database_path := _path_resolver.resolve_database_path(database_name)
	if not _directory_exists(database_path):
		return _error(
			result,
			&"GDSQL_MIGRATION_BACKUP_DATABASE_NOT_FOUND",
			"Database '%s' cannot be backed up because its directory is missing." \
					% database_name,
		)
	var backup_path := _path_resolver.resolve_migration_backup_path(
		database_name,
		migration_id,
	)
	if _directory_exists(backup_path):
		return _error(
			result,
			&"GDSQL_MIGRATION_BACKUP_EXISTS",
			"A recovery snapshot already exists for migration '%s'." % migration_id,
		)
	var staging_path := backup_path + ".building"
	if _remove_tree(staging_path) != OK:
		return _error(
			result,
			&"GDSQL_MIGRATION_BACKUP_STAGING_UNAVAILABLE",
			"Could not prepare migration backup staging.",
		)
	var snapshot_path := staging_path.path_join(SNAPSHOT_DIRECTORY)
	if _copy_tree(database_path, snapshot_path) != OK:
		_remove_tree(staging_path)
		return _error(
			result,
			&"GDSQL_MIGRATION_BACKUP_COPY_FAILED",
			"Could not copy database '%s' into recovery storage." % database_name,
		)
	var fingerprint_result := _fingerprint_tree(snapshot_path)
	result.diagnostics.merge(fingerprint_result.diagnostics)
	if not fingerprint_result.is_successful():
		_remove_tree(staging_path)
		return result
	var backup := GDSQLMigrationBackup.new(
		database_name,
		migration_id,
		String(fingerprint_result.get_value()),
		int(Time.get_unix_time_from_system() * 1000.0),
	)
	if _save_manifest(staging_path, backup) != OK:
		_remove_tree(staging_path)
		return _error(
			result,
			&"GDSQL_MIGRATION_BACKUP_MANIFEST_SAVE_FAILED",
			"Could not save migration recovery metadata.",
		)
	if DirAccess.rename_absolute(
		ProjectSettings.globalize_path(staging_path),
		ProjectSettings.globalize_path(backup_path),
	) != OK:
		_remove_tree(staging_path)
		return _error(
			result,
			&"GDSQL_MIGRATION_BACKUP_ACTIVATION_FAILED",
			"Could not activate the completed migration recovery snapshot.",
		)
	result.value = backup
	return result


func load_backup(
		database_name: StringName,
		migration_id: String,
) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if not _is_valid_identity(database_name, migration_id):
		return _error(
			result,
			&"GDSQL_MIGRATION_BACKUP_IDENTITY_INVALID",
			"Migration backup requires valid database and migration identifiers.",
		)
	var backup_path := _path_resolver.resolve_migration_backup_path(
		database_name,
		migration_id,
	)
	var config := ConfigFile.new()
	if config.load(backup_path.path_join(MANIFEST_FILE)) != OK:
		return _error(
			result,
			&"GDSQL_MIGRATION_BACKUP_NOT_FOUND",
			"No readable recovery snapshot exists for migration '%s'." % migration_id,
		)
	var backup := GDSQLMigrationBackup.new(
		StringName(config.get_value(MANIFEST_SECTION, "database", "")),
		String(config.get_value(MANIFEST_SECTION, "migration_id", "")),
		String(config.get_value(MANIFEST_SECTION, "snapshot_fingerprint", "")),
		int(config.get_value(MANIFEST_SECTION, "created_at_unix_ms", 0)),
	)
	if int(config.get_value(MANIFEST_SECTION, "format_version", 0)) != FORMAT_VERSION \
			or not backup.is_valid() or backup.database_name != database_name \
			or backup.migration_id != migration_id:
		return _error(
			result,
			&"GDSQL_MIGRATION_BACKUP_MANIFEST_INVALID",
			"Migration recovery metadata is invalid or targets another migration.",
		)
	var fingerprint_result := _fingerprint_tree(
		backup_path.path_join(SNAPSHOT_DIRECTORY),
	)
	result.diagnostics.merge(fingerprint_result.diagnostics)
	if not fingerprint_result.is_successful():
		return result
	if String(fingerprint_result.get_value()) != backup.snapshot_fingerprint:
		return _error(
			result,
			&"GDSQL_MIGRATION_BACKUP_FINGERPRINT_MISMATCH",
			"Migration recovery snapshot contents changed after creation.",
		)
	result.value = backup
	return result


func restore(backup: GDSQLMigrationBackup) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if backup == null or not backup.is_valid():
		return _error(
			result,
			&"GDSQL_MIGRATION_BACKUP_INVALID",
			"A valid migration recovery snapshot is required.",
		)
	var loaded := load_backup(backup.database_name, backup.migration_id)
	result.diagnostics.merge(loaded.diagnostics)
	if not loaded.is_successful():
		return result
	var stored := loaded.get_value() as GDSQLMigrationBackup
	if stored.snapshot_fingerprint != backup.snapshot_fingerprint \
			or stored.created_at_unix_ms != backup.created_at_unix_ms:
		return _error(
			result,
			&"GDSQL_MIGRATION_BACKUP_STALE",
			"The requested recovery snapshot no longer matches durable metadata.",
		)
	var database_path := _path_resolver.resolve_database_path(backup.database_name)
	var recovery_root := _path_resolver.resolve_migration_recovery_root(
		backup.database_name,
	)
	var restoring_path := recovery_root.path_join(".restoring")
	var displaced_path := recovery_root.path_join(".displaced")
	if _remove_tree(restoring_path) != OK or _remove_tree(displaced_path) != OK:
		return _error(
			result,
			&"GDSQL_MIGRATION_RESTORE_STAGING_UNAVAILABLE",
			"Could not prepare migration restore staging.",
		)
	var backup_path := _path_resolver.resolve_migration_backup_path(
		backup.database_name,
		backup.migration_id,
	)
	if _copy_tree(
		backup_path.path_join(SNAPSHOT_DIRECTORY),
		restoring_path,
	) != OK:
		_remove_tree(restoring_path)
		return _error(
			result,
			&"GDSQL_MIGRATION_RESTORE_COPY_FAILED",
			"Could not stage the migration recovery snapshot.",
		)
	var restored_fingerprint := _fingerprint_tree(restoring_path)
	result.diagnostics.merge(restored_fingerprint.diagnostics)
	if not restored_fingerprint.is_successful() \
			or String(restored_fingerprint.get_value()) != backup.snapshot_fingerprint:
		_remove_tree(restoring_path)
		if restored_fingerprint.is_successful():
			return _error(
				result,
				&"GDSQL_MIGRATION_RESTORE_FINGERPRINT_MISMATCH",
				"The staged recovery snapshot failed its integrity check.",
			)
		return result
	var had_database := _directory_exists(database_path)
	if had_database and DirAccess.rename_absolute(
		ProjectSettings.globalize_path(database_path),
		ProjectSettings.globalize_path(displaced_path),
	) != OK:
		_remove_tree(restoring_path)
		return _error(
			result,
			&"GDSQL_MIGRATION_RESTORE_SWAP_FAILED",
			"Could not move the current database aside for recovery.",
		)
	if DirAccess.rename_absolute(
		ProjectSettings.globalize_path(restoring_path),
		ProjectSettings.globalize_path(database_path),
	) != OK:
		if had_database:
			DirAccess.rename_absolute(
				ProjectSettings.globalize_path(displaced_path),
				ProjectSettings.globalize_path(database_path),
			)
		_remove_tree(restoring_path)
		return _error(
			result,
			&"GDSQL_MIGRATION_RESTORE_SWAP_FAILED",
			"Could not activate the migration recovery snapshot.",
		)
	_cache.invalidate_prefix(database_path)
	if _remove_tree(displaced_path) != OK:
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_MIGRATION_RESTORE_CLEANUP_PENDING",
				"The database was restored, but displaced files require cleanup.",
				GDSQLQueryDiagnostic.Severity.WARNING,
			),
		)
	result.value = true
	return result


func discard(
		database_name: StringName,
		migration_id: String,
) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if not _is_valid_identity(database_name, migration_id):
		return _error(
			result,
			&"GDSQL_MIGRATION_BACKUP_IDENTITY_INVALID",
			"Migration backup requires valid database and migration identifiers.",
		)
	var backup_path := _path_resolver.resolve_migration_backup_path(
		database_name,
		migration_id,
	)
	if _remove_tree(backup_path) != OK:
		return _error(
			result,
			&"GDSQL_MIGRATION_BACKUP_DISCARD_FAILED",
			"Could not discard the migration recovery snapshot.",
		)
	result.value = true
	return result


func _save_manifest(path: String, backup: GDSQLMigrationBackup) -> Error:
	var config := ConfigFile.new()
	config.set_value(MANIFEST_SECTION, "format_version", FORMAT_VERSION)
	config.set_value(MANIFEST_SECTION, "database", String(backup.database_name))
	config.set_value(MANIFEST_SECTION, "migration_id", backup.migration_id)
	config.set_value(
		MANIFEST_SECTION,
		"snapshot_fingerprint",
		backup.snapshot_fingerprint,
	)
	config.set_value(
		MANIFEST_SECTION,
		"created_at_unix_ms",
		backup.created_at_unix_ms,
	)
	return config.save(path.path_join(MANIFEST_FILE))


func _fingerprint_tree(path: String) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if not _directory_exists(path):
		return _error(
			result,
			&"GDSQL_MIGRATION_BACKUP_SNAPSHOT_MISSING",
			"Migration recovery snapshot directory is missing.",
		)
	var files: Array[String] = []
	if _collect_files(path, "", files) != OK:
		return _error(
			result,
			&"GDSQL_MIGRATION_BACKUP_SNAPSHOT_UNREADABLE",
			"Could not enumerate migration recovery snapshot files.",
		)
	files.sort()
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return _error(
			result,
			&"GDSQL_MIGRATION_BACKUP_FINGERPRINT_FAILED",
			"Could not initialize migration recovery fingerprinting.",
		)
	for relative_path in files:
		var file := FileAccess.open(path.path_join(relative_path), FileAccess.READ)
		if file == null:
			return _error(
				result,
				&"GDSQL_MIGRATION_BACKUP_SNAPSHOT_UNREADABLE",
				"Could not read recovery file '%s'." % relative_path,
			)
		var length := file.get_length()
		hashing.update(
			("%d:%s:%d:" % [relative_path.length(), relative_path, length]) \
					.to_utf8_buffer(),
		)
		hashing.update(file.get_buffer(length))
	result.value = hashing.finish().hex_encode()
	return result


func _collect_files(
		root: String,
		relative_directory: String,
		files: Array[String],
) -> Error:
	var directory := DirAccess.open(root.path_join(relative_directory))
	if directory == null:
		return ERR_CANT_OPEN
	var file_names := directory.get_files()
	file_names.sort()
	for file_name in file_names:
		files.append(relative_directory.path_join(file_name))
	var directory_names := directory.get_directories()
	directory_names.sort()
	for directory_name in directory_names:
		var error := _collect_files(
			root,
			relative_directory.path_join(directory_name),
			files,
		)
		if error != OK:
			return error
	return OK


func _copy_tree(source: String, destination: String) -> Error:
	var source_directory := DirAccess.open(source)
	if source_directory == null:
		return ERR_CANT_OPEN
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(destination),
	)
	if directory_error != OK:
		return directory_error
	for file_name in source_directory.get_files():
		var copy_error := DirAccess.copy_absolute(
			ProjectSettings.globalize_path(source.path_join(file_name)),
			ProjectSettings.globalize_path(destination.path_join(file_name)),
		)
		if copy_error != OK:
			return copy_error
	for directory_name in source_directory.get_directories():
		var copy_error := _copy_tree(
			source.path_join(directory_name),
			destination.path_join(directory_name),
		)
		if copy_error != OK:
			return copy_error
	return OK


func _remove_tree(path: String) -> Error:
	if not _directory_exists(path):
		return OK
	var directory := DirAccess.open(path)
	if directory == null:
		return ERR_CANT_OPEN
	for file_name in directory.get_files():
		var error := DirAccess.remove_absolute(
			ProjectSettings.globalize_path(path.path_join(file_name)),
		)
		if error != OK:
			return error
	for directory_name in directory.get_directories():
		var error := _remove_tree(path.path_join(directory_name))
		if error != OK:
			return error
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _directory_exists(path: String) -> bool:
	return DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path))


func _is_valid_identity(database_name: StringName, migration_id: String) -> bool:
	return _path_resolver.is_valid_name(database_name) \
			and GDSQLMigrationDefinition.is_valid_id(migration_id)


func _error(
		result: GDSQLOperationResult,
		code: StringName,
		message: String,
) -> GDSQLOperationResult:
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
