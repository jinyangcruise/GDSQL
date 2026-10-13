class_name GDSQLMcpAuthoringService
extends RefCounted
## Bounded, UI-independent row and table-schema access for editor AI integrations.

signal mutation_committed(registration_name: StringName, table_name: StringName)
signal schema_committed(registration_name: StringName)
signal database_committed(registration_name: StringName)
signal migration_committed(registration_name: StringName)
signal model_committed(registration_name: StringName, table_name: StringName)

const ScalarCodec = preload(
	"res://addons/gdsql/editor/integrations/mcp/query/gdsql_mcp_scalar_codec.gd"
)
const QueryDecoder = preload(
	"res://addons/gdsql/editor/integrations/mcp/query/gdsql_mcp_query_decoder.gd"
)
const CanonicalValue = preload(
	"res://addons/gdsql/migration/gdsql_migration_canonical_value.gd"
)
const SchemaAuthoring = preload(
	"res://addons/gdsql/editor/integrations/mcp/authoring/schema/gdsql_mcp_schema_authoring_service.gd"
)
const DatabaseAuthoring = preload(
	"res://addons/gdsql/editor/integrations/mcp/authoring/database/gdsql_mcp_database_authoring_service.gd"
)
const MigrationAuthoring = preload(
	"res://addons/gdsql/editor/integrations/mcp/authoring/migration/gdsql_mcp_migration_authoring_service.gd"
)
const ModelAuthoring = preload(
	"res://addons/gdsql/editor/integrations/mcp/authoring/model/gdsql_mcp_model_authoring_service.gd"
)
const DEFAULT_LIMIT := 25
const MAX_LIMIT := 100
const MAX_MUTATION_ROWS := 100
const HANDLE_TTL_MSEC := 120_000
const CURSOR_PREFIX := "gdsql-rows-v1:"

var _workbench: GDSQLWorkbench
var _tickets: Dictionary[String, GDSQLMcpMutationTicket] = { }
var _schema_authoring: RefCounted
var _database_authoring: RefCounted
var _migration_authoring: RefCounted
var _model_authoring: RefCounted


class Target extends RefCounted:
	var registration: GDSQLDatabaseRegistration
	var database: GDSQLDatabase
	var table: GDSQLTableDefinition


func _init(
		workbench: GDSQLWorkbench,
		database_locations: Dictionary = { },
		migration_history_store: GDSQLMigrationHistoryStore = null,
		migration_schema_state_store: GDSQLMigrationSchemaStateStore = null,
) -> void:
	_workbench = workbench
	var history_store := (
		migration_history_store
		if migration_history_store != null
		else GDSQLConfigFileMigrationHistoryStore.new()
	)
	var state_store := (
		migration_schema_state_store
		if migration_schema_state_store != null
		else GDSQLConfigFileMigrationSchemaStateStore.new()
	)
	_schema_authoring = SchemaAuthoring.new(workbench)
	_schema_authoring.connect("committed", schema_committed.emit)
	_database_authoring = DatabaseAuthoring.new(
		workbench,
		database_locations,
		history_store,
	)
	_database_authoring.connect("committed", database_committed.emit)
	_migration_authoring = MigrationAuthoring.new(
		workbench,
		history_store,
		state_store,
	)
	_migration_authoring.connect("committed", migration_committed.emit)
	_model_authoring = ModelAuthoring.new(workbench)
	_model_authoring.connect("committed", model_committed.emit)


func preview_schema_mutation(request: Dictionary) -> GDSQLOperationResult:
	return _schema_authoring.call("preview", request) as GDSQLOperationResult


func commit_schema_mutation(handle: String, confirmed: bool) -> GDSQLOperationResult:
	return _schema_authoring.call("commit", handle, confirmed) as GDSQLOperationResult


func preview_database_mutation(request: Dictionary) -> GDSQLOperationResult:
	return _database_authoring.call("preview", request) as GDSQLOperationResult


func commit_database_mutation(handle: String, confirmed: bool) -> GDSQLOperationResult:
	return _database_authoring.call("commit", handle, confirmed) as GDSQLOperationResult


func preview_migration(request: Dictionary) -> GDSQLOperationResult:
	return _migration_authoring.call("preview", request) as GDSQLOperationResult


func commit_migration(handle: String, confirmed: bool) -> GDSQLOperationResult:
	return _migration_authoring.call("commit", handle, confirmed) as GDSQLOperationResult


func preview_model_mutation(request: Dictionary) -> GDSQLOperationResult:
	return _model_authoring.call("preview", request) as GDSQLOperationResult


func commit_model_mutation(handle: String, confirmed: bool) -> GDSQLOperationResult:
	return _model_authoring.call("commit", handle, confirmed) as GDSQLOperationResult


func query_rows(
		registration_name: StringName,
		table_name: StringName,
		raw_columns: Array = [],
		where: Dictionary = { },
		raw_order: Array = [],
		cursor: String = "",
		limit: int = DEFAULT_LIMIT,
) -> GDSQLOperationResult:
	if limit < 1 or limit > MAX_LIMIT:
		return _error(
			&"GDSQL_MCP_LIMIT_INVALID",
			"Limit must be between 1 and %d." % MAX_LIMIT,
		)
	var resolved := _resolve_target(registration_name, table_name)
	if not resolved.is_successful():
		return resolved
	var target := resolved.get_value() as Target
	var selected := _resolve_columns(target.table, raw_columns)
	if not selected.is_successful():
		return selected
	var columns: Array[StringName] = selected.get_value()
	var ordered := _resolve_order(target.table, raw_order)
	if not ordered.is_successful():
		return ordered
	var order: Array[Dictionary] = ordered.get_value()
	var predicate := QueryDecoder.decode(where, target.table)
	if not predicate.is_successful():
		return predicate
	var fingerprint := _query_fingerprint(
		registration_name,
		table_name,
		columns,
		where,
		order,
	)
	var decoded_cursor := _decode_cursor(cursor, fingerprint)
	if not decoded_cursor.is_successful():
		return decoded_cursor
	var offset := int(decoded_cursor.get_value())
	var builder := target.database.table(table_name).select().columns(columns)
	var expression := predicate.get_value() as GDSQLQueryExpression
	if expression != null:
		builder.where(expression)
	for clause in order:
		builder.order_by_column(
			clause["column"],
			GDSQLOrderClause.SortDirection.DESCENDING if clause["direction"] == "desc" else GDSQLOrderClause.SortDirection.ASCENDING,
		)
	var queried := target.database.execute(builder.limit(limit + 1).offset(offset).build())
	if not queried.is_successful():
		return queried
	var has_more := queried.rows.size() > limit
	var row_count := mini(limit, queried.rows.size())
	var items: Array[Dictionary] = []
	for index in row_count:
		var item: Dictionary = { }
		for column_name in columns:
			item[String(column_name)] = ScalarCodec.serialize(
				queried.rows[index].get_value(column_name),
			)
		items.append(item)
	return _success(
		{
			"kind": "rows",
			"registration": String(registration_name),
			"table": String(table_name),
			"columns": _string_names(columns),
			"items": items,
		},
		{
			"returned": items.size(),
			"truncated": has_more,
			"next_cursor": _encode_cursor(fingerprint, offset + limit) if has_more else "",
		},
	)


func preview_row_mutation(request: Dictionary) -> GDSQLOperationResult:
	_cleanup_expired_tickets()
	var operation_name := String(request.get("operation", "")).to_lower()
	var registration_name := StringName(request.get("registration", ""))
	var table_name := StringName(request.get("table", ""))
	var operation := _operation_from_name(operation_name)
	if operation < 0:
		return _error(
			&"GDSQL_MCP_MUTATION_OPERATION_INVALID",
			"Operation must be 'insert', 'update', or 'delete'.",
		)
	var resolved := _resolve_target(registration_name, table_name)
	if not resolved.is_successful():
		return resolved
	var target := resolved.get_value() as Target
	var normalized := _normalize_mutation(target.table, operation, request)
	if not normalized.is_successful():
		return normalized
	var payload := normalized.get_value() as Dictionary
	var batch_result := _build_batch(target.table, operation, payload)
	if not batch_result.is_successful():
		return batch_result
	var batch := batch_result.get_value() as GDSQLEditorRowBatch
	for query in batch.get_queries():
		var prepared := target.database.context.prepare(query)
		if not prepared.is_successful():
			return prepared
	var row_fingerprint := ""
	if operation != GDSQLMcpMutationTicket.Operation.INSERT:
		var fingerprint_result := _target_rows_fingerprint(
			target,
			_payload_identities(operation, payload),
		)
		if not fingerprint_result.is_successful():
			return fingerprint_result
		row_fingerprint = String(fingerprint_result.get_value())
	var ticket := GDSQLMcpMutationTicket.new()
	ticket.token = Crypto.new().generate_random_bytes(24).hex_encode()
	ticket.operation = operation
	ticket.registration_name = registration_name
	ticket.table_name = table_name
	ticket.payload = payload.duplicate(true)
	ticket.schema_fingerprint = _schema_fingerprint(target.database)
	ticket.row_fingerprint = row_fingerprint
	ticket.expires_at_msec = Time.get_ticks_msec() + HANDLE_TTL_MSEC
	_tickets[ticket.token] = ticket
	return _success(
		{
			"kind": "row_mutation_preview",
			"operation": operation_name,
			"registration": String(registration_name),
			"table": String(table_name),
			"row_count": batch.row_count,
			"targets": _mutation_targets(operation, payload),
			"destructive": operation == GDSQLMcpMutationTicket.Operation.DELETE,
			"confirmation_handle": ticket.token,
			"expires_in_ms": HANDLE_TTL_MSEC,
		},
	)


func commit_row_mutation(handle: String, confirmed: bool) -> GDSQLOperationResult:
	_cleanup_expired_tickets()
	if not confirmed:
		return _error(
			&"GDSQL_MCP_CONFIRMATION_REQUIRED",
			"The previewed mutation must be explicitly confirmed.",
		)
	if handle.is_empty() or not _tickets.has(handle):
		return _error(
			&"GDSQL_MCP_MUTATION_HANDLE_INVALID",
			"The mutation handle is invalid, expired, or already used.",
		)
	var ticket := _tickets[handle] as GDSQLMcpMutationTicket
	_tickets.erase(handle)
	var resolved := _resolve_target(ticket.registration_name, ticket.table_name)
	if not resolved.is_successful():
		return resolved
	var target := resolved.get_value() as Target
	if _schema_fingerprint(target.database) != ticket.schema_fingerprint:
		return _stale_error("The target schema changed after the mutation preview.")
	if ticket.operation != GDSQLMcpMutationTicket.Operation.INSERT:
		var current := _target_rows_fingerprint(
			target,
			_payload_identities(ticket.operation, ticket.payload),
		)
		if not current.is_successful():
			return _stale_error("One or more target rows changed after the mutation preview.")
		if String(current.get_value()) != ticket.row_fingerprint:
			return _stale_error("One or more target rows changed after the mutation preview.")
	var batch_result := _build_batch(target.table, ticket.operation, ticket.payload)
	if not batch_result.is_successful():
		return batch_result
	var batch := batch_result.get_value() as GDSQLEditorRowBatch
	var committed := batch.execute(target.database)
	if not committed.is_successful():
		return committed
	_workbench.refresh_inspections()
	mutation_committed.emit(ticket.registration_name, ticket.table_name)
	return _success(
		{
			"kind": "row_mutation_commit",
			"operation": _operation_name(ticket.operation),
			"registration": String(ticket.registration_name),
			"table": String(ticket.table_name),
			"affected_rows": batch.row_count,
		},
	)


func _resolve_target(
		registration_name: StringName,
		table_name: StringName,
) -> GDSQLOperationResult:
	if _workbench == null:
		return _error(&"GDSQL_MCP_WORKBENCH_REQUIRED", "The GDSQL workbench is unavailable.")
	if registration_name == &"":
		return _error(&"GDSQL_MCP_REGISTRATION_REQUIRED", "A registration is required.")
	if table_name == &"":
		return _error(&"GDSQL_MCP_TABLE_REQUIRED", "A table is required.")
	var registration := _workbench.get_registration(registration_name)
	if registration == null:
		return _error(
			&"GDSQL_MCP_REGISTRATION_NOT_FOUND",
			"Database registration '%s' was not found." % registration_name,
		)
	var opened := GDSQLRuntimeFactory.open_authoring_registration(registration)
	if not opened.is_successful():
		return opened
	var database := opened.get_database()
	var table := database.context.catalog.get_table(database.database_name, table_name)
	if table == null:
		return _error(
			&"GDSQL_MCP_TABLE_NOT_FOUND",
			"Table '%s' was not found in registration '%s'." % [
				table_name,
				registration_name,
			],
		)
	var target := Target.new()
	target.registration = registration
	target.database = database
	target.table = table
	var result := GDSQLOperationResult.new()
	result.value = target
	return result


func _resolve_columns(
		table: GDSQLTableDefinition,
		raw_columns: Array,
) -> GDSQLOperationResult:
	var columns: Array[StringName] = []
	if raw_columns.is_empty():
		for column in table.columns:
			if ScalarCodec.supports_column(column):
				columns.append(column.name)
	else:
		for raw_name in raw_columns:
			if not raw_name is String and not raw_name is StringName:
				return _error(&"GDSQL_MCP_COLUMN_INVALID", "Every column name must be a string.")
			var column_name := StringName(raw_name)
			var column := table.get_column(column_name)
			if column == null:
				return _error(
					&"GDSQL_MCP_COLUMN_NOT_FOUND",
					"Column '%s' was not found in table '%s'." % [column_name, table.name],
				)
			if not ScalarCodec.supports_column(column):
				return _error(
					&"GDSQL_MCP_COLUMN_UNSUPPORTED",
					"Column '%s' is not available through the scalar MCP row surface." % column_name,
				)
			if column_name not in columns:
				columns.append(column_name)
	if columns.is_empty():
		return _error(
			&"GDSQL_MCP_COLUMNS_EMPTY",
			"The table has no scalar columns available through this MCP surface.",
		)
	var result := GDSQLOperationResult.new()
	result.value = columns
	return result


func _resolve_order(
		table: GDSQLTableDefinition,
		raw_order: Array,
) -> GDSQLOperationResult:
	if raw_order.size() > 8:
		return _error(&"GDSQL_MCP_ORDER_LIMIT", "At most 8 order clauses are allowed.")
	var order: Array[Dictionary] = []
	for raw_clause in raw_order:
		if not raw_clause is Dictionary:
			return _error(&"GDSQL_MCP_ORDER_INVALID", "Every order clause must be an object.")
		for key in raw_clause:
			if String(key) not in ["column", "direction"]:
				return _error(
					&"GDSQL_MCP_ORDER_FIELD_UNKNOWN",
					"Unknown order field '%s'." % key,
				)
		var column_name := StringName(raw_clause.get("column", ""))
		var column := table.get_column(column_name)
		if column == null:
			return _error(
				&"GDSQL_MCP_COLUMN_NOT_FOUND",
				"Order column '%s' was not found in table '%s'." % [column_name, table.name],
			)
		if not ScalarCodec.supports_column(column):
			return _error(
				&"GDSQL_MCP_ORDER_COLUMN_UNSUPPORTED",
				"Column '%s' cannot be ordered through the scalar MCP surface." % column_name,
			)
		var direction := String(raw_clause.get("direction", "asc")).to_lower()
		if direction not in ["asc", "desc"]:
			return _error(&"GDSQL_MCP_ORDER_DIRECTION_INVALID", "Order direction must be 'asc' or 'desc'.")
		order.append({ "column": column_name, "direction": direction })
	if table.primary_key != &"" and not _order_has_column(order, table.primary_key):
		order.append({ "column": table.primary_key, "direction": "asc" })
	var result := GDSQLOperationResult.new()
	result.value = order
	return result


func _normalize_mutation(
		table: GDSQLTableDefinition,
		operation: int,
		request: Dictionary,
) -> GDSQLOperationResult:
	if operation == GDSQLMcpMutationTicket.Operation.DELETE:
		var raw_keys: Variant = request.get("primary_keys", [])
		if not raw_keys is Array:
			return _error(&"GDSQL_MCP_MUTATION_ROWS_INVALID", "primary_keys must be an array.")
		if raw_keys.is_empty() or raw_keys.size() > MAX_MUTATION_ROWS:
			return _mutation_count_error()
		var primary_column := table.get_column(table.primary_key)
		var primary_keys: Array[Variant] = []
		for raw_key in raw_keys:
			var normalized_key := ScalarCodec.normalize_for_column(raw_key, primary_column)
			if not normalized_key.is_successful():
				return normalized_key
			primary_keys.append(normalized_key.get_value())
		return _value_result({ "primary_keys": primary_keys })
	var raw_rows: Variant = request.get("rows", [])
	if not raw_rows is Array:
		return _error(&"GDSQL_MCP_MUTATION_ROWS_INVALID", "rows must be an array.")
	if raw_rows.is_empty() or raw_rows.size() > MAX_MUTATION_ROWS:
		return _mutation_count_error()
	var rows: Array[Dictionary] = []
	for raw_row in raw_rows:
		if not raw_row is Dictionary:
			return _error(&"GDSQL_MCP_MUTATION_ROW_INVALID", "Every row mutation must be an object.")
		if operation == GDSQLMcpMutationTicket.Operation.INSERT:
			var normalized_insert := _normalize_values(table, raw_row)
			if not normalized_insert.is_successful():
				return normalized_insert
			rows.append(normalized_insert.get_value())
		else:
			for key in raw_row:
				if String(key) not in ["primary_key", "values"]:
					return _error(&"GDSQL_MCP_MUTATION_FIELD_UNKNOWN", "Unknown update field '%s'." % key)
			if not raw_row.has("primary_key") or not raw_row.get("values") is Dictionary:
				return _error(
					&"GDSQL_MCP_MUTATION_ROW_INVALID",
					"Every update requires primary_key and a values object.",
				)
			var normalized_key := ScalarCodec.normalize_for_column(
				raw_row["primary_key"],
				table.get_column(table.primary_key),
			)
			if not normalized_key.is_successful():
				return normalized_key
			var normalized_values := _normalize_values(table, raw_row["values"])
			if not normalized_values.is_successful():
				return normalized_values
			rows.append(
				{
					"primary_key": normalized_key.get_value(),
					"values": normalized_values.get_value(),
				},
			)
	return _value_result({ "rows": rows })


func _normalize_values(
		table: GDSQLTableDefinition,
		raw_values: Dictionary,
) -> GDSQLOperationResult:
	var values: Dictionary = { }
	for raw_name in raw_values:
		var column_name := StringName(raw_name)
		var column := table.get_column(column_name)
		if column == null:
			return _error(
				&"GDSQL_MCP_COLUMN_NOT_FOUND",
				"Column '%s' was not found in table '%s'." % [column_name, table.name],
			)
		if not ScalarCodec.supports_column(column):
			return _error(
				&"GDSQL_MCP_MUTATION_COLUMN_UNSUPPORTED",
				"Column '%s' requires the future typed resource mutation surface." % column_name,
			)
		var normalized := ScalarCodec.normalize_for_column(raw_values[raw_name], column)
		if not normalized.is_successful():
			return normalized
		values[column_name] = normalized.get_value()
	return _value_result(values)


func _build_batch(
		table: GDSQLTableDefinition,
		operation: int,
		payload: Dictionary,
) -> GDSQLOperationResult:
	match operation:
		GDSQLMcpMutationTicket.Operation.INSERT:
			var rows: Array[Dictionary] = []
			rows.assign(payload.get("rows", []))
			return GDSQLEditorRowBatch.build_inserts(table, rows)
		GDSQLMcpMutationTicket.Operation.UPDATE:
			var rows: Array[Dictionary] = []
			rows.assign(payload.get("rows", []))
			return GDSQLEditorRowBatch.build_updates(table, rows)
		GDSQLMcpMutationTicket.Operation.DELETE:
			var keys: Array[Variant] = []
			keys.assign(payload.get("primary_keys", []))
			return GDSQLEditorRowBatch.build_deletes(table, keys)
	return _error(&"GDSQL_MCP_MUTATION_OPERATION_INVALID", "Unknown row mutation operation.")


func _target_rows_fingerprint(target: Target, identities: Array) -> GDSQLOperationResult:
	var columns: Array[StringName] = []
	for column in target.table.columns:
		if ScalarCodec.supports_column(column):
			columns.append(column.name)
	var predicate: GDSQLQueryExpression
	for identity in identities:
		var term := GDSQLExpr.column(target.table.primary_key).equals(identity)
		predicate = term if predicate == null else predicate.or_(term)
	var query := target.database.table(target.table.name).select().columns(columns).where(predicate).build()
	var selected := target.database.execute(query)
	if not selected.is_successful():
		return selected
	if selected.rows.size() != identities.size():
		return _error(
			&"GDSQL_MCP_MUTATION_TARGET_NOT_FOUND",
			"One or more mutation target rows do not exist.",
		)
	var serialized: Array = []
	for row in selected.rows:
		var values: Array = []
		for column_name in columns:
			values.append([String(column_name), ScalarCodec.serialize(row.get_value(column_name))])
		serialized.append(values)
	serialized.sort_custom(
		func(left: Variant, right: Variant) -> bool:
			return var_to_str(left) < var_to_str(right),
	)
	return _value_result(var_to_str(CanonicalValue.serialize(serialized)).sha256_text())


func _schema_fingerprint(database: GDSQLDatabase) -> String:
	return GDSQLSchemaFingerprint.compute(
		database.context.catalog.get_database(database.database_name),
	)


func _query_fingerprint(
		registration_name: StringName,
		table_name: StringName,
		columns: Array[StringName],
		where: Dictionary,
		order: Array[Dictionary],
) -> String:
	return var_to_str(
		CanonicalValue.serialize(
			[
				String(registration_name),
				String(table_name),
				_string_names(columns),
				where,
				order,
			],
		),
	).sha256_text()


func _encode_cursor(fingerprint: String, offset: int) -> String:
	return Marshalls.raw_to_base64(
		(CURSOR_PREFIX + fingerprint + ":" + str(offset)).to_utf8_buffer(),
	)


func _decode_cursor(cursor: String, fingerprint: String) -> GDSQLOperationResult:
	if cursor.is_empty():
		return _value_result(0)
	var decoded := Marshalls.base64_to_raw(cursor).get_string_from_utf8()
	var prefix := CURSOR_PREFIX + fingerprint + ":"
	if not decoded.begins_with(prefix):
		return _error(
			&"GDSQL_MCP_CURSOR_INVALID",
			"The row cursor is invalid or belongs to another query.",
		)
	var offset_text := decoded.trim_prefix(prefix)
	if not offset_text.is_valid_int() or int(offset_text) < 0:
		return _error(&"GDSQL_MCP_CURSOR_INVALID", "The row cursor is invalid.")
	return _value_result(int(offset_text))


func _payload_identities(operation: int, payload: Dictionary) -> Array:
	if operation == GDSQLMcpMutationTicket.Operation.DELETE:
		return payload.get("primary_keys", [])
	var identities: Array = []
	for row in payload.get("rows", []):
		identities.append(row.get("primary_key"))
	return identities


func _mutation_targets(operation: int, payload: Dictionary) -> Array[Dictionary]:
	var targets: Array[Dictionary] = []
	if operation == GDSQLMcpMutationTicket.Operation.DELETE:
		for identity in payload.get("primary_keys", []):
			targets.append({ "primary_key": ScalarCodec.serialize(identity) })
		return targets
	var index := 0
	for row in payload.get("rows", []):
		var values: Dictionary = (
				row if operation == GDSQLMcpMutationTicket.Operation.INSERT else row["values"]
		)
		var columns: Array[String] = []
		for column_name in values:
			columns.append(String(column_name))
		columns.sort()
		if operation == GDSQLMcpMutationTicket.Operation.INSERT:
			targets.append({ "row": index + 1, "columns": columns })
		else:
			targets.append(
				{
					"primary_key": ScalarCodec.serialize(row["primary_key"]),
					"columns": columns,
				},
			)
		index += 1
	return targets


func _operation_from_name(value: String) -> int:
	match value:
		"insert":
			return GDSQLMcpMutationTicket.Operation.INSERT
		"update":
			return GDSQLMcpMutationTicket.Operation.UPDATE
		"delete":
			return GDSQLMcpMutationTicket.Operation.DELETE
	return -1


func _operation_name(operation: int) -> String:
	match operation:
		GDSQLMcpMutationTicket.Operation.INSERT:
			return "insert"
		GDSQLMcpMutationTicket.Operation.UPDATE:
			return "update"
		GDSQLMcpMutationTicket.Operation.DELETE:
			return "delete"
	return "unknown"


func _order_has_column(order: Array[Dictionary], column_name: StringName) -> bool:
	for clause in order:
		if clause["column"] == column_name:
			return true
	return false


func _cleanup_expired_tickets() -> void:
	for token in _tickets.keys():
		if (_tickets[token] as GDSQLMcpMutationTicket).is_expired():
			_tickets.erase(token)


func _string_names(values: Array[StringName]) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		result.append(String(value))
	return result


func _mutation_count_error() -> GDSQLOperationResult:
	return _error(
		&"GDSQL_MCP_MUTATION_ROW_LIMIT",
		"A row mutation must contain between 1 and %d rows." % MAX_MUTATION_ROWS,
	)


func _stale_error(message: String) -> GDSQLOperationResult:
	return _error(&"GDSQL_MCP_MUTATION_STALE", message + " Preview it again.")


func _value_result(value: Variant) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.value = value
	return result


func _success(data: Dictionary, meta: Dictionary = { }) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	var response_meta := { "scope": "current_project", "truncated": false, "next_cursor": "" }
	response_meta.merge(meta, true)
	result.value = {
		"surface_version": GDSQLMcpInspectionService.SURFACE_VERSION,
		"ok": true,
		"data": data,
		"diagnostics": [],
		"meta": response_meta,
	}
	return result


func _error(code: StringName, message: String) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
