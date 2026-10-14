extends RefCounted
## Translates JSON-compatible MCP schema intents into typed catalog values.

const MAX_ALTERATIONS := 32
const TYPE_IDS := {
	"bool": TYPE_BOOL,
	"int": TYPE_INT,
	"float": TYPE_FLOAT,
	"string": TYPE_STRING,
	"string_name": TYPE_STRING_NAME,
	"vector2": TYPE_VECTOR2,
	"vector2i": TYPE_VECTOR2I,
	"rect2": TYPE_RECT2,
	"rect2i": TYPE_RECT2I,
	"vector3": TYPE_VECTOR3,
	"vector3i": TYPE_VECTOR3I,
	"transform2d": TYPE_TRANSFORM2D,
	"vector4": TYPE_VECTOR4,
	"vector4i": TYPE_VECTOR4I,
	"plane": TYPE_PLANE,
	"quaternion": TYPE_QUATERNION,
	"aabb": TYPE_AABB,
	"basis": TYPE_BASIS,
	"transform3d": TYPE_TRANSFORM3D,
	"projection": TYPE_PROJECTION,
	"color": TYPE_COLOR,
	"node_path": TYPE_NODE_PATH,
	"dictionary": TYPE_DICTIONARY,
	"array": TYPE_ARRAY,
	"packed_byte_array": TYPE_PACKED_BYTE_ARRAY,
	"packed_int32_array": TYPE_PACKED_INT32_ARRAY,
	"packed_int64_array": TYPE_PACKED_INT64_ARRAY,
	"packed_float32_array": TYPE_PACKED_FLOAT32_ARRAY,
	"packed_float64_array": TYPE_PACKED_FLOAT64_ARRAY,
	"packed_string_array": TYPE_PACKED_STRING_ARRAY,
	"packed_vector2_array": TYPE_PACKED_VECTOR2_ARRAY,
	"packed_vector3_array": TYPE_PACKED_VECTOR3_ARRAY,
	"packed_color_array": TYPE_PACKED_COLOR_ARRAY,
	"packed_vector4_array": TYPE_PACKED_VECTOR4_ARRAY,
	"resource": TYPE_OBJECT,
}


static func decode(
		request: Dictionary,
		current_table: GDSQLTableDefinition = null,
) -> GDSQLOperationResult:
	var operation := String(request.get("operation", "")).to_lower()
	match operation:
		"create_table":
			return _decode_create(request)
		"rename_table":
			return _decode_rename(request)
		"drop_table":
			return _decode_drop(request)
		"alter_table":
			return _decode_alter(request, current_table)
	return _error(
		&"GDSQL_MCP_SCHEMA_OPERATION_INVALID",
		"Operation must be create_table, rename_table, drop_table, or alter_table.",
	)


static func type_ids() -> Array[String]:
	var values: Array[String] = []
	values.assign(TYPE_IDS.keys())
	values.sort()
	return values


static func _decode_create(request: Dictionary) -> GDSQLOperationResult:
	var unknown := _unknown_key(request, ["operation", "registration", "table"])
	if not unknown.is_empty():
		return _unknown_error(unknown)
	if not request.get("table") is Dictionary:
		return _error(&"GDSQL_MCP_SCHEMA_TABLE_INVALID", "table must be an object.")
	var decoded := _table_definition(request["table"])
	if not decoded.is_successful():
		return decoded
	return _value_result(
		{
			"operation": "create_table",
			"table_definition": decoded.get_value(),
		},
	)


static func _decode_rename(request: Dictionary) -> GDSQLOperationResult:
	var unknown := _unknown_key(
		request,
		["operation", "registration", "table", "new_name"],
	)
	if not unknown.is_empty():
		return _unknown_error(unknown)
	var table_name := _required_name(request, "table")
	if not table_name.is_successful():
		return table_name
	var new_name := _required_name(request, "new_name")
	if not new_name.is_successful():
		return new_name
	return _value_result(
		{
			"operation": "rename_table",
			"table_name": table_name.get_value(),
			"new_name": new_name.get_value(),
		},
	)


static func _decode_drop(request: Dictionary) -> GDSQLOperationResult:
	var unknown := _unknown_key(request, ["operation", "registration", "table"])
	if not unknown.is_empty():
		return _unknown_error(unknown)
	var table_name := _required_name(request, "table")
	if not table_name.is_successful():
		return table_name
	return _value_result(
		{
			"operation": "drop_table",
			"table_name": table_name.get_value(),
		},
	)


static func _decode_alter(
		request: Dictionary,
		current_table: GDSQLTableDefinition,
) -> GDSQLOperationResult:
	var unknown := _unknown_key(
		request,
		["operation", "registration", "table", "alterations"],
	)
	if not unknown.is_empty():
		return _unknown_error(unknown)
	var table_name := _required_name(request, "table")
	if not table_name.is_successful():
		return table_name
	if not request.get("alterations") is Array:
		return _error(
			&"GDSQL_MCP_SCHEMA_ALTERATIONS_INVALID",
			"alterations must be an array.",
		)
	var raw_alterations := request["alterations"] as Array
	if raw_alterations.is_empty() or raw_alterations.size() > MAX_ALTERATIONS:
		return _error(
			&"GDSQL_MCP_SCHEMA_ALTERATION_LIMIT",
			"A schema preview requires between 1 and %d alterations." % MAX_ALTERATIONS,
		)
	var alterations: Array[GDSQLTableAlteration] = []
	for raw_alteration in raw_alterations:
		if not raw_alteration is Dictionary:
			return _error(
				&"GDSQL_MCP_SCHEMA_ALTERATION_INVALID",
				"Every alteration must be an object.",
			)
		var decoded := _alteration(raw_alteration, current_table)
		if not decoded.is_successful():
			return decoded
		alterations.append(decoded.get_value())
	return _value_result(
		{
			"operation": "alter_table",
			"table_name": table_name.get_value(),
			"alterations": alterations,
		},
	)


static func _table_definition(raw: Dictionary) -> GDSQLOperationResult:
	var unknown := _unknown_key(
		raw,
		["name", "primary_key", "columns", "indexes", "foreign_keys"],
	)
	if not unknown.is_empty():
		return _unknown_error(unknown)
	var name := _required_name(raw, "name")
	if not name.is_successful():
		return name
	var primary_key := _required_name(raw, "primary_key")
	if not primary_key.is_successful():
		return primary_key
	if not raw.get("columns") is Array or (raw["columns"] as Array).is_empty():
		return _error(
			&"GDSQL_MCP_SCHEMA_COLUMNS_INVALID",
			"columns must be a non-empty array.",
		)
	var table := GDSQLTableDefinition.new(name.get_value(), primary_key.get_value())
	for raw_column in raw["columns"]:
		if not raw_column is Dictionary:
			return _error(
				&"GDSQL_MCP_SCHEMA_COLUMN_INVALID",
				"Every column must be an object.",
			)
		var column := _column(raw_column)
		if not column.is_successful():
			return column
		table.add_column(column.get_value())
	var indexes := _definitions(raw.get("indexes", []), Callable(_index), "index")
	if not indexes.is_successful():
		return indexes
	for index in indexes.get_value():
		table.add_index(index)
	var foreign_keys := _definitions(
		raw.get("foreign_keys", []),
		Callable(_foreign_key),
		"foreign key",
	)
	if not foreign_keys.is_successful():
		return foreign_keys
	for foreign_key in foreign_keys.get_value():
		table.add_foreign_key(foreign_key)
	return _value_result(table)


static func _column(raw: Dictionary) -> GDSQLOperationResult:
	var unknown := _unknown_key(
		raw,
		[
			"name",
			"type",
			"nullable",
			"unique",
			"auto_increment",
			"default",
			"generation",
			"resource",
		],
	)
	if not unknown.is_empty():
		return _unknown_error(unknown)
	var name := _required_name(raw, "name")
	if not name.is_successful():
		return name
	if not raw.get("type") is String:
		return _error(&"GDSQL_MCP_SCHEMA_TYPE_INVALID", "Column type must be a string.")
	var type_id := String(raw["type"]).to_lower()
	if not TYPE_IDS.has(type_id):
		return _error(
			&"GDSQL_MCP_SCHEMA_TYPE_INVALID",
			"Unsupported column type '%s'." % type_id,
		)
	for boolean_key in ["nullable", "unique", "auto_increment"]:
		if raw.has(boolean_key) and not raw[boolean_key] is bool:
			return _error(
				&"GDSQL_MCP_SCHEMA_COLUMN_INVALID",
				"%s must be a boolean." % boolean_key,
			)
	var resource_constraint: GDSQLResourceTypeConstraint
	var ownership := GDSQLResourceOwnership.Mode.OWNED
	if type_id == "resource":
		var resource := _resource_constraint(raw.get("resource"))
		if not resource.is_successful():
			return resource
		var resource_value := resource.get_value() as Dictionary
		resource_constraint = resource_value["constraint"]
		ownership = resource_value["ownership"]
	elif raw.has("resource"):
		return _error(
			&"GDSQL_MCP_SCHEMA_RESOURCE_INVALID",
			"resource is only valid for a resource column.",
		)
	var default_value: Variant = null
	if raw.has("default"):
		if raw["default"] == null:
			return _error(
				&"GDSQL_MCP_SCHEMA_DEFAULT_INVALID",
				"Use nullable instead of a null default.",
			)
		default_value = _normalize_default(raw["default"], TYPE_IDS[type_id])
		if default_value == null:
			return _error(
				&"GDSQL_MCP_SCHEMA_DEFAULT_INVALID",
				"The default is not JSON-compatible with column type '%s'." % type_id,
			)
	var column := GDSQLColumnDefinition.new(
		name.get_value(),
		TYPE_IDS[type_id],
		bool(raw.get("nullable", true)),
		bool(raw.get("unique", false)),
		bool(raw.get("auto_increment", false)),
		default_value,
		resource_constraint,
	)
	column.resource_ownership = ownership
	var generation := _generation(raw.get("generation", "none"))
	if generation < 0:
		return _error(
			&"GDSQL_MCP_SCHEMA_GENERATION_INVALID",
			"generation must be none, created_at, or updated_at.",
		)
	column.generation = generation as GDSQLColumnDefinition.Generation
	return _value_result(column)


static func _index(raw: Dictionary) -> GDSQLOperationResult:
	var unknown := _unknown_key(raw, ["name", "columns", "unique"])
	if not unknown.is_empty():
		return _unknown_error(unknown)
	var name := _required_name(raw, "name")
	if not name.is_successful():
		return name
	var columns := _name_array(raw.get("columns"), "columns")
	if not columns.is_successful():
		return columns
	if raw.has("unique") and not raw["unique"] is bool:
		return _error(&"GDSQL_MCP_SCHEMA_INDEX_INVALID", "unique must be a boolean.")
	return _value_result(
		GDSQLIndexDefinition.new(
			name.get_value(),
			columns.get_value(),
			bool(raw.get("unique", false)),
		),
	)


static func _foreign_key(raw: Dictionary) -> GDSQLOperationResult:
	var unknown := _unknown_key(
		raw,
		["name", "column", "referenced_table", "referenced_column"],
	)
	if not unknown.is_empty():
		return _unknown_error(unknown)
	var names: Array[StringName] = []
	for key in ["name", "column", "referenced_table", "referenced_column"]:
		var decoded := _required_name(raw, key)
		if not decoded.is_successful():
			return decoded
		names.append(decoded.get_value())
	return _value_result(
		GDSQLForeignKeyDefinition.new(names[0], names[1], names[2], names[3]),
	)


static func _alteration(
		raw: Dictionary,
		current_table: GDSQLTableDefinition,
) -> GDSQLOperationResult:
	if not raw.get("kind") is String:
		return _error(
			&"GDSQL_MCP_SCHEMA_ALTERATION_INVALID",
			"Alteration kind must be a string.",
		)
	var kind := String(raw["kind"]).to_lower()
	match kind:
		"add_column":
			return _object_alteration(raw, "column", Callable(_column), Callable(GDSQLTableAlteration.add_column))
		"rename_column":
			return _rename_column(raw)
		"drop_column":
			return _named_alteration(raw, "column", Callable(GDSQLTableAlteration.drop_column))
		"add_index":
			return _object_alteration(raw, "index", Callable(_index), Callable(GDSQLTableAlteration.add_index))
		"drop_index":
			return _named_alteration(raw, "name", Callable(GDSQLTableAlteration.drop_index))
		"add_foreign_key":
			return _object_alteration(raw, "foreign_key", Callable(_foreign_key), Callable(GDSQLTableAlteration.add_foreign_key))
		"drop_foreign_key":
			return _named_alteration(raw, "name", Callable(GDSQLTableAlteration.drop_foreign_key))
		"set_column_default":
			return _set_default(raw, current_table)
		"clear_column_default":
			return _named_alteration(raw, "column", Callable(GDSQLTableAlteration.clear_column_default))
		"set_column_nullable":
			return _boolean_alteration(raw, Callable(GDSQLTableAlteration.set_column_nullable))
		"set_column_unique":
			return _boolean_alteration(raw, Callable(GDSQLTableAlteration.set_column_unique))
		"set_column_auto_increment":
			return _boolean_alteration(raw, Callable(GDSQLTableAlteration.set_column_auto_increment))
		"set_column_generation":
			return _set_generation(raw)
		"set_resource_ownership":
			return _set_resource_ownership(raw)
		"reorder_columns":
			return _reorder_columns(raw)
	return _error(
		&"GDSQL_MCP_SCHEMA_ALTERATION_INVALID",
		"Unsupported alteration kind '%s'." % kind,
	)


static func _object_alteration(
		raw: Dictionary,
		key: String,
		decoder: Callable,
		factory: Callable,
) -> GDSQLOperationResult:
	var unknown := _unknown_key(raw, ["kind", key])
	if not unknown.is_empty():
		return _unknown_error(unknown)
	if not raw.get(key) is Dictionary:
		return _error(
			&"GDSQL_MCP_SCHEMA_ALTERATION_INVALID",
			"%s must be an object." % key,
		)
	var decoded := decoder.call(raw[key]) as GDSQLOperationResult
	if not decoded.is_successful():
		return decoded
	return _value_result(factory.call(decoded.get_value()))


static func _named_alteration(
		raw: Dictionary,
		key: String,
		factory: Callable,
) -> GDSQLOperationResult:
	var unknown := _unknown_key(raw, ["kind", key])
	if not unknown.is_empty():
		return _unknown_error(unknown)
	var name := _required_name(raw, key)
	if not name.is_successful():
		return name
	return _value_result(factory.call(name.get_value()))


static func _rename_column(raw: Dictionary) -> GDSQLOperationResult:
	var unknown := _unknown_key(raw, ["kind", "column", "new_name"])
	if not unknown.is_empty():
		return _unknown_error(unknown)
	var column := _required_name(raw, "column")
	if not column.is_successful():
		return column
	var new_name := _required_name(raw, "new_name")
	if not new_name.is_successful():
		return new_name
	return _value_result(
		GDSQLTableAlteration.rename_column(column.get_value(), new_name.get_value()),
	)


static func _boolean_alteration(raw: Dictionary, factory: Callable) -> GDSQLOperationResult:
	var unknown := _unknown_key(raw, ["kind", "column", "enabled"])
	if not unknown.is_empty():
		return _unknown_error(unknown)
	var column := _required_name(raw, "column")
	if not column.is_successful():
		return column
	if not raw.get("enabled") is bool:
		return _error(
			&"GDSQL_MCP_SCHEMA_ALTERATION_INVALID",
			"enabled must be a boolean.",
		)
	return _value_result(factory.call(column.get_value(), raw["enabled"]))


static func _set_default(
		raw: Dictionary,
		current_table: GDSQLTableDefinition,
) -> GDSQLOperationResult:
	var unknown := _unknown_key(raw, ["kind", "column", "value"])
	if not unknown.is_empty():
		return _unknown_error(unknown)
	var column_name := _required_name(raw, "column")
	if not column_name.is_successful():
		return column_name
	if not raw.has("value") or raw["value"] == null:
		return _error(
			&"GDSQL_MCP_SCHEMA_DEFAULT_INVALID",
			"value must be a non-null JSON value.",
		)
	var value: Variant = raw["value"]
	if current_table != null:
		var column := current_table.get_column(column_name.get_value())
		if column != null:
			value = _normalize_default(value, column.data_type)
			if value == null:
				return _error(
					&"GDSQL_MCP_SCHEMA_DEFAULT_INVALID",
					"value is incompatible with column '%s'." % column.name,
				)
	return _value_result(
		GDSQLTableAlteration.set_column_default(column_name.get_value(), value),
	)


static func _set_generation(raw: Dictionary) -> GDSQLOperationResult:
	var unknown := _unknown_key(raw, ["kind", "column", "generation"])
	if not unknown.is_empty():
		return _unknown_error(unknown)
	var column := _required_name(raw, "column")
	if not column.is_successful():
		return column
	var generation := _generation(raw.get("generation"))
	if generation < 0:
		return _error(
			&"GDSQL_MCP_SCHEMA_GENERATION_INVALID",
			"generation must be none, created_at, or updated_at.",
		)
	return _value_result(
		GDSQLTableAlteration.set_column_generation(
			column.get_value(),
			generation as GDSQLColumnDefinition.Generation,
		),
	)


static func _set_resource_ownership(raw: Dictionary) -> GDSQLOperationResult:
	var unknown := _unknown_key(raw, ["kind", "column", "ownership"])
	if not unknown.is_empty():
		return _unknown_error(unknown)
	var column := _required_name(raw, "column")
	if not column.is_successful():
		return column
	var ownership := _ownership(raw.get("ownership"))
	if ownership < 0:
		return _error(
			&"GDSQL_MCP_SCHEMA_RESOURCE_INVALID",
			"ownership must be owned or referenced.",
		)
	return _value_result(
		GDSQLTableAlteration.set_resource_ownership(
			column.get_value(),
			ownership as GDSQLResourceOwnership.Mode,
		),
	)


static func _reorder_columns(raw: Dictionary) -> GDSQLOperationResult:
	var unknown := _unknown_key(raw, ["kind", "columns"])
	if not unknown.is_empty():
		return _unknown_error(unknown)
	var columns := _name_array(raw.get("columns"), "columns")
	if not columns.is_successful():
		return columns
	return _value_result(GDSQLTableAlteration.reorder_columns(columns.get_value()))


static func _resource_constraint(raw: Variant) -> GDSQLOperationResult:
	if not raw is Dictionary:
		return _error(
			&"GDSQL_MCP_SCHEMA_RESOURCE_INVALID",
			"A resource column requires a resource object.",
		)
	var unknown := _unknown_key(raw, ["class", "script_path", "ownership"])
	if not unknown.is_empty():
		return _unknown_error(unknown)
	if not raw.get("class") is String or String(raw["class"]).is_empty():
		return _error(
			&"GDSQL_MCP_SCHEMA_RESOURCE_INVALID",
			"resource.class must be a non-empty string.",
		)
	var script_path := String(raw.get("script_path", ""))
	if not script_path.is_empty() and (
			not script_path.begins_with("res://") or not ResourceLoader.exists(script_path)
	):
		return _error(
			&"GDSQL_MCP_SCHEMA_RESOURCE_PATH_INVALID",
			"resource.script_path must reference an existing res:// script.",
		)
	var ownership := _ownership(raw.get("ownership"))
	if ownership < 0:
		return _error(
			&"GDSQL_MCP_SCHEMA_RESOURCE_INVALID",
			"resource.ownership must be owned or referenced.",
		)
	var constraint := GDSQLResourceTypeConstraint.from_serialized(
		StringName(raw["class"]),
		script_path,
	)
	if not constraint.is_valid():
		return _error(
			&"GDSQL_MCP_SCHEMA_RESOURCE_INVALID",
			"The Resource class or script constraint is invalid.",
		)
	return _value_result({ "constraint": constraint, "ownership": ownership })


static func _definitions(
		raw: Variant,
		decoder: Callable,
		label: String,
) -> GDSQLOperationResult:
	if not raw is Array:
		return _error(
			&"GDSQL_MCP_SCHEMA_DEFINITION_INVALID",
			"%s list must be an array." % label,
		)
	var values: Array = []
	for raw_value in raw:
		if not raw_value is Dictionary:
			return _error(
				&"GDSQL_MCP_SCHEMA_DEFINITION_INVALID",
				"Every %s must be an object." % label,
			)
		var decoded := decoder.call(raw_value) as GDSQLOperationResult
		if not decoded.is_successful():
			return decoded
		values.append(decoded.get_value())
	return _value_result(values)


static func _required_name(raw: Dictionary, key: String) -> GDSQLOperationResult:
	if not raw.get(key) is String or not String(raw[key]).is_valid_identifier():
		return _error(
			&"GDSQL_MCP_SCHEMA_NAME_INVALID",
			"%s must be a valid non-empty identifier." % key,
		)
	return _value_result(StringName(raw[key]))


static func _name_array(raw: Variant, label: String) -> GDSQLOperationResult:
	if not raw is Array or raw.is_empty():
		return _error(
			&"GDSQL_MCP_SCHEMA_NAMES_INVALID",
			"%s must be a non-empty array of identifiers." % label,
		)
	var values: Array[StringName] = []
	for raw_name in raw:
		if not raw_name is String or not String(raw_name).is_valid_identifier():
			return _error(
				&"GDSQL_MCP_SCHEMA_NAMES_INVALID",
				"Every %s value must be a valid identifier." % label,
			)
		var name := StringName(raw_name)
		if name in values:
			return _error(
				&"GDSQL_MCP_SCHEMA_NAMES_INVALID",
				"%s cannot contain duplicate identifiers." % label,
			)
		values.append(name)
	return _value_result(values)


static func _generation(raw: Variant) -> int:
	if not raw is String:
		return -1
	match String(raw).to_lower():
		"none":
			return GDSQLColumnDefinition.Generation.NONE
		"created_at":
			return GDSQLColumnDefinition.Generation.CREATED_AT
		"updated_at":
			return GDSQLColumnDefinition.Generation.UPDATED_AT
	return -1


static func _ownership(raw: Variant) -> int:
	if not raw is String:
		return -1
	return GDSQLResourceOwnership.from_id(StringName(String(raw).to_lower()))


static func _normalize_default(value: Variant, data_type: Variant.Type) -> Variant:
	match data_type:
		TYPE_BOOL:
			return value if value is bool else null
		TYPE_INT:
			if value is int:
				return value
			if value is float and value == floorf(value):
				return int(value)
		TYPE_FLOAT:
			return float(value) if value is int or value is float else null
		TYPE_STRING:
			return value if value is String else null
		TYPE_STRING_NAME:
			return StringName(value) if value is String else null
	return null


static func _unknown_key(raw: Dictionary, allowed: Array[String]) -> String:
	for key in raw:
		if String(key) not in allowed:
			return String(key)
	return ""


static func _unknown_error(key: String) -> GDSQLOperationResult:
	return _error(
		&"GDSQL_MCP_SCHEMA_FIELD_UNKNOWN",
		"Unknown schema field '%s'." % key,
	)


static func _value_result(value: Variant) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.value = value
	return result


static func _error(code: StringName, message: String) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
