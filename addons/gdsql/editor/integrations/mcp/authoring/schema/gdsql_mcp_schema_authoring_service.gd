extends RefCounted
## Guarded catalog-plan authoring for the editor AI integration.

signal committed(registration_name: StringName)

const Decoder = preload("res://addons/gdsql/editor/integrations/mcp/authoring/schema/gdsql_mcp_schema_decoder.gd")
const Ticket = preload("res://addons/gdsql/editor/integrations/mcp/authoring/schema/gdsql_mcp_schema_mutation_ticket.gd")
const ResourceStorageContext = preload(
	"res://addons/gdsql/editor/integrations/mcp/authoring/storage/gdsql_mcp_resource_storage_context.gd"
)
const SchemaChangeContext = preload(
	"res://addons/gdsql/editor/integrations/mcp/authoring/migration/gdsql_mcp_schema_change_context.gd"
)
const HANDLE_TTL_MSEC := 120_000

var _workbench: GDSQLWorkbench
var _history_store: GDSQLMigrationHistoryStore
var _tickets: Dictionary[String, Ticket] = { }


func _init(
	workbench: GDSQLWorkbench,
	history_store: GDSQLMigrationHistoryStore,
) -> void:
	_workbench = workbench
	_history_store = history_store


func preview(request: Dictionary) -> GDSQLOperationResult:
	_cleanup_expired_tickets()
	var registration_name := StringName(request.get("registration", ""))
	var opened := _open_registration(registration_name)
	if not opened.is_successful():
		return opened
	var registration := _workbench.get_registration(registration_name)
	var loaded_history := _history_store.load(registration.migration_stream)
	if not loaded_history.is_successful():
		return loaded_history
	var history := loaded_history.get_value() as Array[GDSQLMigrationDefinition]
	if not history.is_empty():
		return _error(
			&"GDSQL_MCP_SCHEMA_MIGRATION_REQUIRED",
			"Direct schema changes are disabled because migration history is active. "
			+ "Author the change with gdsql_preview_migration.",
		)
	var database := opened.get_database()
	var table: GDSQLTableDefinition
	if request.get("table") is String:
		table = database.context.catalog.get_table(
			database.database_name,
			StringName(request["table"]),
		)
	var decoded := Decoder.decode(request, table)
	if not decoded.is_successful():
		return decoded
	var intent := decoded.get_value() as Dictionary
	var previewed := _preview(database, intent)
	if not previewed.is_successful():
		return previewed
	var plan := previewed.get_value() as GDSQLCatalogChangePlan
	var resource_storage_decisions := ResourceStorageContext.describe_intent(intent)
	var ticket := Ticket.new()
	ticket.token = Crypto.new().generate_random_bytes(24).hex_encode()
	ticket.operation = intent["operation"]
	ticket.registration_name = registration_name
	ticket.plan = plan
	ticket.expires_at_msec = Time.get_ticks_msec() + HANDLE_TTL_MSEC
	_tickets[ticket.token] = ticket
	return _success(
		{
			"kind": "schema_mutation_preview",
			"operation": ticket.operation,
			"registration": String(registration_name),
			"table": String(plan.table_name),
			"resulting_table": (
					String(plan.new_table_name)
					if plan.kind == GDSQLCatalogChangePlan.Kind.RENAME_TABLE
					else String(plan.table_name)
			),
			"summaries": plan.summaries.duplicate(),
			"affected_rows": plan.affected_rows,
			"destructive": plan.requires_confirmation(),
			"schema_change_decision": SchemaChangeContext.describe("direct", history.size()),
			"resource_storage_decisions": resource_storage_decisions,
			"confirmation_handle": ticket.token,
			"expires_in_ms": HANDLE_TTL_MSEC,
		},
	)


func commit(handle: String, confirmed: bool) -> GDSQLOperationResult:
	_cleanup_expired_tickets()
	if not confirmed:
		return _error(
			&"GDSQL_MCP_CONFIRMATION_REQUIRED",
			"The previewed schema mutation must be explicitly confirmed.",
		)
	if handle.is_empty() or not _tickets.has(handle):
		return _error(
			&"GDSQL_MCP_SCHEMA_HANDLE_INVALID",
			"The schema handle is invalid, expired, or already used.",
		)
	var ticket := _tickets[handle]
	_tickets.erase(handle)
	var opened := _open_registration(ticket.registration_name)
	if not opened.is_successful():
		return opened
	var database := opened.get_database()
	var plan := ticket.plan
	var applied := database.apply_change_plan(plan)
	if not applied.is_successful():
		return applied
	_workbench.refresh_inspections()
	committed.emit(ticket.registration_name)
	return _success(
		{
			"kind": "schema_mutation_commit",
			"operation": ticket.operation,
			"registration": String(ticket.registration_name),
			"table": String(plan.table_name),
			"resulting_table": (
					String(plan.new_table_name)
					if plan.kind == GDSQLCatalogChangePlan.Kind.RENAME_TABLE
					else String(plan.table_name)
			),
			"affected_rows": plan.affected_rows,
		},
	)


func _preview(
		database: GDSQLDatabase,
		intent: Dictionary,
) -> GDSQLOperationResult:
	match intent["operation"]:
		"create_table":
			return database.preview_create_table(intent["table_definition"])
		"rename_table":
			return database.preview_rename_table(intent["table_name"], intent["new_name"])
		"drop_table":
			return database.preview_drop_table(intent["table_name"])
		"alter_table":
			var alterations: Array[GDSQLTableAlteration] = []
			alterations.assign(intent["alterations"])
			return database.preview_alter_table(intent["table_name"], alterations)
	return _error(&"GDSQL_MCP_SCHEMA_OPERATION_INVALID", "Unknown schema operation.")


func _open_registration(registration_name: StringName) -> GDSQLDatabaseResult:
	if _workbench == null:
		return _database_error(
			&"GDSQL_MCP_WORKBENCH_REQUIRED",
			"The GDSQL workbench is unavailable.",
		)
	if registration_name == &"":
		return _database_error(
			&"GDSQL_MCP_REGISTRATION_REQUIRED",
			"A registration is required.",
		)
	var registration := _workbench.get_registration(registration_name)
	if registration == null:
		return _database_error(
			&"GDSQL_MCP_REGISTRATION_NOT_FOUND",
			"Database registration '%s' was not found." % registration_name,
		)
	return GDSQLRuntimeFactory.open_authoring_registration(registration)


func _cleanup_expired_tickets() -> void:
	for token in _tickets.keys():
		if _tickets[token].is_expired():
			_tickets.erase(token)


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


func _database_error(code: StringName, message: String) -> GDSQLDatabaseResult:
	var result := GDSQLDatabaseResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result


func _error(code: StringName, message: String) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
