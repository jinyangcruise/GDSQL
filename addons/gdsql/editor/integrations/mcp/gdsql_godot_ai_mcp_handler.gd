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


func _invoke(operation: Callable) -> Dictionary:
	if not operation.is_valid():
		return _error("INTERNAL_ERROR", "The GDSQL MCP inspection service is unavailable.")
	var result := operation.call() as GDSQLOperationResult
	if result == null:
		return _error("INTERNAL_ERROR", "The GDSQL MCP inspection returned no result.")
	if result.is_successful():
		return { "data": result.get_value() }
	var diagnostic := result.diagnostics.entries[0]
	var response := _error(String(diagnostic.code), diagnostic.message)
	response["error"]["data"] = { "diagnostics": _diagnostics(result.diagnostics) }
	return response


func _service() -> GDSQLMcpInspectionService:
	return Context.get_service()


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
