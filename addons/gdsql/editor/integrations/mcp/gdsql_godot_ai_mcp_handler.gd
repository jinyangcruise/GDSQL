@tool
extends RefCounted
## Lazy Godot-AI handler. Godot-AI constructs this script without arguments.

const Context := preload("res://addons/gdsql/editor/integrations/mcp/gdsql_mcp_bridge_context.gd")


func capabilities(params: Dictionary, _context: Variant) -> Dictionary:
	if not params.is_empty():
		return _invalid("gdsql_capabilities does not accept parameters.")
	return _invoke(Callable(_service(), "get_capabilities"))


func inspect_setup(params: Dictionary, _context: Variant) -> Dictionary:
	var invalid := _unknown_parameter(params, ["profile"])
	if not invalid.is_empty():
		return _invalid(invalid)
	var profile: Variant = params.get("profile", "selected")
	if not profile is String:
		return _invalid("profile must be a string.")
	return _invoke(Callable(_service(), "inspect_setup").bind(StringName(profile)))


func inspect_schema(params: Dictionary, _context: Variant) -> Dictionary:
	var invalid := _unknown_parameter(
		params,
		["registration", "table", "cursor", "limit"],
	)
	if not invalid.is_empty():
		return _invalid(invalid)
	for key in ["registration", "table", "cursor"]:
		if params.has(key) and not params[key] is String:
			return _invalid("%s must be a string." % key)
	if params.has("limit") and not params["limit"] is int and not params["limit"] is float:
		return _invalid("limit must be an integer.")
	var raw_limit: Variant = params.get("limit", GDSQLMcpInspectionService.DEFAULT_LIMIT)
	if raw_limit is float and raw_limit != floorf(raw_limit):
		return _invalid("limit must be an integer.")
	return _invoke(
		Callable(_service(), "inspect_schema").bind(
			StringName(params.get("registration", "")),
			StringName(params.get("table", "")),
			String(params.get("cursor", "")),
			int(raw_limit),
		),
	)


func inspect_models(params: Dictionary, _context: Variant) -> Dictionary:
	var invalid := _unknown_parameter(
		params,
		["registration", "table", "cursor", "limit"],
	)
	if not invalid.is_empty():
		return _invalid(invalid)
	for key in ["registration", "table", "cursor"]:
		if params.has(key) and not params[key] is String:
			return _invalid("%s must be a string." % key)
	if params.has("limit") and not params["limit"] is int and not params["limit"] is float:
		return _invalid("limit must be an integer.")
	var raw_limit: Variant = params.get("limit", GDSQLMcpInspectionService.DEFAULT_LIMIT)
	if raw_limit is float and raw_limit != floorf(raw_limit):
		return _invalid("limit must be an integer.")
	return _invoke(
		Callable(_service(), "inspect_models").bind(
			StringName(params.get("registration", "")),
			StringName(params.get("table", "")),
			String(params.get("cursor", "")),
			int(raw_limit),
		),
	)


func query_rows(params: Dictionary, _context: Variant) -> Dictionary:
	var invalid := _unknown_parameter(
		params,
		["registration", "table", "columns", "where", "order_by", "cursor", "limit"],
	)
	if not invalid.is_empty():
		return _invalid(invalid)
	for required in ["registration", "table"]:
		if not params.has(required) or not params[required] is String \
				or String(params[required]).is_empty():
			return _invalid("%s must be a non-empty string." % required)
	if params.has("columns") and not params["columns"] is Array:
		return _invalid("columns must be an array.")
	if params.has("where") and not params["where"] is Dictionary:
		return _invalid("where must be an object.")
	if params.has("order_by") and not params["order_by"] is Array:
		return _invalid("order_by must be an array.")
	if params.has("cursor") and not params["cursor"] is String:
		return _invalid("cursor must be a string.")
	var limit: Variant = _integer_parameter(
		params,
		"limit",
		GDSQLMcpAuthoringService.DEFAULT_LIMIT,
	)
	if limit == null:
		return _invalid("limit must be an integer.")
	return _invoke(
		Callable(_authoring_service(), "query_rows").bind(
			StringName(params["registration"]),
			StringName(params["table"]),
			params.get("columns", []),
			params.get("where", { }),
			params.get("order_by", []),
			String(params.get("cursor", "")),
			limit,
		),
	)


func preview_row_mutation(params: Dictionary, _context: Variant) -> Dictionary:
	var invalid := _unknown_parameter(
		params,
		["operation", "registration", "table", "rows", "primary_keys"],
	)
	if not invalid.is_empty():
		return _invalid(invalid)
	for required in ["operation", "registration", "table"]:
		if not params.has(required) or not params[required] is String \
				or String(params[required]).is_empty():
			return _invalid("%s must be a non-empty string." % required)
	if params.has("rows") and not params["rows"] is Array:
		return _invalid("rows must be an array.")
	if params.has("primary_keys") and not params["primary_keys"] is Array:
		return _invalid("primary_keys must be an array.")
	return _invoke(
		Callable(_authoring_service(), "preview_row_mutation").bind(params),
	)


func commit_row_mutation(params: Dictionary, _context: Variant) -> Dictionary:
	var invalid := _unknown_parameter(params, ["handle", "confirm"])
	if not invalid.is_empty():
		return _invalid(invalid)
	if not params.get("handle") is String or String(params.get("handle", "")).is_empty():
		return _invalid("handle must be a non-empty string.")
	if not params.get("confirm") is bool:
		return _invalid("confirm must be a boolean.")
	return _invoke(
		Callable(_authoring_service(), "commit_row_mutation").bind(
			String(params["handle"]),
			bool(params["confirm"]),
		),
	)


func preview_schema_mutation(params: Dictionary, _context: Variant) -> Dictionary:
	var invalid := _unknown_parameter(
		params,
		["operation", "registration", "table", "new_name", "alterations"],
	)
	if not invalid.is_empty():
		return _invalid(invalid)
	for required in ["operation", "registration"]:
		if not params.get(required) is String or String(params.get(required, "")).is_empty():
			return _invalid("%s must be a non-empty string." % required)
	if not params.has("table") or not params["table"] is String \
			and not params["table"] is Dictionary:
		return _invalid("table must be a string or object.")
	if params.has("new_name") and not params["new_name"] is String:
		return _invalid("new_name must be a string.")
	if params.has("alterations") and not params["alterations"] is Array:
		return _invalid("alterations must be an array.")
	return _invoke(
		Callable(_authoring_service(), "preview_schema_mutation").bind(params),
	)


func commit_schema_mutation(params: Dictionary, _context: Variant) -> Dictionary:
	var invalid := _unknown_parameter(params, ["handle", "confirm"])
	if not invalid.is_empty():
		return _invalid(invalid)
	if not params.get("handle") is String or String(params.get("handle", "")).is_empty():
		return _invalid("handle must be a non-empty string.")
	if not params.get("confirm") is bool:
		return _invalid("confirm must be a boolean.")
	return _invoke(
		Callable(_authoring_service(), "commit_schema_mutation").bind(
			String(params["handle"]),
			bool(params["confirm"]),
		),
	)


func preview_database_mutation(params: Dictionary, _context: Variant) -> Dictionary:
	var invalid := _unknown_parameter(
		params,
		[
			"operation", "registration", "database", "location",
			"root_registration", "storage_backend", "new_name",
		],
	)
	if not invalid.is_empty():
		return _invalid(invalid)
	for required in ["operation", "registration"]:
		if not params.get(required) is String \
				or String(params.get(required, "")).is_empty():
			return _invalid("%s must be a non-empty string." % required)
	for key in [
		"database", "location", "root_registration", "storage_backend", "new_name",
	]:
		if params.has(key) and not params[key] is String:
			return _invalid("%s must be a string." % key)
	return _invoke(
		Callable(_authoring_service(), "preview_database_mutation").bind(params),
	)


func commit_database_mutation(params: Dictionary, _context: Variant) -> Dictionary:
	var invalid := _unknown_parameter(params, ["handle", "confirm"])
	if not invalid.is_empty():
		return _invalid(invalid)
	if not params.get("handle") is String or String(params.get("handle", "")).is_empty():
		return _invalid("handle must be a non-empty string.")
	if not params.get("confirm") is bool:
		return _invalid("confirm must be a boolean.")
	return _invoke(
		Callable(_authoring_service(), "commit_database_mutation").bind(
			String(params["handle"]),
			bool(params["confirm"]),
		),
	)


func preview_migration(params: Dictionary, _context: Variant) -> Dictionary:
	var invalid := _unknown_parameter(
		params,
		["registration", "migration_id", "description", "steps"],
	)
	if not invalid.is_empty():
		return _invalid(invalid)
	if not params.get("registration") is String \
			or String(params.get("registration", "")).is_empty():
		return _invalid("registration must be a non-empty string.")
	for key in ["migration_id", "description"]:
		if params.has(key) and not params[key] is String:
			return _invalid("%s must be a string." % key)
	if params.has("steps") and not params["steps"] is Array:
		return _invalid("steps must be an array.")
	return _invoke(Callable(_authoring_service(), "preview_migration").bind(params))


func commit_migration(params: Dictionary, _context: Variant) -> Dictionary:
	var invalid := _unknown_parameter(params, ["handle", "confirm"])
	if not invalid.is_empty():
		return _invalid(invalid)
	if not params.get("handle") is String or String(params.get("handle", "")).is_empty():
		return _invalid("handle must be a non-empty string.")
	if not params.get("confirm") is bool:
		return _invalid("confirm must be a boolean.")
	return _invoke(
		Callable(_authoring_service(), "commit_migration").bind(
			String(params["handle"]),
			bool(params["confirm"]),
		),
	)


func preview_model_mutation(params: Dictionary, _context: Variant) -> Dictionary:
	var allowed: Array[String] = [
		"operation", "registration", "table", "class_name", "role", "model_root",
		"source_registration", "source_table", "source_column",
		"target_registration", "target_table", "target_column",
		"target_model_class", "relationship_name",
	]
	var invalid := _unknown_parameter(params, allowed)
	if not invalid.is_empty():
		return _invalid(invalid)
	if not params.get("operation") is String \
			or String(params.get("operation", "")).is_empty():
		return _invalid("operation must be a non-empty string.")
	for key in allowed:
		if key != "operation" and params.has(key) and not params[key] is String:
			return _invalid("%s must be a string." % key)
	return _invoke(
		Callable(_authoring_service(), "preview_model_mutation").bind(params),
	)


func commit_model_mutation(params: Dictionary, _context: Variant) -> Dictionary:
	var invalid := _unknown_parameter(params, ["handle", "confirm"])
	if not invalid.is_empty():
		return _invalid(invalid)
	if not params.get("handle") is String or String(params.get("handle", "")).is_empty():
		return _invalid("handle must be a non-empty string.")
	if not params.get("confirm") is bool:
		return _invalid("confirm must be a boolean.")
	return _invoke(
		Callable(_authoring_service(), "commit_model_mutation").bind(
			String(params["handle"]),
			bool(params["confirm"]),
		),
	)


func _invoke(operation: Callable) -> Dictionary:
	if not operation.is_valid():
		return _error("INTERNAL_ERROR", "The requested GDSQL MCP service is unavailable.")
	var result := operation.call() as GDSQLOperationResult
	if result == null:
		return _error("INTERNAL_ERROR", "The GDSQL MCP operation returned no result.")
	if result.is_successful():
		return { "data": result.get_value() }
	var diagnostic := result.diagnostics.entries[0]
	var response := _error(String(diagnostic.code), diagnostic.message)
	response["error"]["data"] = { "diagnostics": _diagnostics(result.diagnostics) }
	return response


func _service() -> GDSQLMcpInspectionService:
	return Context.get_inspection_service()


func _authoring_service() -> GDSQLMcpAuthoringService:
	return Context.get_authoring_service()


func _integer_parameter(params: Dictionary, key: String, fallback: int) -> Variant:
	if not params.has(key):
		return fallback
	var value: Variant = params[key]
	if not value is int and not value is float:
		return null
	if value is float and value != floorf(value):
		return null
	return int(value)


func _unknown_parameter(params: Dictionary, allowed: Array[String]) -> String:
	for key in params:
		if String(key) not in allowed:
			return "Unknown parameter '%s'." % key
	return ""


func _invalid(message: String) -> Dictionary:
	return _error("INVALID_PARAMS", message)


func _error(code: String, message: String) -> Dictionary:
	return { "status": "error", "error": { "code": code, "message": message } }


func _diagnostics(diagnostics: GDSQLDiagnostics) -> Array[Dictionary]:
	var values: Array[Dictionary] = []
	for diagnostic in diagnostics.entries:
		values.append({ "code": String(diagnostic.code), "message": diagnostic.message })
	return values
