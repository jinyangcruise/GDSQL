class_name GDSQLWorkbench
extends RefCounted
## Collection-level editor coordinator for durable registrations.
##
## The workbench keeps lightweight inspection metadata for every known
## database and opens only the registration selected into its active session.

var snapshot := GDSQLDatabaseRegistrySnapshot.new()
var active_session: GDSQLWorkbenchSession
var _registry: GDSQLDatabaseRegistry
var _explorer: GDSQLDatabaseExplorer
var _inspections: Dictionary[StringName, GDSQLDatabaseInspection] = { }


func _init(
		registry: GDSQLDatabaseRegistry,
		explorer: GDSQLDatabaseExplorer,
) -> void:
	_registry = registry
	_explorer = explorer


func load() -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if _registry == null or _explorer == null:
		return _error(
			&"GDSQL_WORKBENCH_SERVICES_REQUIRED",
			"Workbench requires a database registry and explorer.",
		)
	var loaded := _registry.load_snapshot()
	result.diagnostics.merge(loaded.diagnostics)
	if not loaded.is_successful():
		return result
	snapshot = loaded.get_value() as GDSQLDatabaseRegistrySnapshot
	var refreshed := refresh_inspections()
	result.diagnostics.merge(refreshed.diagnostics)
	if result.is_successful():
		result.value = self
	return result


func get_registrations() -> Array[GDSQLDatabaseRegistration]:
	return snapshot.registrations.duplicate()


func get_registration(
		registration_name: StringName,
) -> GDSQLDatabaseRegistration:
	for registration in snapshot.registrations:
		if registration.name == registration_name:
			return registration
	return null


func get_inspections() -> Array[GDSQLDatabaseInspection]:
	var values: Array[GDSQLDatabaseInspection] = []
	for inspection in _inspections.values():
		values.append(inspection)
	return values


func get_inspection(
		registration_name: StringName,
) -> GDSQLDatabaseInspection:
	return _inspections.get(registration_name)


func refresh_inspections() -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	_inspections.clear()
	var inspected_roots: Dictionary[String, Array] = { }
	for registration in snapshot.registrations:
		if registration.storage_backend_id not in [
			GDSQLStorageBackendIds.CONFIG_FILE,
			GDSQLStorageBackendIds.IN_MEMORY,
		]:
			continue
		if not inspected_roots.has(registration.data_root):
			var root_result := _explorer.inspect_root(registration.data_root)
			result.diagnostics.merge(root_result.diagnostics)
			if not root_result.is_successful():
				continue
			inspected_roots[registration.data_root] = root_result.get_value()
		var found := false
		for inspection_value in inspected_roots[registration.data_root]:
			var inspection := inspection_value as GDSQLDatabaseInspection
			if inspection.registration.database_name == registration.database_name:
				inspection.registration = registration
				_inspections[registration.name] = inspection
				found = true
				break
		if not found:
			_inspections[registration.name] = GDSQLDatabaseInspection.new(
				registration,
				false,
			)
	result.value = get_inspections()
	return result


func discover_root(
		data_root: String,
		registration_prefix: StringName = &"",
		persist: bool = true,
) -> GDSQLOperationResult:
	var discovery := _explorer.inspect_root(data_root, registration_prefix)
	if not discovery.is_successful():
		return discovery
	var result := GDSQLOperationResult.new()
	result.diagnostics.merge(discovery.diagnostics)
	var discovered_databases: Dictionary[StringName, bool] = { }
	for inspection_value in discovery.get_value():
		var inspection := inspection_value as GDSQLDatabaseInspection
		discovered_databases[inspection.registration.database_name] = true
	for registration in snapshot.registrations.duplicate():
		if registration.data_root == data_root \
				and not discovered_databases.has(registration.database_name):
			_remove_registration_state(registration)
	for inspection_value in discovery.get_value():
		var inspection := inspection_value as GDSQLDatabaseInspection
		var existing := _find_registration(
			inspection.registration.database_name,
			data_root,
		)
		if existing != null:
			inspection.registration = existing
			_inspections[existing.name] = inspection
		else:
			var merged := _merge_inspection(inspection)
			result.diagnostics.merge(merged.diagnostics)
	if result.is_successful() and persist:
		var saved := _registry.save_snapshot(snapshot)
		result.diagnostics.merge(saved.diagnostics)
	result.value = discovery.get_value()
	return result


func discover_children(
		parent_root: String,
		persist: bool = true,
) -> GDSQLOperationResult:
	var directory := DirAccess.open(parent_root)
	if directory == null:
		return _error(
			&"GDSQL_DATABASE_DISCOVERY_ROOT_UNREADABLE",
			"Could not inspect database parent root '%s'." % parent_root,
		)
	var result := GDSQLOperationResult.new()
	var discovered: Array[GDSQLDatabaseInspection] = []
	for directory_name in directory.get_directories():
		var child_root := parent_root.path_join(directory_name)
		if not FileAccess.file_exists(child_root.path_join("databases.cfg")):
			continue
		var child := discover_root(
			child_root,
			StringName(directory_name),
			false,
		)
		result.diagnostics.merge(child.diagnostics)
		if child.is_successful():
			for inspection in child.get_value():
				discovered.append(inspection)
	if result.is_successful() and persist:
		var saved := _registry.save_snapshot(snapshot)
		result.diagnostics.merge(saved.diagnostics)
	result.value = discovered
	return result


func select_registration(
		registration_name: StringName,
) -> GDSQLOperationResult:
	var registration := get_registration(registration_name)
	if registration == null:
		return _error(
			&"GDSQL_WORKBENCH_REGISTRATION_NOT_FOUND",
			"Database registration '%s' was not found." % registration_name,
		)
	var session := GDSQLWorkbenchSession.new()
	var opened := session.open_registration(registration)
	var result := GDSQLOperationResult.new()
	result.diagnostics.merge(opened.diagnostics)
	if opened.is_successful():
		active_session = session
		result.value = session
	return result


func remove_registration(
		registration_name: StringName,
		persist: bool = true,
) -> GDSQLOperationResult:
	var registration := get_registration(registration_name)
	if registration == null:
		return _error(
			&"GDSQL_WORKBENCH_REGISTRATION_NOT_FOUND",
			"Database registration '%s' was not found." % registration_name,
		)
	_remove_registration_state(registration)
	var result := GDSQLOperationResult.new()
	if persist:
		var saved := _registry.save_snapshot(snapshot)
		result.diagnostics.merge(saved.diagnostics)
	result.value = registration
	return result


func set_storage_backend(
		registration_name: StringName,
		backend_id: StringName,
) -> GDSQLOperationResult:
	if not GDSQLStorageBackendIds.is_implemented(backend_id):
		return _error(
			&"GDSQL_STORAGE_BACKEND_UNAVAILABLE",
			"Storage backend '%s' is not available." % backend_id,
		)
	var registration := get_registration(registration_name)
	if registration == null:
		return _error(
			&"GDSQL_WORKBENCH_REGISTRATION_NOT_FOUND",
			"Database registration '%s' was not found." % registration_name,
		)
	registration.storage_backend_id = backend_id
	var result := _registry.save_snapshot(snapshot)
	result.value = registration
	return result


func update_database_name(
		registration_name: StringName,
		database_name: StringName,
) -> GDSQLOperationResult:
	var registration := get_registration(registration_name)
	if registration == null:
		return _error(
			&"GDSQL_WORKBENCH_REGISTRATION_NOT_FOUND",
			"Database registration '%s' was not found." % registration_name,
		)
	registration.database_name = database_name
	var result := _registry.save_snapshot(snapshot)
	result.value = registration
	return result


func _find_registration(
		database_name: StringName,
		data_root: String,
) -> GDSQLDatabaseRegistration:
	for registration in snapshot.registrations:
		if registration.database_name == database_name \
				and registration.data_root == data_root:
			return registration
	return null


func _remove_registration_state(
		registration: GDSQLDatabaseRegistration,
) -> void:
	snapshot.registrations.erase(registration)
	_inspections.erase(registration.name)
	for binding in snapshot.role_bindings.duplicate():
		if binding.registration_name == registration.name:
			snapshot.role_bindings.erase(binding)
	if active_session != null \
			and active_session.registration.name == registration.name:
		active_session = null


func _merge_inspection(
		inspection: GDSQLDatabaseInspection,
) -> GDSQLOperationResult:
	var registration := inspection.registration
	var existing := get_registration(registration.name)
	if existing != null and (
			existing.database_name != registration.database_name
			or existing.data_root != registration.data_root
	):
		return _error(
			&"GDSQL_DATABASE_REGISTRATION_COLLISION",
			"Registration name '%s' already identifies another database." \
					% registration.name,
		)
	if existing == null:
		snapshot.registrations.append(registration)
	else:
		inspection.registration = existing
	_inspections[registration.name] = inspection
	var result := GDSQLOperationResult.new()
	result.value = inspection
	return result


func _error(code: StringName, message: String) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
