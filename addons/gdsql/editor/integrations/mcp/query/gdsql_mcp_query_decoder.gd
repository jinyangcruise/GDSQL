extends RefCounted
## Translates bounded structured MCP predicates into canonical expressions.

const ScalarCodec = preload(
	"res://addons/gdsql/editor/integrations/mcp/query/gdsql_mcp_scalar_codec.gd"
)
const MAX_DEPTH := 6
const MAX_CONDITIONS := 32


static func decode(
		encoded: Dictionary,
		table: GDSQLTableDefinition,
) -> GDSQLOperationResult:
	if encoded.is_empty():
		var empty := GDSQLOperationResult.new()
		empty.value = null
		return empty
	var budget := [MAX_CONDITIONS]
	return _decode_condition(encoded, table, 0, budget)


static func _decode_condition(
		encoded: Dictionary,
		table: GDSQLTableDefinition,
		depth: int,
		budget: Array,
) -> GDSQLOperationResult:
	if depth > MAX_DEPTH:
		return _error(
			&"GDSQL_MCP_WHERE_DEPTH_EXCEEDED",
			"WHERE nesting exceeds the maximum depth of %d." % MAX_DEPTH,
		)
	budget[0] = int(budget[0]) - 1
	if int(budget[0]) < 0:
		return _error(
			&"GDSQL_MCP_WHERE_CONDITION_LIMIT",
			"WHERE contains more than %d conditions." % MAX_CONDITIONS,
		)
	var operator := String(encoded.get("operator", "")).to_lower()
	if operator in ["and", "or"]:
		return _decode_group(encoded, table, operator, depth, budget)
	if operator == "not":
		return _decode_not(encoded, table, depth, budget)
	return _decode_leaf(encoded, table, operator)


static func _decode_group(
		encoded: Dictionary,
		table: GDSQLTableDefinition,
		operator: String,
		depth: int,
		budget: Array,
) -> GDSQLOperationResult:
	var unknown := _unknown_key(encoded, ["operator", "conditions"])
	if not unknown.is_empty():
		return _error(&"GDSQL_MCP_WHERE_FIELD_UNKNOWN", unknown)
	var raw_conditions: Variant = encoded.get("conditions")
	if not raw_conditions is Array or raw_conditions.is_empty():
		return _error(
			&"GDSQL_MCP_WHERE_GROUP_EMPTY",
			"Logical '%s' requires a non-empty conditions array." % operator,
		)
	var combined: GDSQLQueryExpression
	for raw_condition in raw_conditions:
		if not raw_condition is Dictionary:
			return _error(
				&"GDSQL_MCP_WHERE_CONDITION_INVALID",
				"Every logical condition must be an object.",
			)
		var decoded := _decode_condition(raw_condition, table, depth + 1, budget)
		if not decoded.is_successful():
			return decoded
		var expression := decoded.get_value() as GDSQLQueryExpression
		combined = expression if combined == null else (
				combined.and_(expression) if operator == "and" else combined.or_(expression)
		)
	var result := GDSQLOperationResult.new()
	result.value = combined
	return result


static func _decode_not(
		encoded: Dictionary,
		table: GDSQLTableDefinition,
		depth: int,
		budget: Array,
) -> GDSQLOperationResult:
	var unknown := _unknown_key(encoded, ["operator", "condition"])
	if not unknown.is_empty():
		return _error(&"GDSQL_MCP_WHERE_FIELD_UNKNOWN", unknown)
	var raw_condition: Variant = encoded.get("condition")
	if not raw_condition is Dictionary:
		return _error(
			&"GDSQL_MCP_WHERE_CONDITION_INVALID",
			"Logical 'not' requires one condition object.",
		)
	var decoded := _decode_condition(raw_condition, table, depth + 1, budget)
	if not decoded.is_successful():
		return decoded
	var result := GDSQLOperationResult.new()
	result.value = (decoded.get_value() as GDSQLQueryExpression).not_()
	return result


static func _decode_leaf(
		encoded: Dictionary,
		table: GDSQLTableDefinition,
		operator: String,
) -> GDSQLOperationResult:
	var unknown := _unknown_key(encoded, ["column", "operator", "value"])
	if not unknown.is_empty():
		return _error(&"GDSQL_MCP_WHERE_FIELD_UNKNOWN", unknown)
	if table == null:
		return _error(&"GDSQL_MCP_TABLE_REQUIRED", "A table is required for WHERE decoding.")
	var column_name := StringName(encoded.get("column", ""))
	var column := table.get_column(column_name)
	if column == null:
		return _error(
			&"GDSQL_MCP_COLUMN_NOT_FOUND",
			"Column '%s' was not found in table '%s'." % [column_name, table.name],
		)
	if not ScalarCodec.supports_column(column):
		return _error(
			&"GDSQL_MCP_WHERE_COLUMN_UNSUPPORTED",
			"Column '%s' cannot be filtered through the scalar MCP surface." % column_name,
		)
	var left := GDSQLExpr.column(column_name)
	if operator == "is_null":
		return _expression_result(left.is_null())
	if operator == "is_not_null":
		return _expression_result(left.is_not_null())
	if operator not in ["eq", "neq", "gt", "gte", "lt", "lte"]:
		return _error(
			&"GDSQL_MCP_WHERE_OPERATOR_INVALID",
			"Unsupported WHERE operator '%s'." % operator,
		)
	if not encoded.has("value") or encoded["value"] == null:
		return _error(
			&"GDSQL_MCP_WHERE_VALUE_REQUIRED",
			"Operator '%s' requires a non-null value; use is_null for null checks." % operator,
		)
	var normalized := ScalarCodec.normalize_for_column(encoded["value"], column)
	if not normalized.is_successful():
		return normalized
	var value: Variant = normalized.get_value()
	match operator:
		"eq":
			return _expression_result(left.equals(value))
		"neq":
			return _expression_result(left.not_equals(value))
		"gt":
			return _expression_result(left.greater_than(value))
		"gte":
			return _expression_result(left.greater_than_or_equal(value))
		"lt":
			return _expression_result(left.less_than(value))
		"lte":
			return _expression_result(left.less_than_or_equal(value))
	return _error(&"GDSQL_MCP_WHERE_OPERATOR_INVALID", "Unsupported WHERE operator.")


static func _expression_result(expression: GDSQLQueryExpression) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.value = expression
	return result


static func _unknown_key(encoded: Dictionary, allowed: Array[String]) -> String:
	for key in encoded:
		if String(key) not in allowed:
			return "Unknown WHERE field '%s'." % key
	return ""


static func _error(code: StringName, message: String) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
