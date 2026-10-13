class_name GDSQLMcpSetupAuthoringService
extends RefCounted
## Guarded setup-profile selection and durable logical-role binding.

signal committed

const Ticket = preload(
	"res://addons/gdsql/editor/integrations/mcp/authoring/setup/gdsql_mcp_setup_ticket.gd"
)
const HANDLE_TTL_MSEC := 120_000
const ROLES: Array[StringName] = [
	GDSQLDatabaseRegistry.CONTENT_ROLE,
	GDSQLDatabaseRegistry.SAVE_ROLE,
	GDSQLDatabaseRegistry.SETTINGS_ROLE,
]

var _workbench: GDSQLWorkbench
var _profile_store: GDSQLSetupProfileStore
var _tickets: Dictionary[String, GDSQLMcpSetupTicket] = { }


func _init(
		workbench: GDSQLWorkbench,
		profile_store: GDSQLSetupProfileStore = null,
) -> void:
	_workbench = workbench
	_profile_store = (
		profile_store if profile_store != null else GDSQLConfigFileSetupProfileStore.new()
	)


func preview(request: Dictionary) -> GDSQLOperationResult:
	_cleanup_expired()
	var operation := String(request.get("operation", "")).to_lower()
	var prepared := (
		_prepare_profile(request)
		if operation == "select_profile"
		else _prepare_role(request) if operation == "bind_role" else null
	)
	if prepared == null:
		return _error(
			&"GDSQL_MCP_SETUP_OPERATION_INVALID",
			"Operation must be 'select_profile' or 'bind_role'.",
		)
	if not prepared.is_successful():
		return prepared
	var ticket := Ticket.new()
	ticket.token = Crypto.new().generate_random_bytes(24).hex_encode()
	ticket.operation = operation
	ticket.payload = prepared.get_value()
	ticket.fingerprint = _fingerprint()
	ticket.expires_at_msec = Time.get_ticks_msec() + HANDLE_TTL_MSEC
	_tickets[ticket.token] = ticket
	var data: Dictionary = ticket.payload.duplicate(true)
	data.merge(
		{
			"kind": "setup_mutation_preview",
			"confirmation_handle": ticket.token,
			"expires_in_ms": HANDLE_TTL_MSEC,
			"destructive": false,
		},
	)
	return _success(data)


func commit(handle: String, confirmed: bool) -> GDSQLOperationResult:
	_cleanup_expired()
	if not confirmed:
		return _error(
			&"GDSQL_MCP_CONFIRMATION_REQUIRED",
			"The previewed setup mutation must be explicitly confirmed.",
		)
	if handle.is_empty() or not _tickets.has(handle):
		return _error(
			&"GDSQL_MCP_SETUP_HANDLE_INVALID",
			"The setup mutation handle is invalid, expired, or already used.",
		)
	var ticket := _tickets[handle] as GDSQLMcpSetupTicket
	_tickets.erase(handle)
	if ticket.fingerprint != _fingerprint():
		return _error(
			&"GDSQL_MCP_SETUP_STALE",
			"The setup profile, registrations, or role bindings changed after preview.",
		)
	var result: GDSQLOperationResult
	if ticket.operation == "select_profile":
		result = _profile_store.save_profile(
			GDSQLSetupProfile.from_id(ticket.payload["profile"]),
		)
	else:
		result = _workbench.bind_role(
			StringName(ticket.payload["role"]),
			StringName(ticket.payload["registration"]),
		)
	if not result.is_successful():
		return result
	committed.emit()
	return _success(
		{
			"kind": "setup_mutation_commit",
			"operation": ticket.operation,
			"profile": ticket.payload.get("profile", ""),
			"role": ticket.payload.get("role", ""),
			"registration": ticket.payload.get("registration", ""),
		},
	)


func _prepare_profile(request: Dictionary) -> GDSQLOperationResult:
	var unknown := _unknown(request, ["operation", "profile"])
	if not unknown.is_empty():
		return _error(&"GDSQL_MCP_SETUP_FIELD_UNKNOWN", unknown)
	var profile_id := StringName(request.get("profile", ""))
	var profile := GDSQLSetupProfile.from_id(profile_id)
	if not GDSQLSetupProfile.is_selectable(profile):
		return _error(
			&"GDSQL_MCP_SETUP_PROFILE_INVALID",
			"profile must be 'direct' or 'managed'.",
		)
	var loaded := _profile_store.load_profile()
	if not loaded.is_successful():
		return loaded
	var current := loaded.get_value() as GDSQLSetupProfile.Kind
	if current != GDSQLSetupProfile.Kind.UNSELECTED and current != profile:
		return _error(
			&"GDSQL_MCP_SETUP_PROFILE_MIGRATION_REQUIRED",
			"Changing setup profiles requires an explicit content migration; this tool only " \
					+ "performs initial selection.",
		)
	return _value(
		{
			"operation": "select_profile",
			"profile": String(profile_id),
			"previous_profile": String(GDSQLSetupProfile.get_id(current)),
			"already_selected": current == profile,
		},
	)


func _prepare_role(request: Dictionary) -> GDSQLOperationResult:
	var unknown := _unknown(request, ["operation", "role", "registration"])
	if not unknown.is_empty():
		return _error(&"GDSQL_MCP_SETUP_FIELD_UNKNOWN", unknown)
	var role := StringName(request.get("role", ""))
	var registration_name := StringName(request.get("registration", ""))
	if role not in ROLES:
		return _error(
			&"GDSQL_MCP_SETUP_ROLE_INVALID",
			"role must be 'content', 'save', or 'settings'.",
		)
	if _workbench == null or _workbench.get_registration(registration_name) == null:
		return _error(
			&"GDSQL_MCP_REGISTRATION_NOT_FOUND",
			"Database registration '%s' was not found." % registration_name,
		)
	for binding in _workbench.snapshot.role_bindings:
		if binding.role != role and binding.registration_name == registration_name:
			return _error(
				&"GDSQL_MCP_SETUP_REGISTRATION_IN_USE",
				"Registration '%s' is already bound to role '%s'." \
						% [registration_name, binding.role],
			)
	return _value(
		{
			"operation": "bind_role",
			"role": String(role),
			"registration": String(registration_name),
			"previous_registration": String(_registration_for_role(role)),
		},
	)


func _registration_for_role(role: StringName) -> StringName:
	if _workbench != null:
		for binding in _workbench.snapshot.role_bindings:
			if binding.role == role:
				return binding.registration_name
	return &""


func _fingerprint() -> String:
	var loaded := _profile_store.load_profile()
	var values: Array = [
		GDSQLSetupProfile.get_id(loaded.get_value()) if loaded.is_successful() else &"invalid",
	]
	if _workbench != null:
		var registrations: Array[String] = []
		for registration in _workbench.get_registrations():
			registrations.append("%s:%s" % [registration.name, registration.database_name])
		registrations.sort()
		var roles: Array[String] = []
		for binding in _workbench.snapshot.role_bindings:
			roles.append("%s:%s" % [binding.role, binding.registration_name])
		roles.sort()
		values.append(registrations)
		values.append(roles)
	return var_to_str(values).sha256_text()


func _cleanup_expired() -> void:
	for token in _tickets.keys():
		if (_tickets[token] as GDSQLMcpSetupTicket).is_expired():
			_tickets.erase(token)


func _unknown(values: Dictionary, allowed: Array[String]) -> String:
	for key in values:
		if String(key) not in allowed:
			return "Unknown field '%s'." % key
	return ""


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
