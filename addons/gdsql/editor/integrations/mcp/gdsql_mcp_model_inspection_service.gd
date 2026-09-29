class_name GDSQLMcpModelInspectionService
extends RefCounted
## Statically projects persisted model bindings without executing user model code.

const CURSOR_PREFIX := "gdsql-model-v1:"

var _workbench: GDSQLWorkbench
var _bindings_provider: Callable
var _references_provider: Callable
var _generator := GDSQLModelSourceGenerator.new()
var _compatibility_inspector := GDSQLModelCompatibilityInspector.new()


func _init(
		workbench: GDSQLWorkbench,
		bindings_provider: Callable,
		references_provider: Callable = Callable(),
) -> void:
	_workbench = workbench
	_bindings_provider = bindings_provider
	_references_provider = references_provider


func inspect(
		registration_name: StringName,
		table_name: StringName,
		cursor: String,
		limit: int,
) -> GDSQLOperationResult:
	if _workbench == null or not _bindings_provider.is_valid():
		return _error(
			&"GDSQL_MCP_MODEL_INSPECTION_UNAVAILABLE",
			"Model binding inspection is unavailable.",
		)
	if registration_name == &"" and table_name != &"":
		return _error(
			&"GDSQL_MCP_REGISTRATION_REQUIRED",
			"A registration is required when inspecting one model binding.",
		)
	if registration_name != &"" and _workbench.get_registration(registration_name) == null:
		return _error(
			&"GDSQL_MCP_REGISTRATION_NOT_FOUND",
			"Database registration '%s' was not found." % registration_name,
		)
	var bindings := _bindings()
	if registration_name != &"":
		bindings = bindings.filter(
			func(binding: Dictionary) -> bool:
				return StringName(binding["registration"]) == registration_name,
		)
	if table_name != &"":
		if not cursor.is_empty():
			return _error(
				&"GDSQL_MCP_CURSOR_NOT_APPLICABLE",
				"A cursor cannot be used when inspecting one model binding.",
			)
		for binding in bindings:
			if StringName(binding["table"]) == table_name:
				return _detail(binding)
		return _error(
			&"GDSQL_MCP_MODEL_BINDING_NOT_FOUND",
			"Table '%s' has no model binding in registration '%s'." % [
				table_name,
				registration_name,
			],
		)
	var offset_result := _decode_cursor(cursor)
	if not offset_result.is_successful():
		return offset_result
	var offset := int(offset_result.get_value())
	if offset > bindings.size():
		return _error(&"GDSQL_MCP_CURSOR_INVALID", "The model cursor is out of range.")
	var items: Array[Dictionary] = []
	for index in range(offset, mini(offset + limit, bindings.size())):
		items.append(_summary(bindings[index]))
	return _success(
		{
			"kind": "model_bindings",
			"registration": String(registration_name),
			"items": items,
		},
		_page_meta(offset, limit, bindings.size()),
	)


func _bindings() -> Array[Dictionary]:
	var provided: Variant = _bindings_provider.call()
	var bindings: Array[Dictionary] = []
	if not provided is Array:
		return bindings
	for value in provided:
		if not value is Dictionary:
			continue
		var binding := value as Dictionary
		if String(binding.get("registration", "")).is_empty() \
				or String(binding.get("table", "")).is_empty() \
				or String(binding.get("class_name", "")).is_empty():
			continue
		bindings.append(binding.duplicate(true))
	bindings.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return _binding_key(left) < _binding_key(right),
	)
	return bindings


func _detail(binding: Dictionary) -> GDSQLOperationResult:
	var registration_name := StringName(binding["registration"])
	var registration := _workbench.get_registration(registration_name)
	if StringName(binding.get("database", "")) != registration.database_name:
		return _error(
			&"GDSQL_MCP_MODEL_BINDING_STALE",
			"The model binding for '%s' targets database '%s', but registration '%s' now targets '%s'." % [
				binding["table"],
				binding.get("database", ""),
				registration_name,
				registration.database_name,
			],
		)
	var opened := GDSQLRuntimeFactory.open_authoring_registration(registration)
	if not opened.is_successful():
		return opened
	var database := opened.get_database()
	var definition := database.context.catalog.get_database(database.database_name)
	var table_name := StringName(binding["table"])
	var table := definition.get_table(table_name) if definition != null else null
	if table == null:
		return _error(
			&"GDSQL_MCP_TABLE_NOT_FOUND",
			"Bound table '%s' was not found in registration '%s'." % [
				table_name,
				registration_name,
			],
		)
	var source_result := _generator.build(
		table,
		StringName(binding["class_name"]),
		StringName(binding.get("role", "")),
		String(binding.get("model_root", GDSQLModelSourceGenerator.DEFAULT_ROOT)),
	)
	var result := _summary(binding)
	result["compatibility"] = _compatibility(source_result, table, binding)
	var relationships := GDSQLModelRelationshipInferrer.describe(
		table,
		definition,
	)
	relationships.sort()
	result["catalog_relationships"] = relationships
	result["registered_cross_role_references"] = _references(binding)
	result["relationship_coverage"] = {
		"catalog_foreign_keys": true,
		"registered_cross_role_references": true,
		"explicit_user_relationships_inspected": false,
	}
	return _success({ "kind": "model_binding", "binding": result })


func _compatibility(
		source_result: GDSQLOperationResult,
		table: GDSQLTableDefinition,
		binding: Dictionary,
) -> Dictionary:
	if not source_result.is_successful():
		return {
			"status": "invalid_binding",
			"diagnostics": _serialize_diagnostics(source_result.diagnostics),
		}
	var source := source_result.get_value() as GDSQLModelSource
	var result := {
		"status": "not_generated",
		"generated_path": source.generated_path,
		"user_path": source.user_path,
		"diagnostics": [],
	}
	if not FileAccess.file_exists(source.user_path):
		return result
	var model_script := ResourceLoader.load(
		source.user_path,
		"Script",
		ResourceLoader.CACHE_MODE_REPLACE,
	) as Script
	var report := _compatibility_inspector.inspect(
		model_script,
		table,
		StringName(binding.get("role", "")),
		source.generated_path,
	)
	result["status"] = "compatible" if report.is_compatible() else "needs_update"
	if model_script == null:
		result["status"] = "script_error"
	result["diagnostics"] = _serialize_diagnostics(report.diagnostics)
	return result


func _references(binding: Dictionary) -> Array[Dictionary]:
	var serialized: Array[Dictionary] = []
	if not _references_provider.is_valid():
		return serialized
	var provided: Variant = _references_provider.call(
		StringName(binding["registration"]),
		StringName(binding.get("database", "")),
		StringName(binding["table"]),
	)
	if not provided is Array:
		return serialized
	for value in provided:
		var reference := value as GDSQLEditorContentReference
		if reference == null:
			continue
		serialized.append(
			{
				"name": String(reference.relationship_name),
				"kind": "references_one",
				"local_column": String(reference.source_column_name),
				"target_registration": String(reference.target_registration_name),
				"target_database": String(reference.target_database_name),
				"target_table": String(reference.target_table_name),
				"target_column": String(reference.target_column_name),
				"target_model_class": String(reference.target_model_class),
			},
		)
	serialized.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return String(left["name"]) < String(right["name"]),
	)
	return serialized


func _summary(binding: Dictionary) -> Dictionary:
	return {
		"registration": String(binding["registration"]),
		"database": String(binding.get("database", "")),
		"table": String(binding["table"]),
		"class_name": String(binding["class_name"]),
		"role": String(binding.get("role", "")),
	}


func _page_meta(offset: int, limit: int, total: int) -> Dictionary:
	var next_offset := offset + limit
	return {
		"scope": "current_project",
		"truncated": next_offset < total,
		"next_cursor": _encode_cursor(next_offset) if next_offset < total else "",
		"total": total,
	}


func _encode_cursor(offset: int) -> String:
	return Marshalls.raw_to_base64((CURSOR_PREFIX + str(offset)).to_utf8_buffer())


func _decode_cursor(cursor: String) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if cursor.is_empty():
		result.value = 0
		return result
	var decoded := Marshalls.base64_to_raw(cursor).get_string_from_utf8()
	if not decoded.begins_with(CURSOR_PREFIX):
		return _error(&"GDSQL_MCP_CURSOR_INVALID", "The model cursor is invalid.")
	var offset_text := decoded.trim_prefix(CURSOR_PREFIX)
	if not offset_text.is_valid_int() or int(offset_text) < 0:
		return _error(&"GDSQL_MCP_CURSOR_INVALID", "The model cursor is invalid.")
	result.value = int(offset_text)
	return result


func _serialize_diagnostics(diagnostics: GDSQLDiagnostics) -> Array[Dictionary]:
	var values: Array[Dictionary] = []
	for diagnostic in diagnostics.entries:
		values.append(
			{
				"code": String(diagnostic.code),
				"severity": _severity_id(diagnostic.severity),
				"message": diagnostic.message,
			},
		)
	return values


func _severity_id(severity: GDSQLQueryDiagnostic.Severity) -> String:
	match severity:
		GDSQLQueryDiagnostic.Severity.INFO:
			return "info"
		GDSQLQueryDiagnostic.Severity.WARNING:
			return "warning"
	return "error"


func _binding_key(binding: Dictionary) -> String:
	return "%s:%s:%s" % [
		binding.get("registration", ""),
		binding.get("database", ""),
		binding.get("table", ""),
	]


func _success(data: Dictionary, meta: Dictionary = { }) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.value = { "data": data, "meta": meta }
	return result


func _error(code: StringName, message: String) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
