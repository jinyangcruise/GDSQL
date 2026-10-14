class_name GDSQLMcpMigrationAuthoringService
extends RefCounted
## Preview/commit authoring over the canonical migration history and database API.

signal committed(registration_name: StringName)

const SchemaDecoder = preload(
	"res://addons/gdsql/editor/integrations/mcp/authoring/schema/gdsql_mcp_schema_decoder.gd"
)
const QueryDecoder = preload(
	"res://addons/gdsql/editor/integrations/mcp/query/gdsql_mcp_query_decoder.gd"
)
const ScalarCodec = preload(
	"res://addons/gdsql/editor/integrations/mcp/query/gdsql_mcp_scalar_codec.gd"
)
const Ticket = preload(
	"res://addons/gdsql/editor/integrations/mcp/authoring/migration/gdsql_mcp_migration_ticket.gd"
)
const SchemaChangeContext = preload(
	"res://addons/gdsql/editor/integrations/mcp/authoring/migration/gdsql_mcp_schema_change_context.gd"
)
const HANDLE_TTL_MSEC := 120_000
const MAX_STEPS := 16
const MAX_ASSIGNMENTS := 32

var _workbench: GDSQLWorkbench
var _history_store: GDSQLMigrationHistoryStore
var _state_store: GDSQLMigrationSchemaStateStore
var _tickets: Dictionary[String, GDSQLMcpMigrationTicket] = { }


func _init(
		workbench: GDSQLWorkbench,
		history_store: GDSQLMigrationHistoryStore,
		state_store: GDSQLMigrationSchemaStateStore,
) -> void:
	_workbench = workbench
	_history_store = history_store
	_state_store = state_store


func preview(request: Dictionary) -> GDSQLOperationResult:
	_cleanup_expired()
	var unknown := _unknown_key(
		request,
		["registration", "migration_id", "description", "steps"],
	)
	if not unknown.is_empty():
		return _error(&"GDSQL_MCP_MIGRATION_FIELD_UNKNOWN", unknown)
	var registration_name := StringName(request.get("registration", ""))
	var target := _open(registration_name)
	if not target.is_successful():
		return target
	var registration := _workbench.get_registration(registration_name)
	var database := target.get_database()
	var loaded := _history_store.load(registration.migration_stream)
	if not loaded.is_successful():
		return loaded
	var history := loaded.get_value() as Array[GDSQLMigrationDefinition]
	var history_count_before := history.size()
	var definition: GDSQLMigrationDefinition
	var persisted := true
	if request.has("steps") or request.has("migration_id") or request.has("description"):
		var current := database.preview_migrations(history)
		if not current.is_successful():
			return current
		if not current.is_up_to_date():
			return _error(
				&"GDSQL_MCP_MIGRATION_PENDING",
				"Apply the current pending migration before authoring another.",
			)
		var decoded := _decode_definition(request, registration_name, database)
		if not decoded.is_successful():
			return decoded
		definition = decoded.get_value()
		persisted = false
		history.append(definition)
	var planned := database.preview_migrations(history)
	if not planned.is_successful():
		return planned
	if planned.is_up_to_date():
		return _success(
			{
				"kind": "migration_status",
				"registration": String(registration_name),
				"history_count": history.size(),
				"up_to_date": true,
				"schema_change_decision": SchemaChangeContext.describe(
					"migration",
					history_count_before,
				),
			},
		)
	var plan := planned.next_plan
	if definition != null and plan.migration.checksum != definition.checksum:
		return _error(
			&"GDSQL_MCP_MIGRATION_ORDER_INVALID",
			"The authored migration is not the next applicable history entry.",
		)
	definition = plan.migration
	var ticket := Ticket.new()
	ticket.token = Crypto.new().generate_random_bytes(24).hex_encode()
	ticket.registration_name = registration_name
	ticket.definition = definition
	ticket.expected_history_count = history.size() - (0 if persisted else 1)
	ticket.definition_persisted = persisted
	ticket.plan_fingerprint = _plan_fingerprint(plan)
	ticket.expires_at_msec = Time.get_ticks_msec() + HANDLE_TTL_MSEC
	_tickets[ticket.token] = ticket
	return _success(
		{
			"kind": "migration_preview",
			"registration": String(registration_name),
			"migration_stream": String(registration.migration_stream),
			"migration_id": definition.migration_id,
			"description": definition.description,
			"definition_persisted": persisted,
			"summaries": plan.summaries(),
			"affected_rows": plan.affected_rows(),
			"destructive": plan.requires_confirmation(),
			"schema_change_decision": SchemaChangeContext.describe(
				"migration",
				history_count_before,
			),
			"confirmation_handle": ticket.token,
			"expires_in_ms": HANDLE_TTL_MSEC,
		},
	)


func commit(handle: String, confirmed: bool) -> GDSQLOperationResult:
	_cleanup_expired()
	if not confirmed:
		return _error(
			&"GDSQL_MCP_CONFIRMATION_REQUIRED",
			"The previewed migration must be explicitly confirmed.",
		)
	if handle.is_empty() or not _tickets.has(handle):
		return _error(
			&"GDSQL_MCP_MIGRATION_HANDLE_INVALID",
			"The migration handle is invalid, expired, or already used.",
		)
	var ticket := _tickets[handle] as GDSQLMcpMigrationTicket
	_tickets.erase(handle)
	var target := _open(ticket.registration_name)
	if not target.is_successful():
		return target
	var registration := _workbench.get_registration(ticket.registration_name)
	var database := target.get_database()
	var loaded := _history_store.load(registration.migration_stream)
	if not loaded.is_successful():
		return loaded
	var history := loaded.get_value() as Array[GDSQLMigrationDefinition]
	if not ticket.definition_persisted:
		if history.size() != ticket.expected_history_count:
			return _stale()
		history.append(ticket.definition)
	var current := database.preview_migrations(history)
	if not current.is_successful() or current.next_plan == null \
			or _plan_fingerprint(current.next_plan) != ticket.plan_fingerprint:
		return _stale()
	if not ticket.definition_persisted:
		var appended := _history_store.append(
			registration.migration_stream,
			ticket.definition,
			ticket.expected_history_count,
		)
		if not appended.is_successful():
			return appended
	var applied := database.apply_migration(current.next_plan)
	if not applied.is_successful():
		return applied
	_workbench.refresh_inspections()
	var state_synchronized := _synchronize_state(registration, database, history)
	committed.emit(ticket.registration_name)
	return _success(
		{
			"kind": "migration_commit",
			"registration": String(ticket.registration_name),
			"migration_id": ticket.definition.migration_id,
			"affected_rows": current.next_plan.affected_rows(),
			"schema_state_synchronized": state_synchronized,
		},
	)


func _decode_definition(
		request: Dictionary,
		registration_name: StringName,
		database: GDSQLDatabase,
) -> GDSQLOperationResult:
	if not request.get("migration_id") is String \
			or not GDSQLMigrationDefinition.is_valid_id(request["migration_id"]):
		return _error(
			&"GDSQL_MCP_MIGRATION_ID_INVALID",
			"migration_id must be a valid, stable migration identifier.",
		)
	if not request.get("description") is String \
			or String(request["description"]).strip_edges().is_empty():
		return _error(
			&"GDSQL_MCP_MIGRATION_DESCRIPTION_REQUIRED",
			"description must be a non-empty string.",
		)
	if not request.get("steps") is Array:
		return _error(&"GDSQL_MCP_MIGRATION_STEPS_INVALID", "steps must be an array.")
	var raw_steps := request["steps"] as Array
	if raw_steps.is_empty() or raw_steps.size() > MAX_STEPS:
		return _error(
			&"GDSQL_MCP_MIGRATION_STEP_LIMIT",
			"A migration requires between 1 and %d steps." % MAX_STEPS,
		)
	var steps: Array[GDSQLMigrationStep] = []
	for raw_step in raw_steps:
		if not raw_step is Dictionary:
			return _error(
				&"GDSQL_MCP_MIGRATION_STEP_INVALID",
				"Every migration step must be an object.",
			)
		var decoded := _decode_step(raw_step, registration_name, database)
		if not decoded.is_successful():
			return decoded
		steps.append(decoded.get_value())
	var definition := GDSQLMigrationDefinition.new(
		request["migration_id"],
		String(request["description"]).strip_edges(),
		steps,
	)
	if not definition.is_valid():
		return _error(
			&"GDSQL_MCP_MIGRATION_INVALID",
			"The decoded migration definition is invalid.",
		)
	return _value(definition)


func _decode_step(
		raw: Dictionary,
		registration_name: StringName,
		database: GDSQLDatabase,
) -> GDSQLOperationResult:
	match String(raw.get("kind", "")).to_lower():
		"schema":
			var request := raw.duplicate(true)
			request.erase("kind")
			request["registration"] = String(registration_name)
			var table: GDSQLTableDefinition
			if request.get("table") is String:
				table = database.context.catalog.get_table(
					database.database_name,
					StringName(request["table"]),
				)
			var decoded := SchemaDecoder.decode(request, table)
			if not decoded.is_successful():
				return decoded
			return _schema_step(decoded.get_value())
		"data_update":
			return _data_step(raw, database)
	return _error(
		&"GDSQL_MCP_MIGRATION_STEP_KIND_INVALID",
		"Migration step kind must be 'schema' or 'data_update'.",
	)


func _schema_step(intent: Dictionary) -> GDSQLOperationResult:
	match intent["operation"]:
		"create_table":
			return _value(GDSQLSchemaMigrationStep.create_table(intent["table_definition"]))
		"rename_table":
			return _value(
				GDSQLSchemaMigrationStep.rename_table(
					intent["table_name"],
					intent["new_name"],
				),
			)
		"drop_table":
			return _value(GDSQLSchemaMigrationStep.drop_table(intent["table_name"]))
		"alter_table":
			var alterations: Array[GDSQLTableAlteration] = []
			alterations.assign(intent["alterations"])
			return _value(GDSQLSchemaMigrationStep.new(intent["table_name"], alterations))
	return _error(&"GDSQL_MCP_MIGRATION_STEP_INVALID", "Unknown schema migration step.")


func _data_step(raw: Dictionary, database: GDSQLDatabase) -> GDSQLOperationResult:
	var unknown := _unknown_key(raw, ["kind", "table", "values", "where"])
	if not unknown.is_empty():
		return _error(&"GDSQL_MCP_MIGRATION_STEP_FIELD_UNKNOWN", unknown)
	var table_name := StringName(raw.get("table", ""))
	var table := database.context.catalog.get_table(database.database_name, table_name)
	if table == null:
		return _error(
			&"GDSQL_MCP_TABLE_NOT_FOUND",
			"Table '%s' was not found." % table_name,
		)
	if not raw.get("values") is Dictionary:
		return _error(&"GDSQL_MCP_MIGRATION_VALUES_INVALID", "values must be an object.")
	var values := raw["values"] as Dictionary
	if values.is_empty() or values.size() > MAX_ASSIGNMENTS:
		return _error(
			&"GDSQL_MCP_MIGRATION_ASSIGNMENT_LIMIT",
			"A data step requires between 1 and %d assignments." % MAX_ASSIGNMENTS,
		)
	var assignments: Array[GDSQLColumnAssignment] = []
	var columns: Array[String] = []
	for key in values:
		columns.append(String(key))
	columns.sort()
	for key in columns:
		var column := table.get_column(StringName(key))
		var normalized := ScalarCodec.normalize_for_column(values[key], column)
		if not normalized.is_successful():
			return normalized
		assignments.append(
			GDSQLColumnAssignment.new(
				StringName(key),
				GDSQLLiteralExpression.new(normalized.get_value()),
			),
		)
	var raw_where: Variant = raw.get("where", { })
	if not raw_where is Dictionary:
		return _error(&"GDSQL_MCP_MIGRATION_WHERE_INVALID", "where must be an object.")
	var predicate := QueryDecoder.decode(raw_where, table)
	if not predicate.is_successful():
		return predicate
	return _value(
		GDSQLDataMigrationStep.new(
			table_name,
			assignments,
			predicate.get_value() as GDSQLQueryExpression,
		),
	)


func _synchronize_state(
		registration: GDSQLDatabaseRegistration,
		database: GDSQLDatabase,
		history: Array[GDSQLMigrationDefinition],
) -> bool:
	var fingerprint := GDSQLSchemaFingerprint.compute(
		database.context.catalog.get_database(database.database_name),
	)
	var state := GDSQLMigrationSchemaState.from_history(
		registration.migration_stream,
		registration.database_name,
		history,
		fingerprint,
	)
	var loaded := _state_store.load(registration.migration_stream)
	if not loaded.is_successful():
		return false
	var previous := loaded.get_value() as GDSQLMigrationSchemaState
	return _state_store.save(
		state,
		previous.history_checksum if previous != null else "",
	).is_successful()


func _open(registration_name: StringName) -> GDSQLDatabaseResult:
	if _workbench == null or _history_store == null or _state_store == null:
		return _database_error(
			&"GDSQL_MCP_MIGRATION_SERVICES_REQUIRED",
			"Migration authoring services are unavailable.",
		)
	var registration := _workbench.get_registration(registration_name)
	if registration == null:
		return _database_error(
			&"GDSQL_MCP_REGISTRATION_NOT_FOUND",
			"Database registration '%s' was not found." % registration_name,
		)
	return GDSQLRuntimeFactory.open_authoring_registration(registration)


func _plan_fingerprint(plan: GDSQLMigrationStepPlan) -> String:
	return var_to_str(
		[
			plan.migration.checksum,
			plan.expected_ledger_revision,
			plan.affected_rows(),
			plan.summaries(),
		],
	).sha256_text()


func _cleanup_expired() -> void:
	for token in _tickets.keys():
		if (_tickets[token] as GDSQLMcpMigrationTicket).is_expired():
			_tickets.erase(token)


func _unknown_key(values: Dictionary, allowed: Array[String]) -> String:
	for key in values:
		if String(key) not in allowed:
			return "Unknown field '%s'." % key
	return ""


func _stale() -> GDSQLOperationResult:
	return _error(
		&"GDSQL_MCP_MIGRATION_STALE",
		"Migration history, schema, or affected rows changed after preview. Preview it again.",
	)


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


func _database_error(code: StringName, message: String) -> GDSQLDatabaseResult:
	var result := GDSQLDatabaseResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result


func _error(code: StringName, message: String) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
