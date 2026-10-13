class_name GDSQLMcpDatabaseAuthoringService
extends RefCounted
## Guarded lifecycle authoring for databases visible to the editor workbench.

signal committed(registration_name: StringName)

const Ticket = preload(
	"res://addons/gdsql/editor/integrations/mcp/authoring/database/gdsql_mcp_database_mutation_ticket.gd"
)
const CanonicalValue = preload(
	"res://addons/gdsql/migration/gdsql_migration_canonical_value.gd"
)
const HANDLE_TTL_MSEC := 120_000
const DEFAULT_LOCATIONS := {
	"project_data": "res://data",
	"settings": "user://gdsql/settings",
}
const OPERATIONS := [
	"create_database",
	"rename_database",
	"unregister_database",
	"destroy_database",
]

var _workbench: GDSQLWorkbench
var _locations: Dictionary
var _history_store: GDSQLMigrationHistoryStore
var _tickets: Dictionary[String, GDSQLMcpDatabaseMutationTicket] = { }


func _init(
		workbench: GDSQLWorkbench,
		locations: Dictionary = { },
		history_store: GDSQLMigrationHistoryStore = null,
) -> void:
	_workbench = workbench
	_locations = DEFAULT_LOCATIONS.duplicate()
	for key in locations:
		_locations[String(key)] = String(locations[key]).trim_suffix("/")
	_history_store = (
		history_store
		if history_store != null
		else GDSQLConfigFileMigrationHistoryStore.new()
	)


func preview(request: Dictionary) -> GDSQLOperationResult:
	_cleanup_expired_tickets()
	if _workbench == null:
		return _error(
			&"GDSQL_MCP_WORKBENCH_REQUIRED",
			"The GDSQL workbench is unavailable.",
		)
	var normalized := _normalize(request)
	if not normalized.is_successful():
		return normalized
	var payload := normalized.get_value() as Dictionary
	var validation := _validate(payload)
	if not validation.is_successful():
		return validation
	if payload["operation"] != "create_database":
		payload["database"] = String(
			_workbench.get_registration(StringName(payload["registration"])).database_name,
		)
	var ticket := Ticket.new()
	ticket.token = Crypto.new().generate_random_bytes(24).hex_encode()
	ticket.operation = payload["operation"]
	ticket.payload = payload.duplicate(true)
	ticket.workspace_fingerprint = _workspace_fingerprint(payload)
	ticket.expires_at_msec = Time.get_ticks_msec() + HANDLE_TTL_MSEC
	_tickets[ticket.token] = ticket
	var summary := validation.get_value() as Dictionary
	summary.merge(
		{
			"kind": "database_mutation_preview",
			"operation": ticket.operation,
			"destructive": ticket.operation == "destroy_database",
			"preserves_files": ticket.operation == "unregister_database",
			"confirmation_handle": ticket.token,
			"expires_in_ms": HANDLE_TTL_MSEC,
		},
		true,
	)
	return _success(summary)


func commit(handle: String, confirmed: bool) -> GDSQLOperationResult:
	_cleanup_expired_tickets()
	if not confirmed:
		return _error(
			&"GDSQL_MCP_CONFIRMATION_REQUIRED",
			"The previewed database mutation must be explicitly confirmed.",
		)
	if handle.is_empty() or not _tickets.has(handle):
		return _error(
			&"GDSQL_MCP_DATABASE_HANDLE_INVALID",
			"The database mutation handle is invalid, expired, or already used.",
		)
	var ticket := _tickets[handle] as GDSQLMcpDatabaseMutationTicket
	_tickets.erase(handle)
	if _workspace_fingerprint(ticket.payload) != ticket.workspace_fingerprint:
		return _stale("The registered database workspace changed after preview.")
	var validation := _validate(ticket.payload)
	if not validation.is_successful():
		return _stale("The database mutation is no longer valid.")
	var applied := _apply(ticket.payload)
	if not applied.is_successful():
		return applied
	_workbench.refresh_inspections()
	var registration_name := StringName(ticket.payload["registration"])
	committed.emit(registration_name)
	return _success(
		{
			"kind": "database_mutation_commit",
			"operation": ticket.operation,
			"registration": String(registration_name),
			"database": String(
				ticket.payload.get("new_name", ticket.payload.get("database", "")),
			),
			"preserves_files": ticket.operation == "unregister_database",
		},
	)


func _normalize(request: Dictionary) -> GDSQLOperationResult:
	var allowed := [
		"operation", "registration", "database", "location",
		"root_registration", "storage_backend", "new_name",
	]
	for key in request:
		if String(key) not in allowed:
			return _error(
				&"GDSQL_MCP_DATABASE_FIELD_UNKNOWN",
				"Unknown database mutation field '%s'." % key,
			)
	var operation := String(request.get("operation", "")).to_lower()
	if operation not in OPERATIONS:
		return _error(
			&"GDSQL_MCP_DATABASE_OPERATION_INVALID",
			"Operation must create, rename, unregister, or destroy a database.",
		)
	var operation_fields := ["operation", "registration"]
	if operation == "create_database":
		operation_fields.append_array(
			["database", "location", "root_registration", "storage_backend"],
		)
	elif operation == "rename_database":
		operation_fields.append("new_name")
	for key in request:
		if String(key) not in operation_fields:
			return _error(
				&"GDSQL_MCP_DATABASE_FIELD_INVALID",
				"Field '%s' does not apply to operation '%s'." % [key, operation],
			)
	var registration := String(request.get("registration", ""))
	if not registration.is_valid_identifier():
		return _error(
			&"GDSQL_MCP_REGISTRATION_INVALID",
			"registration must be a valid identifier.",
		)
	var payload := { "operation": operation, "registration": registration }
	if operation == "create_database":
		var database := String(request.get("database", ""))
		if not database.is_valid_identifier():
			return _error(
				&"GDSQL_MCP_DATABASE_NAME_INVALID",
				"database must be a valid identifier.",
			)
		var location := String(request.get("location", "project_data"))
		if location != "registration_root" and request.has("root_registration"):
			return _error(
				&"GDSQL_MCP_DATABASE_LOCATION_INVALID",
				"root_registration is valid only with location 'registration_root'.",
			)
		var root := _resolve_location(
			location,
			StringName(request.get("root_registration", "")),
		)
		if root.is_empty():
			return _error(
				&"GDSQL_MCP_DATABASE_LOCATION_INVALID",
				"location must be 'project_data', 'settings', or 'registration_root' with a known root_registration.",
			)
		var backend := StringName(
			request.get("storage_backend", GDSQLStorageBackendIds.CONFIG_FILE),
		)
		if not GDSQLStorageBackendIds.is_implemented(backend):
			return _error(
				&"GDSQL_STORAGE_BACKEND_UNAVAILABLE",
				"Storage backend '%s' is not available." % backend,
			)
		payload.merge(
			{
				"database": database,
				"location": location,
				"data_root": root,
				"storage_backend": String(backend),
			},
		)
	elif operation == "rename_database":
		var new_name := String(request.get("new_name", ""))
		if not new_name.is_valid_identifier():
			return _error(
				&"GDSQL_MCP_DATABASE_NAME_INVALID",
				"new_name must be a valid identifier.",
			)
		payload["new_name"] = new_name
	return _value(payload)


func _validate(payload: Dictionary) -> GDSQLOperationResult:
	var operation := String(payload["operation"])
	var registration_name := StringName(payload["registration"])
	if operation == "create_database":
		if _workbench.get_registration(registration_name) != null:
			return _error(
				&"GDSQL_MCP_REGISTRATION_EXISTS",
				"Database registration '%s' already exists." % registration_name,
			)
		if GDSQLDatabase.open(
			StringName(payload["database"]),
			payload["data_root"],
		).is_successful():
			return _error(
				&"GDSQL_MCP_DATABASE_EXISTS",
				"Database '%s' already exists at the selected location." % payload["database"],
			)
		return _value(
			{
				"registration": String(registration_name),
				"database": payload["database"],
				"location": payload["location"],
				"storage_backend": payload["storage_backend"],
				"affected_tables": 0,
				"affected_rows": 0,
				"affected_roles": [],
			},
		)
	var registration := _workbench.get_registration(registration_name)
	if registration == null:
		return _error(
			&"GDSQL_MCP_REGISTRATION_NOT_FOUND",
			"Database registration '%s' was not found." % registration_name,
		)
	if operation == "rename_database":
		if StringName(payload["new_name"]) == registration.database_name:
			return _error(
				&"GDSQL_MCP_DATABASE_NAME_UNCHANGED",
				"The database already uses that name.",
			)
		var history := _history_store.load(registration.migration_stream)
		if not history.is_successful():
			return history
		if not (history.get_value() as Array[GDSQLMigrationDefinition]).is_empty():
			return _error(
				&"GDSQL_MCP_DATABASE_RENAME_MIGRATIONS",
				"A database with authored migration history cannot be renamed by this lifecycle surface.",
			)
	var opened := GDSQLRuntimeFactory.open_authoring_registration(registration)
	if not opened.is_successful():
		return opened
	if operation == "rename_database":
		var definition := opened.get_database().context.catalog.get_database(
			StringName(payload["new_name"]),
		)
		if definition != null:
			return _error(&"GDSQL_MCP_DATABASE_EXISTS", "The rename target already exists.")
	return _value(_existing_summary(registration))


func _apply(payload: Dictionary) -> GDSQLOperationResult:
	match String(payload["operation"]):
		"create_database":
			return _create(payload)
		"rename_database":
			return _rename(payload)
		"unregister_database":
			return _unregister(payload)
		"destroy_database":
			return _destroy(payload)
	return _error(&"GDSQL_MCP_DATABASE_OPERATION_INVALID", "Unsupported database operation.")


func _create(payload: Dictionary) -> GDSQLOperationResult:
	var database_name := StringName(payload["database"])
	var created := GDSQLDatabase.create(database_name, payload["data_root"])
	if not created.is_successful():
		return created
	var registration := GDSQLDatabaseRegistration.new(
		StringName(payload["registration"]),
		database_name,
		payload["data_root"],
		StringName(payload["storage_backend"]),
	)
	var added := _workbench.add_registration(registration)
	if not added.is_successful():
		var rollback := created.get_database().drop()
		added.diagnostics.merge(rollback.diagnostics)
	return added


func _rename(payload: Dictionary) -> GDSQLOperationResult:
	var registration := _workbench.get_registration(StringName(payload["registration"]))
	var old_name := registration.database_name
	var opened := GDSQLRuntimeFactory.open_authoring_registration(registration)
	if not opened.is_successful():
		return opened
	var database := opened.get_database()
	var renamed := database.rename(StringName(payload["new_name"]))
	if not renamed.is_successful():
		return renamed
	var registered := _workbench.update_database_name(registration.name, database.database_name)
	if not registered.is_successful():
		var rollback := database.rename(old_name)
		registered.diagnostics.merge(rollback.diagnostics)
	return registered


func _unregister(payload: Dictionary) -> GDSQLOperationResult:
	var registration := _workbench.get_registration(StringName(payload["registration"]))
	var opened := GDSQLRuntimeFactory.open_authoring_registration(registration)
	if not opened.is_successful():
		return opened
	var roles := _bound_roles(registration.name)
	var database := opened.get_database()
	var removed := _workbench.remove_registration(registration.name)
	if not removed.is_successful():
		return removed
	var unregistered := database.unregister()
	if not unregistered.is_successful():
		_restore_registration(registration, roles, unregistered)
		return unregistered
	return removed


func _destroy(payload: Dictionary) -> GDSQLOperationResult:
	var registration := _workbench.get_registration(StringName(payload["registration"]))
	var opened := GDSQLRuntimeFactory.open_authoring_registration(registration)
	if not opened.is_successful():
		return opened
	var roles := _bound_roles(registration.name)
	var removed := _workbench.remove_registration(registration.name)
	if not removed.is_successful():
		return removed
	var dropped := opened.get_database().drop()
	if not dropped.is_successful():
		_restore_registration(registration, roles, dropped)
		return dropped
	return removed


func _resolve_location(location: String, root_registration: StringName) -> String:
	if location == "registration_root":
		var registration := _workbench.get_registration(root_registration)
		return registration.data_root if registration != null else ""
	return String(_locations.get(location, ""))


func _existing_summary(registration: GDSQLDatabaseRegistration) -> Dictionary:
	var tables := 0
	var rows := 0
	var inspection := _workbench.get_inspection(registration.name)
	if inspection != null:
		tables = inspection.tables.size()
		for table in inspection.tables:
			rows += table.row_count
	var roles: Array[String] = []
	for binding in _workbench.snapshot.role_bindings:
		if binding.registration_name == registration.name:
			roles.append(String(binding.role))
	roles.sort()
	return {
		"registration": String(registration.name),
		"database": String(registration.database_name),
		"storage_backend": String(registration.storage_backend_id),
		"affected_tables": tables,
		"affected_rows": rows,
		"affected_roles": roles,
	}


func _bound_roles(registration_name: StringName) -> Array[StringName]:
	var roles: Array[StringName] = []
	for binding in _workbench.snapshot.role_bindings:
		if binding.registration_name == registration_name:
			roles.append(binding.role)
	return roles


func _restore_registration(
		registration: GDSQLDatabaseRegistration,
		roles: Array[StringName],
		result: GDSQLOperationResult,
) -> void:
	var restored := _workbench.add_registration(registration)
	result.diagnostics.merge(restored.diagnostics)
	if not restored.is_successful():
		return
	for role in roles:
		var rebound := _workbench.bind_role(role, registration.name)
		result.diagnostics.merge(rebound.diagnostics)


func _workspace_fingerprint(payload: Dictionary) -> String:
	var values: Array = []
	var registrations := _workbench.get_registrations()
	registrations.sort_custom(
		func(left: GDSQLDatabaseRegistration, right: GDSQLDatabaseRegistration) -> bool:
			return String(left.name) < String(right.name),
	)
	for registration in registrations:
		var schema := ""
		var opened := GDSQLRuntimeFactory.open_authoring_registration(registration)
		if opened.is_successful():
			schema = GDSQLSchemaFingerprint.compute(
				opened.get_database().context.catalog.get_database(registration.database_name),
			)
		values.append(
			[
				String(registration.name), String(registration.database_name),
				registration.data_root, String(registration.storage_backend_id),
				String(registration.migration_stream), schema,
			],
		)
	var roles: Array = []
	for binding in _workbench.snapshot.role_bindings:
		roles.append([String(binding.role), String(binding.registration_name)])
	roles.sort_custom(
		func(left: Variant, right: Variant) -> bool:
			return var_to_str(left) < var_to_str(right),
	)
	values.append(roles)
	values.append(payload)
	return var_to_str(CanonicalValue.serialize(values)).sha256_text()


func _cleanup_expired_tickets() -> void:
	for token in _tickets.keys():
		if (_tickets[token] as GDSQLMcpDatabaseMutationTicket).is_expired():
			_tickets.erase(token)


func _stale(message: String) -> GDSQLOperationResult:
	return _error(&"GDSQL_MCP_DATABASE_MUTATION_STALE", message + " Preview it again.")


func _value(value: Variant) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.value = value
	return result


func _success(data: Dictionary) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.value = {
		"surface_version": GDSQLMcpInspectionService.SURFACE_VERSION,
		"ok": true,
		"data": data,
		"diagnostics": [],
		"meta": { "scope": "current_project", "truncated": false, "next_cursor": "" },
	}
	return result


func _error(code: StringName, message: String) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
