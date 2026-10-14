extends RefCounted
## JSON-safe scalar conversion at the MCP frontend boundary.

static func supports_column(column: GDSQLColumnDefinition) -> bool:
	return column != null and column.data_type in [
		TYPE_BOOL,
		TYPE_INT,
		TYPE_FLOAT,
		TYPE_STRING,
		TYPE_STRING_NAME,
	]


static func normalize_for_column(
		value: Variant,
		column: GDSQLColumnDefinition,
) -> GDSQLOperationResult:
	if column == null:
		return _error(
			&"GDSQL_MCP_COLUMN_REQUIRED",
			"A column definition is required to normalize an MCP value.",
		)
	var result := GDSQLOperationResult.new()
	if value == null:
		if not column.nullable:
			return _error(
				&"GDSQL_MCP_VALUE_NULL_INVALID",
				"Column '%s' does not accept null." % column.name,
			)
		result.value = null
		return result
	var normalized: Variant
	match column.data_type:
		TYPE_BOOL:
			if not value is bool:
				return _type_error(column)
			normalized = value
		TYPE_INT:
			if value is int:
				normalized = value
			elif value is float and value == floorf(value):
				normalized = int(value)
			else:
				return _type_error(column)
		TYPE_FLOAT:
			if not value is int and not value is float:
				return _type_error(column)
			normalized = float(value)
		TYPE_STRING:
			if not value is String:
				return _type_error(column)
			normalized = value
		TYPE_STRING_NAME:
			if not value is String and not value is StringName:
				return _type_error(column)
			normalized = StringName(value)
		_:
			return _error(
				&"GDSQL_MCP_VALUE_TYPE_UNSUPPORTED",
				"Column '%s' uses unsupported MCP row type %s." % [
					column.name,
					column.display_type_name(),
				],
			)
	if not column.accepts_value(normalized):
		return _type_error(column)
	result.value = normalized
	return result


static func serialize(value: Variant) -> Variant:
	if value is StringName:
		return String(value)
	if typeof(value) in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
		return value
	return null


static func _type_error(column: GDSQLColumnDefinition) -> GDSQLOperationResult:
	return _error(
		&"GDSQL_MCP_VALUE_TYPE_INVALID",
		"Column '%s' expects %s." % [column.name, column.display_type_name()],
	)


static func _error(code: StringName, message: String) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
