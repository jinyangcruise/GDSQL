class_name GDSQLConfigFileDatabaseRegistryStore
extends GDSQLDatabaseRegistryStore
## Persists database registration metadata in a human-readable ConfigFile.

const DEFAULT_PATH := "user://gdsql/databases.cfg"
const DATABASE_SECTION_PREFIX := "database:"
const ROLES_SECTION := "roles"

var registry_path: String


func _init(path: String = DEFAULT_PATH) -> void:
	registry_path = path


func load_snapshot() -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	var snapshot := GDSQLDatabaseRegistrySnapshot.new()
	result.value = snapshot
	if not FileAccess.file_exists(registry_path):
		return result
	var config := ConfigFile.new()
	var load_error := config.load(registry_path)
	if load_error != OK:
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_DATABASE_REGISTRY_LOAD_FAILED",
				"Failed to load database registry '%s' (error %d)." \
						% [registry_path, load_error],
			),
		)
		return result
	for section in config.get_sections():
		if section.begins_with(DATABASE_SECTION_PREFIX):
			var registration_name := StringName(section.trim_prefix(DATABASE_SECTION_PREFIX))
			var backend_id := StringName(
				config.get_value(
					section,
					"storage_backend_id",
					GDSQLStorageBackendIds.CONFIG_FILE,
				),
			)
			if not GDSQLStorageBackendIds.is_valid(backend_id):
				result.add_diagnostic(
					GDSQLQueryDiagnostic.new(
						&"GDSQL_STORAGE_BACKEND_ID_INVALID",
						"Database registration '%s' uses unknown storage backend '%s'." \
								% [registration_name, backend_id],
					),
				)
				continue
			snapshot.registrations.append(
				GDSQLDatabaseRegistration.new(
					registration_name,
					StringName(config.get_value(section, "database_name", &"")),
					String(config.get_value(section, "data_root", "")),
					backend_id,
				),
			)
	if config.has_section(ROLES_SECTION):
		for role_name in config.get_section_keys(ROLES_SECTION):
			snapshot.role_bindings.append(
				GDSQLDatabaseRoleBinding.new(
					StringName(role_name),
					StringName(config.get_value(ROLES_SECTION, role_name, &"")),
				),
			)
	return result


func save_snapshot(snapshot: GDSQLDatabaseRegistrySnapshot) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if snapshot == null:
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_DATABASE_REGISTRY_SNAPSHOT_REQUIRED",
				"A database registry snapshot is required.",
			),
		)
		return result
	for registration in snapshot.registrations:
		if not GDSQLStorageBackendIds.is_valid(registration.storage_backend_id):
			result.add_diagnostic(
				GDSQLQueryDiagnostic.new(
					&"GDSQL_STORAGE_BACKEND_ID_INVALID",
					"Database registration '%s' uses unknown storage backend '%s'." \
							% [registration.name, registration.storage_backend_id],
				),
			)
	if not result.is_successful():
		return result
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(registry_path.get_base_dir()),
	)
	if directory_error != OK:
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_DATABASE_REGISTRY_DIRECTORY_FAILED",
				"Failed to prepare database registry directory (error %d)." % directory_error,
			),
		)
		return result
	var config := ConfigFile.new()
	for registration in snapshot.registrations:
		var section := DATABASE_SECTION_PREFIX + String(registration.name)
		config.set_value(section, "database_name", registration.database_name)
		config.set_value(section, "data_root", registration.data_root)
		config.set_value(section, "storage_backend_id", registration.storage_backend_id)
	for binding in snapshot.role_bindings:
		config.set_value(ROLES_SECTION, binding.role, binding.registration_name)
	var save_error := config.save(registry_path)
	if save_error != OK:
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_DATABASE_REGISTRY_SAVE_FAILED",
				"Failed to save database registry '%s' (error %d)." \
						% [registry_path, save_error],
			),
		)
		return result
	result.value = snapshot
	return result
