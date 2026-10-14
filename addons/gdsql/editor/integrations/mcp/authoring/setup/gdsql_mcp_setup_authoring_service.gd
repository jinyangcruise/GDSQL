class_name GDSQLMcpSetupAuthoringService
extends RefCounted
## Guarded project setup, runtime installation, save slots, and managed cache.

signal committed

const Ticket = preload(
	"res://addons/gdsql/editor/integrations/mcp/authoring/setup/gdsql_mcp_setup_ticket.gd"
)
const HANDLE_TTL_MSEC := 120_000
const RUNTIME_AUTOLOAD_SETTING := "autoload/GDSQLRuntime"
const RUNTIME_NODE_PATH := "res://addons/gdsql/runtime/gdsql_runtime_node.tscn"
const ROLES: Array[StringName] = [
	GDSQLDatabaseRegistry.CONTENT_ROLE,
	GDSQLDatabaseRegistry.SAVE_ROLE,
	GDSQLDatabaseRegistry.SETTINGS_ROLE,
]

var _workbench: GDSQLWorkbench
var _profile_store: GDSQLSetupProfileStore
var _history_store: GDSQLMigrationHistoryStore
var _state_store: GDSQLMigrationSchemaStateStore
var _runtime_path_provider: Callable
var _runtime_installer: Callable
var _managed_configuration_store: GDSQLManagedContentConfigurationStore
var _package_discovery: GDSQLContentPackageDiscovery
var _package_resolver: GDSQLContentPackageResolver
var _fingerprint_provider: GDSQLContentPackageFingerprintProvider
var _cache_manager: GDSQLContentCacheManager
var _tickets: Dictionary[String, GDSQLMcpSetupTicket] = { }


func _init(
		workbench: GDSQLWorkbench,
		profile_store: GDSQLSetupProfileStore = null,
		history_store: GDSQLMigrationHistoryStore = null,
		state_store: GDSQLMigrationSchemaStateStore = null,
		runtime_path_provider: Callable = Callable(),
		runtime_installer: Callable = Callable(),
		managed_configuration_store: GDSQLManagedContentConfigurationStore = null,
		package_discovery: GDSQLContentPackageDiscovery = null,
		package_resolver: GDSQLContentPackageResolver = null,
		fingerprint_provider: GDSQLContentPackageFingerprintProvider = null,
		cache_manager: GDSQLContentCacheManager = null,
) -> void:
	_workbench = workbench
	_profile_store = (
		profile_store if profile_store != null else GDSQLConfigFileSetupProfileStore.new()
	)
	_history_store = (
		history_store if history_store != null else GDSQLConfigFileMigrationHistoryStore.new()
	)
	_state_store = (
		state_store if state_store != null else GDSQLConfigFileMigrationSchemaStateStore.new()
	)
	_runtime_path_provider = (
		runtime_path_provider
		if runtime_path_provider.is_valid()
		else Callable(self, "_current_runtime_path")
	)
	_runtime_installer = (
		runtime_installer
		if runtime_installer.is_valid()
		else Callable(self, "_install_runtime")
	)
	_managed_configuration_store = (
		managed_configuration_store
		if managed_configuration_store != null
		else GDSQLConfigFileManagedContentConfigurationStore.new()
	)
	_package_discovery = (
		package_discovery
		if package_discovery != null
		else GDSQLConfigFileContentPackageDiscovery.new()
	)
	_package_resolver = (
		package_resolver if package_resolver != null else GDSQLContentPackageResolver.new()
	)
	_fingerprint_provider = (
		fingerprint_provider
		if fingerprint_provider != null
		else GDSQLConfigFileContentPackageFingerprintProvider.new()
	)
	_cache_manager = (
		cache_manager
		if cache_manager != null
		else GDSQLContentCacheManager.new(
			GDSQLContentOverlayLoader.new(GDSQLConfigFileContentPackageLayerReader.new()),
			_fingerprint_provider,
			GDSQLConfigFileContentCacheStore.new(),
		)
	)


func preview(request: Dictionary) -> GDSQLOperationResult:
	_cleanup_expired()
	var operation := String(request.get("operation", "")).to_lower()
	var prepared: GDSQLOperationResult
	match operation:
		"select_profile":
			prepared = _prepare_profile(request)
		"bind_role":
			prepared = _prepare_role(request)
		"install_runtime_adapter":
			prepared = _prepare_runtime(request)
		"create_save_slot":
			prepared = _prepare_create_save(request)
		"delete_save_slot":
			prepared = _prepare_delete_save(request)
		"build_managed_cache":
			prepared = _prepare_managed_cache(request)
	if prepared == null:
		return _error(
			&"GDSQL_MCP_SETUP_OPERATION_INVALID",
			"Unknown setup operation.",
		)
	if not prepared.is_successful():
		return prepared
	var ticket := Ticket.new()
	ticket.token = Crypto.new().generate_random_bytes(24).hex_encode()
	ticket.operation = operation
	ticket.payload = prepared.get_value()
	ticket.fingerprint = _fingerprint(ticket.payload)
	ticket.expires_at_msec = Time.get_ticks_msec() + HANDLE_TTL_MSEC
	_tickets[ticket.token] = ticket
	var data: Dictionary = ticket.payload.duplicate(true)
	data.merge(
		{
			"kind": "setup_mutation_preview",
			"confirmation_handle": ticket.token,
			"expires_in_ms": HANDLE_TTL_MSEC,
			"destructive": operation == "delete_save_slot",
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
	if ticket.fingerprint != _fingerprint(ticket.payload):
		return _error(
			&"GDSQL_MCP_SETUP_STALE",
			"The setup profile, registrations, or role bindings changed after preview.",
		)
	var result: GDSQLOperationResult
	match ticket.operation:
		"select_profile":
			result = _profile_store.save_profile(
				GDSQLSetupProfile.from_id(ticket.payload["profile"]),
			)
		"bind_role":
			result = _workbench.bind_role(
				StringName(ticket.payload["role"]),
				StringName(ticket.payload["registration"]),
			)
		"install_runtime_adapter":
			result = _runtime_installer.call() as GDSQLOperationResult
		"create_save_slot":
			result = _create_save_slot(ticket.payload)
		"delete_save_slot":
			result = _delete_save_slot(ticket.payload)
		"build_managed_cache":
			result = _build_managed_cache()
	if not result.is_successful():
		return result
	committed.emit()
	var response := {
			"kind": "setup_mutation_commit",
			"operation": ticket.operation,
			"profile": ticket.payload.get("profile", ""),
			"role": ticket.payload.get("role", ""),
			"registration": ticket.payload.get("registration", ""),
			"runtime_path": ticket.payload.get("runtime_path", ""),
			"save_slot": ticket.payload.get("save_slot", ""),
			"fallback_registration": ticket.payload.get("fallback_registration", ""),
	}
	if result.get_value() is Dictionary:
		response.merge(result.get_value())
	return _success(response)


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


func _prepare_runtime(request: Dictionary) -> GDSQLOperationResult:
	var unknown := _unknown(request, ["operation"])
	if not unknown.is_empty():
		return _error(&"GDSQL_MCP_SETUP_FIELD_UNKNOWN", unknown)
	var current := String(_runtime_path_provider.call()).trim_prefix("*")
	if not current.is_empty() and current != RUNTIME_NODE_PATH:
		return _error(
			&"GDSQL_RUNTIME_AUTOLOAD_NAME_IN_USE",
			"The GDSQLRuntime autoload name is already used by '%s'." % current,
		)
	return _value(
		{
			"operation": "install_runtime_adapter",
			"runtime_path": RUNTIME_NODE_PATH,
			"already_installed": current == RUNTIME_NODE_PATH,
		},
	)


func _prepare_create_save(request: Dictionary) -> GDSQLOperationResult:
	var unknown := _unknown(request, ["operation", "save_slot", "storage_backend"])
	if not unknown.is_empty():
		return _error(&"GDSQL_MCP_SETUP_FIELD_UNKNOWN", unknown)
	var slot := String(request.get("save_slot", "")).strip_edges()
	if not slot.is_valid_identifier():
		return _error(
			&"GDSQL_MCP_SAVE_SLOT_NAME_INVALID",
			"save_slot must be a valid identifier.",
		)
	if _workbench.get_registration(StringName(slot)) != null:
		return _error(
			&"GDSQL_MCP_SAVE_SLOT_EXISTS",
			"Save slot registration '%s' already exists." % slot,
		)
	var backend := StringName(request.get("storage_backend", "configfile"))
	if not GDSQLStorageBackendIds.is_implemented(backend):
		return _error(
			&"GDSQL_STORAGE_BACKEND_UNAVAILABLE",
			"storage_backend must be 'configfile' or 'memory'.",
		)
	var template_name := _registration_for_role(GDSQLDatabaseRegistry.SAVE_ROLE)
	var template := _workbench.get_registration(template_name)
	if template == null:
		return _error(
			&"GDSQL_MCP_SAVE_TEMPLATE_REQUIRED",
			"Create and bind the first save database before creating additional slots.",
		)
	var context := _save_template_context(template)
	if not context.is_successful():
		return context
	var data := context.get_value() as Dictionary
	return _value(
		{
			"operation": "create_save_slot",
			"save_slot": slot,
			"registration": slot,
			"data_root": GDSQLSaveSlotDeletionPlan.STANDARD_SAVE_SLOTS_ROOT.path_join(slot),
			"database": String(template.database_name),
			"storage_backend": String(backend),
			"template_registration": String(template.name),
			"migration_stream": String(template.migration_stream),
			"table_count": (data["definition"] as GDSQLDatabaseDefinition).tables.size(),
			"copies_rows": false,
			"becomes_active": true,
		},
	)


func _prepare_delete_save(request: Dictionary) -> GDSQLOperationResult:
	var unknown := _unknown(request, ["operation", "registration"])
	if not unknown.is_empty():
		return _error(&"GDSQL_MCP_SETUP_FIELD_UNKNOWN", unknown)
	var registration_name := StringName(request.get("registration", ""))
	var planned := GDSQLSaveSlotDeletionPlan.build(
		_workbench.get_registration(registration_name),
		_registration_for_role(GDSQLDatabaseRegistry.SAVE_ROLE),
		_workbench.get_registrations(),
	)
	if not planned.is_successful():
		return planned
	var plan := planned.get_value() as GDSQLSaveSlotDeletionPlan
	var inspection := _workbench.get_inspection(registration_name)
	var rows := 0
	if inspection != null:
		for table in inspection.tables:
			rows += table.row_count
	return _value(
		{
			"operation": "delete_save_slot",
			"save_slot": String(registration_name),
			"registration": String(registration_name),
			"database": String(plan.database_name),
			"was_active": plan.was_active,
			"fallback_registration": String(plan.fallback_registration_name),
			"affected_tables": inspection.tables.size() if inspection != null else 0,
			"affected_rows": rows,
		},
	)


func _prepare_managed_cache(request: Dictionary) -> GDSQLOperationResult:
	var unknown := _unknown(request, ["operation"])
	if not unknown.is_empty():
		return _error(&"GDSQL_MCP_SETUP_FIELD_UNKNOWN", unknown)
	var profile := _profile_store.load_profile()
	if not profile.is_successful():
		return profile
	if profile.get_value() != GDSQLSetupProfile.Kind.MANAGED:
		return _error(
			&"GDSQL_MCP_MANAGED_PROFILE_REQUIRED",
			"Select the Managed Content profile before building its effective cache.",
		)
	var context := _managed_context(false)
	if not context.is_successful():
		return context
	var packages: Array[Dictionary] = []
	for source in context.get_value()["packages"]:
		var package := source as GDSQLContentPackageSource
		packages.append(
			{
				"package_id": String(package.manifest.package_id),
				"version": package.manifest.version,
				"kind": String(GDSQLContentPackageKind.get_id(package.manifest.kind)),
			},
		)
	return _value(
		{
			"operation": "build_managed_cache",
			"packages": packages,
			"package_count": packages.size(),
			"source_database": String(GDSQLContentOverlayLoader.DEFAULT_SOURCE_DATABASE),
			"effective_database": String(
				GDSQLContentOverlayLoader.DEFAULT_EFFECTIVE_DATABASE,
			),
		},
	)


func _registration_for_role(role: StringName) -> StringName:
	if _workbench != null:
		for binding in _workbench.snapshot.role_bindings:
			if binding.role == role:
				return binding.registration_name
	return &""


func _fingerprint(payload: Dictionary = { }) -> String:
	var loaded := _profile_store.load_profile()
	var values: Array = [
		GDSQLSetupProfile.get_id(loaded.get_value()) if loaded.is_successful() else &"invalid",
	]
	if _workbench != null:
		var registrations: Array[String] = []
		for registration in _workbench.get_registrations():
			var schema := ""
			var opened := GDSQLRuntimeFactory.open_authoring_registration(registration)
			if opened.is_successful():
				schema = GDSQLSchemaFingerprint.compute(
					opened.get_database().context.catalog.get_database(registration.database_name),
				)
			registrations.append(
				"%s:%s:%s" % [registration.name, registration.database_name, schema],
			)
		registrations.sort()
		var roles: Array[String] = []
		for binding in _workbench.snapshot.role_bindings:
			roles.append("%s:%s" % [binding.role, binding.registration_name])
		roles.sort()
		values.append(registrations)
		values.append(roles)
	values.append(String(_runtime_path_provider.call()))
	if payload.get("operation") == "create_save_slot":
		var loaded_history := _history_store.load(StringName(payload["migration_stream"]))
		var history: Array[GDSQLMigrationDefinition] = []
		if loaded_history.is_successful():
			history.assign(loaded_history.get_value())
		values.append(
			GDSQLMigrationHistoryChecksum.compute(history, history.size())
			if loaded_history.is_successful()
			else "invalid",
		)
	if payload.get("operation") == "build_managed_cache":
		var context := _managed_context(true)
		values.append(
			context.get_value()["fingerprints"]
			if context.is_successful()
			else ["invalid"],
		)
	return var_to_str(values).sha256_text()


func _managed_context(include_fingerprints: bool) -> GDSQLOperationResult:
	var loaded := _managed_configuration_store.load_configuration()
	if not loaded.is_successful():
		return loaded
	var configuration := loaded.get_value() as GDSQLManagedContentConfiguration
	var discovered := _package_discovery.discover(
		configuration.base_package_root,
		configuration.package_container_roots,
	)
	if not discovered.is_successful():
		return discovered
	var packages: Array[GDSQLContentPackageSource] = []
	packages.assign(discovered.get_value())
	var resolved := _package_resolver.resolve(packages, configuration.enabled_package_ids)
	if not resolved.is_successful():
		return resolved
	var fingerprints: Array[String] = []
	if include_fingerprints:
		for package in resolved.ordered_packages:
			var fingerprinted := _fingerprint_provider.fingerprint(package)
			if not fingerprinted.is_successful():
				return fingerprinted
			var fingerprint := fingerprinted.get_value() as GDSQLContentPackageFingerprint
			fingerprints.append(
				"%s:%s:%s" % [
					fingerprint.package_id,
					fingerprint.version,
					fingerprint.content_hash,
				],
			)
	return _value(
		{
			"packages": resolved.ordered_packages,
			"fingerprints": fingerprints,
		},
	)


func _save_template_context(
		template: GDSQLDatabaseRegistration,
) -> GDSQLOperationResult:
	var opened := GDSQLRuntimeFactory.open_authoring_registration(template)
	if not opened.is_successful():
		return opened
	var database := opened.get_database()
	var loaded := _history_store.load(template.migration_stream)
	if not loaded.is_successful():
		return loaded
	var history := loaded.get_value() as Array[GDSQLMigrationDefinition]
	var pending := database.preview_migrations(history)
	if not pending.is_successful():
		return pending
	if not pending.is_up_to_date():
		return _error(
			&"GDSQL_FRESH_SAVE_TEMPLATE_PENDING",
			"Apply the active save slot's pending migration before creating another slot.",
		)
	var definition := database.context.catalog.get_database(template.database_name)
	var state := GDSQLMigrationSchemaState.from_history(
		template.migration_stream,
		template.database_name,
		history,
		GDSQLSchemaFingerprint.compute(definition),
	)
	return _value({ "definition": definition, "history": history, "state": state })


func _create_save_slot(payload: Dictionary) -> GDSQLOperationResult:
	var template := _workbench.get_registration(payload["template_registration"])
	var context := _save_template_context(template)
	if not context.is_successful():
		return context
	var values := context.get_value() as Dictionary
	var previous_state := _state_store.load(template.migration_stream)
	if not previous_state.is_successful():
		return previous_state
	var old_state := previous_state.get_value() as GDSQLMigrationSchemaState
	var saved_state := _state_store.save(
		values["state"],
		old_state.history_checksum if old_state != null else "",
	)
	if not saved_state.is_successful():
		return saved_state
	var created := GDSQLDatabase.create(payload["database"], payload["data_root"])
	if not created.is_successful():
		return created
	var database := created.get_database()
	var provisioned := GDSQLEditorFreshSaveProvisioner.new().provision(
		values["definition"], database, values["history"], values["state"],
	)
	if not provisioned.is_successful():
		database.drop()
		return provisioned
	var registration := GDSQLDatabaseRegistration.new(
		StringName(payload["registration"]),
		StringName(payload["database"]),
		String(payload["data_root"]),
		StringName(payload["storage_backend"]),
		StringName(payload["migration_stream"]),
	)
	var registered := _workbench.add_registration(registration)
	if not registered.is_successful():
		database.drop()
		return registered
	var bound := _workbench.bind_role(GDSQLDatabaseRegistry.SAVE_ROLE, registration.name)
	if not bound.is_successful():
		_workbench.remove_registration(registration.name)
		database.drop()
		return bound
	_workbench.refresh_inspections()
	return _value(registration)


func _delete_save_slot(payload: Dictionary) -> GDSQLOperationResult:
	var registration_name := StringName(payload["registration"])
	var registration := _workbench.get_registration(registration_name)
	var planned := GDSQLSaveSlotDeletionPlan.build(
		registration,
		_registration_for_role(GDSQLDatabaseRegistry.SAVE_ROLE),
		_workbench.get_registrations(),
	)
	if not planned.is_successful():
		return planned
	var plan := planned.get_value() as GDSQLSaveSlotDeletionPlan
	var opened := GDSQLRuntimeFactory.open_authoring_registration(registration)
	if not opened.is_successful():
		return opened
	var removed := (
		_workbench.remove_registration_and_rebind(
			registration_name,
			GDSQLDatabaseRegistry.SAVE_ROLE,
			plan.fallback_registration_name,
		)
		if plan.was_active and plan.fallback_registration_name != &""
		else _workbench.remove_registration(registration_name)
	)
	if not removed.is_successful():
		return removed
	var dropped := opened.get_database().drop()
	if dropped.is_successful():
		return dropped
	_workbench.add_registration(registration)
	if plan.was_active:
		_workbench.bind_role(GDSQLDatabaseRegistry.SAVE_ROLE, registration_name)
	return dropped


func _build_managed_cache() -> GDSQLOperationResult:
	var context := _managed_context(false)
	if not context.is_successful():
		return context
	var packages: Array[GDSQLContentPackageSource] = []
	packages.assign(context.get_value()["packages"])
	var cached := _cache_manager.ensure_cache(packages)
	var result := GDSQLOperationResult.new()
	result.diagnostics.merge(cached.diagnostics)
	if cached.is_successful():
		result.value = {
			"cache_status": "rebuilt" if cached.was_rebuilt() else "current",
			"package_count": cached.manifest.packages.size(),
			"effective_database": String(cached.manifest.effective_database_name),
		}
	return result


func _current_runtime_path() -> String:
	return String(ProjectSettings.get_setting(RUNTIME_AUTOLOAD_SETTING, ""))


func _install_runtime() -> GDSQLOperationResult:
	var current := _current_runtime_path().trim_prefix("*")
	if current == RUNTIME_NODE_PATH:
		return _value(true)
	if not current.is_empty():
		return _error(
			&"GDSQL_RUNTIME_AUTOLOAD_NAME_IN_USE",
			"The GDSQLRuntime autoload name is already used by '%s'." % current,
		)
	ProjectSettings.set_setting(RUNTIME_AUTOLOAD_SETTING, "*%s" % RUNTIME_NODE_PATH)
	var save_error := ProjectSettings.save()
	if save_error != OK:
		ProjectSettings.clear(RUNTIME_AUTOLOAD_SETTING)
		return _error(
			&"GDSQL_RUNTIME_AUTOLOAD_SAVE_FAILED",
			"Could not save the GDSQLRuntime autoload setting: %s." \
					% error_string(save_error),
		)
	return _value(true)


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
