class_name GDSQLMcpModelAuthoringService
extends RefCounted
## Guarded model-source generation and cross-role content-reference authoring.

signal committed(registration_name: StringName, table_name: StringName)

const Ticket = preload(
	"res://addons/gdsql/editor/integrations/mcp/authoring/model/gdsql_mcp_model_mutation_ticket.gd"
)
const HANDLE_TTL_MSEC := 120_000
const OPERATIONS: Array[String] = [
	"generate_model",
	"register_content_reference",
	"remove_content_reference",
]

var _workbench: GDSQLWorkbench
var _binding_store: GDSQLEditorModelBindingStore
var _reference_store: GDSQLEditorContentReferenceStore
var _tickets: Dictionary[String, GDSQLMcpModelMutationTicket] = { }


class Target extends RefCounted:
	var registration: GDSQLDatabaseRegistration
	var database: GDSQLDatabase
	var table: GDSQLTableDefinition


func _init(
		workbench: GDSQLWorkbench,
		binding_store: GDSQLEditorModelBindingStore = null,
		reference_store: GDSQLEditorContentReferenceStore = null,
) -> void:
	_workbench = workbench
	_binding_store = (
		binding_store if binding_store != null else GDSQLEditorModelBindingStore.new()
	)
	_reference_store = (
		reference_store
		if reference_store != null
		else GDSQLEditorContentReferenceStore.new()
	)


func preview(request: Dictionary) -> GDSQLOperationResult:
	_cleanup_expired()
	var operation := String(request.get("operation", "")).to_lower()
	if operation not in OPERATIONS:
		return _error(
			&"GDSQL_MCP_MODEL_OPERATION_INVALID",
			"Operation must be 'generate_model', 'register_content_reference', or " \
					+ "'remove_content_reference'.",
		)
	var normalized: GDSQLOperationResult
	match operation:
		"generate_model":
			normalized = _prepare_generation(request)
		"register_content_reference":
			normalized = _prepare_reference(request, false)
		"remove_content_reference":
			normalized = _prepare_reference(request, true)
	if not normalized.is_successful():
		return normalized
	var payload := normalized.get_value() as Dictionary
	var ticket := Ticket.new()
	ticket.token = Crypto.new().generate_random_bytes(24).hex_encode()
	ticket.operation = operation
	ticket.payload = payload
	ticket.fingerprint = _fingerprint(operation, payload)
	ticket.expires_at_msec = Time.get_ticks_msec() + HANDLE_TTL_MSEC
	_tickets[ticket.token] = ticket
	return _success(_preview_payload(ticket))


func commit(handle: String, confirmed: bool) -> GDSQLOperationResult:
	_cleanup_expired()
	if not confirmed:
		return _error(
			&"GDSQL_MCP_CONFIRMATION_REQUIRED",
			"The previewed model mutation must be explicitly confirmed.",
		)
	if handle.is_empty() or not _tickets.has(handle):
		return _error(
			&"GDSQL_MCP_MODEL_HANDLE_INVALID",
			"The model mutation handle is invalid, expired, or already used.",
		)
	var ticket := _tickets[handle] as GDSQLMcpModelMutationTicket
	_tickets.erase(handle)
	var request := _request_from_payload(ticket.operation, ticket.payload)
	var refreshed: GDSQLOperationResult
	match ticket.operation:
		"generate_model":
			refreshed = _prepare_generation(request)
		"register_content_reference":
			refreshed = _prepare_reference(request, false)
		"remove_content_reference":
			refreshed = _prepare_reference(request, true)
	if not refreshed.is_successful() \
			or _fingerprint(ticket.operation, refreshed.get_value()) != ticket.fingerprint:
		return _error(
			&"GDSQL_MCP_MODEL_STALE",
			"The table, model files, binding, or content reference changed after preview. " \
					+ "Preview it again.",
		)
	var payload := refreshed.get_value() as Dictionary
	var committed_result: GDSQLOperationResult
	match ticket.operation:
		"generate_model":
			committed_result = _commit_generation(payload)
		"register_content_reference":
			committed_result = _commit_reference(payload, false)
		"remove_content_reference":
			committed_result = _commit_reference(payload, true)
	if committed_result.is_successful():
		committed.emit(payload["source_registration"], payload["source_table"])
	return committed_result


func _prepare_generation(request: Dictionary) -> GDSQLOperationResult:
	var unknown := _unknown_key(
		request,
		["operation", "registration", "table", "class_name", "role", "model_root"],
	)
	if not unknown.is_empty():
		return _error(&"GDSQL_MCP_MODEL_FIELD_UNKNOWN", unknown)
	var resolved := _resolve_target(
		StringName(request.get("registration", "")),
		StringName(request.get("table", "")),
	)
	if not resolved.is_successful():
		return resolved
	var target := resolved.get_value() as Target
	var role := StringName(request.get("role", ""))
	if role == &"":
		role = _role_for_registration(target.registration.name)
	if role == &"":
		return _error(
			&"GDSQL_MCP_MODEL_ROLE_REQUIRED",
			"role is required when the registration has no configured database role.",
		)
	var bound_role := _role_for_registration(target.registration.name)
	if bound_role != &"" and role != bound_role:
		return _error(
			&"GDSQL_MCP_MODEL_ROLE_MISMATCH",
			"Role '%s' does not match registration '%s', which is bound as '%s'." \
					% [role, target.registration.name, bound_role],
		)
	var model_root := String(
		request.get("model_root", _binding_store.load_root()),
	)
	var generated := GDSQLModelSourceGenerator.new().build(
		target.table,
		StringName(request.get("class_name", "")),
		role,
		model_root,
	)
	if not generated.is_successful():
		return generated
	var source := generated.get_value() as GDSQLModelSource
	return _value(
		{
			"operation": "generate_model",
			"source_registration": target.registration.name,
			"source_database": target.registration.database_name,
			"source_table": target.table.name,
			"class_name": source.model_class_name,
			"role": role,
			"model_root": model_root.strip_edges().trim_suffix("/").simplify_path(),
			"generated_path": source.generated_path,
			"user_path": source.user_path,
			"generated_source": source.generated_source,
			"user_source": source.user_source,
		},
	)


func _prepare_reference(request: Dictionary, remove: bool) -> GDSQLOperationResult:
	var allowed: Array[String] = [
		"operation", "source_registration", "source_table", "source_column",
	]
	if not remove:
		allowed.append_array(
			[
				"target_registration", "target_table", "target_column",
				"target_model_class", "relationship_name",
			],
		)
	var unknown := _unknown_key(request, allowed)
	if not unknown.is_empty():
		return _error(&"GDSQL_MCP_MODEL_FIELD_UNKNOWN", unknown)
	var source_result := _resolve_target(
		StringName(request.get("source_registration", "")),
		StringName(request.get("source_table", "")),
	)
	if not source_result.is_successful():
		return source_result
	var source := source_result.get_value() as Target
	var source_column_name := StringName(request.get("source_column", ""))
	var current := _reference_for_column(
		source.registration.name,
		source.registration.database_name,
		source.table.name,
		source_column_name,
	)
	if remove:
		if current == null:
			return _error(
				&"GDSQL_MCP_CONTENT_REFERENCE_NOT_FOUND",
				"No content reference is registered for '%s.%s'." \
						% [source.table.name, source_column_name],
			)
		return _value(_reference_payload(current, true))
	var source_column := source.table.get_column(source_column_name)
	if source_column == null:
		return _error(
			&"GDSQL_MCP_COLUMN_NOT_FOUND",
			"Column '%s' was not found in table '%s'." % [source_column_name, source.table.name],
		)
	if _role_for_registration(source.registration.name) != GDSQLDatabaseRegistry.SAVE_ROLE:
		return _error(
			&"GDSQL_MCP_CONTENT_REFERENCE_SOURCE_ROLE",
			"Content references must originate from the registration bound to the save role.",
		)
	if not GDSQLForeignKeyDefinition.supports_column_type(source_column.data_type):
		return _error(
			&"GDSQL_MCP_CONTENT_REFERENCE_TYPE",
			"Content-reference identifiers must use int, String, or StringName columns.",
		)
	var target_result := _resolve_target(
		StringName(request.get("target_registration", "")),
		StringName(request.get("target_table", "")),
	)
	if not target_result.is_successful():
		return target_result
	var target := target_result.get_value() as Target
	if _role_for_registration(target.registration.name) != GDSQLDatabaseRegistry.CONTENT_ROLE:
		return _error(
			&"GDSQL_MCP_CONTENT_REFERENCE_TARGET_ROLE",
			"Content references must target the registration bound to the content role.",
		)
	var target_column_name := StringName(request.get("target_column", target.table.primary_key))
	if target_column_name != target.table.primary_key:
		return _error(
			&"GDSQL_MCP_CONTENT_REFERENCE_TARGET_KEY",
			"A content reference must target the content table primary key.",
		)
	var target_column := target.table.get_column(target_column_name)
	if target_column == null or target_column.data_type != source_column.data_type:
		return _error(
			&"GDSQL_MCP_CONTENT_REFERENCE_TYPE_MISMATCH",
			"Source and target identifier columns must have the same scalar type.",
		)
	var relationship_name := String(request.get("relationship_name", "")).strip_edges()
	if not relationship_name.is_valid_identifier() \
			or relationship_name != relationship_name.to_snake_case():
		return _error(
			&"GDSQL_MCP_CONTENT_REFERENCE_NAME_INVALID",
			"relationship_name must be a valid snake_case identifier.",
		)
	var target_binding := _binding_store.load_for_table(
		target.registration.name,
		target.registration.database_name,
		target.table.name,
	)
	if target_binding.is_empty():
		return _error(
			&"GDSQL_MCP_CONTENT_REFERENCE_MODEL_REQUIRED",
			"Generate or register the target content model before creating its reference.",
		)
	var model_class := String(target_binding["class_name"])
	var requested_class := String(request.get("target_model_class", "")).strip_edges()
	if not requested_class.is_empty() and requested_class != model_class:
		return _error(
			&"GDSQL_MCP_CONTENT_REFERENCE_MODEL_MISMATCH",
			"target_model_class does not match the registered content model '%s'." \
					% model_class,
		)
	if not model_class.is_valid_identifier():
		return _error(
			&"GDSQL_MCP_CONTENT_REFERENCE_MODEL_INVALID",
			"target_model_class must be a valid GDScript class name.",
		)
	var reference := GDSQLEditorContentReference.new(
		StringName(relationship_name),
		source.registration.name,
		source.registration.database_name,
		source.table.name,
		source_column_name,
		target.registration.name,
		target.registration.database_name,
		target.table.name,
		target_column_name,
		StringName(model_class),
	)
	var payload := _reference_payload(reference, false)
	payload["replaces_existing"] = current != null
	return _value(payload)


func _commit_generation(payload: Dictionary) -> GDSQLOperationResult:
	var generated_error := _write_text(payload["generated_path"], payload["generated_source"])
	if generated_error != OK:
		return _file_error(payload["generated_path"], generated_error)
	var user_created := not FileAccess.file_exists(payload["user_path"])
	if user_created:
		var user_error := _write_text(payload["user_path"], payload["user_source"])
		if user_error != OK:
			return _file_error(payload["user_path"], user_error)
	var binding_error := _binding_store.save(
		payload["source_registration"],
		payload["source_database"],
		payload["source_table"],
		payload["class_name"],
		payload["role"],
		payload["model_root"],
	)
	if binding_error != OK:
		return _error(
			&"GDSQL_MCP_MODEL_BINDING_WRITE_FAILED",
			"Could not save the model binding (%s)." % error_string(binding_error),
		)
	return _success(
		{
			"kind": "model_mutation_commit",
			"operation": "generate_model",
			"registration": String(payload["source_registration"]),
			"table": String(payload["source_table"]),
			"generated_path": payload["generated_path"],
			"user_path": payload["user_path"],
			"user_file_created": user_created,
			"user_file_preserved": not user_created,
		},
	)


func _commit_reference(payload: Dictionary, remove: bool) -> GDSQLOperationResult:
	var reference := _reference_from_payload(payload)
	var store_error := (
		_reference_store.remove(reference) if remove else _reference_store.save(reference)
	)
	if store_error != OK:
		return _error(
			&"GDSQL_MCP_CONTENT_REFERENCE_WRITE_FAILED",
			"Could not %s the content reference (%s)." \
					% ["remove" if remove else "save", error_string(store_error)],
		)
	return _success(
		{
			"kind": "model_mutation_commit",
			"operation": "remove_content_reference" if remove else "register_content_reference",
			"registration": String(reference.source_registration_name),
			"table": String(reference.source_table_name),
			"source_column": String(reference.source_column_name),
			"relationship_name": String(reference.relationship_name),
		},
	)


func _preview_payload(ticket: GDSQLMcpModelMutationTicket) -> Dictionary:
	var payload := ticket.payload
	var data := {
		"kind": "model_mutation_preview",
		"operation": ticket.operation,
		"registration": String(payload["source_registration"]),
		"table": String(payload["source_table"]),
		"destructive": ticket.operation == "remove_content_reference",
		"confirmation_handle": ticket.token,
		"expires_in_ms": HANDLE_TTL_MSEC,
	}
	if ticket.operation == "generate_model":
		data.merge(
			{
				"class_name": String(payload["class_name"]),
				"role": String(payload["role"]),
				"generated_path": payload["generated_path"],
				"user_path": payload["user_path"],
				"generated_file_will_replace": FileAccess.file_exists(payload["generated_path"]),
				"user_file_will_be_created": not FileAccess.file_exists(payload["user_path"]),
				"user_file_will_be_preserved": FileAccess.file_exists(payload["user_path"]),
			},
		)
	else:
		data.merge(
			{
				"source_column": String(payload["source_column"]),
				"target_registration": String(payload["target_registration"]),
				"target_table": String(payload["target_table"]),
				"target_column": String(payload["target_column"]),
				"relationship_name": String(payload["relationship_name"]),
				"relationship_snippet": _reference_from_payload(payload).build_relationship_snippet(),
				"replaces_existing": bool(payload.get("replaces_existing", false)),
			},
		)
	return data


func _resolve_target(
		registration_name: StringName,
		table_name: StringName,
) -> GDSQLOperationResult:
	if _workbench == null:
		return _error(&"GDSQL_MCP_WORKBENCH_REQUIRED", "The GDSQL workbench is unavailable.")
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
			"Table '%s' was not found in registration '%s'." % [table_name, registration_name],
		)
	var target := Target.new()
	target.registration = registration
	target.database = database
	target.table = table
	return _value(target)


func _role_for_registration(registration_name: StringName) -> StringName:
	if _workbench == null or _workbench.snapshot == null:
		return &""
	for binding in _workbench.snapshot.role_bindings:
		if binding.registration_name == registration_name:
			return binding.role
	return &""


func _reference_for_column(
		registration_name: StringName,
		database_name: StringName,
		table_name: StringName,
		column_name: StringName,
) -> GDSQLEditorContentReference:
	for reference in _reference_store.load_for_table(
		registration_name,
		database_name,
		table_name,
	):
		if reference.source_column_name == column_name:
			return reference
	return null


func _reference_payload(
		reference: GDSQLEditorContentReference,
		remove: bool,
) -> Dictionary:
	return {
		"operation": "remove_content_reference" if remove else "register_content_reference",
		"source_registration": reference.source_registration_name,
		"source_database": reference.source_database_name,
		"source_table": reference.source_table_name,
		"source_column": reference.source_column_name,
		"target_registration": reference.target_registration_name,
		"target_database": reference.target_database_name,
		"target_table": reference.target_table_name,
		"target_column": reference.target_column_name,
		"target_model_class": reference.target_model_class,
		"relationship_name": reference.relationship_name,
	}


func _reference_from_payload(payload: Dictionary) -> GDSQLEditorContentReference:
	return GDSQLEditorContentReference.new(
		payload["relationship_name"],
		payload["source_registration"],
		payload["source_database"],
		payload["source_table"],
		payload["source_column"],
		payload["target_registration"],
		payload["target_database"],
		payload["target_table"],
		payload["target_column"],
		payload["target_model_class"],
	)


func _request_from_payload(operation: String, payload: Dictionary) -> Dictionary:
	if operation == "generate_model":
		return {
			"operation": operation,
			"registration": payload["source_registration"],
			"table": payload["source_table"],
			"class_name": payload["class_name"],
			"role": payload["role"],
			"model_root": payload["model_root"],
		}
	var request := {
		"operation": operation,
		"source_registration": payload["source_registration"],
		"source_table": payload["source_table"],
		"source_column": payload["source_column"],
	}
	if operation == "register_content_reference":
		request.merge(
			{
				"target_registration": payload["target_registration"],
				"target_table": payload["target_table"],
				"target_column": payload["target_column"],
				"target_model_class": payload["target_model_class"],
				"relationship_name": payload["relationship_name"],
			},
		)
	return request


func _fingerprint(operation: String, payload: Dictionary) -> String:
	var values: Array = [operation, payload]
	if operation == "generate_model":
		values.append(_file_hash(payload["generated_path"]))
		values.append(_file_hash(payload["user_path"]))
		values.append(
			_binding_store.load_for_table(
				payload["source_registration"],
				payload["source_database"],
				payload["source_table"],
			),
		)
	else:
		var current := _reference_for_column(
			payload["source_registration"],
			payload["source_database"],
			payload["source_table"],
			payload["source_column"],
		)
		values.append(_reference_payload(current, false) if current != null else { })
	return var_to_str(values).sha256_text()


func _file_hash(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "missing"
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_as_text().sha256_text() if file != null else "unreadable"


func _write_text(path: String, content: String) -> Error:
	var directory_error := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(path.get_base_dir()),
	)
	if directory_error != OK:
		return directory_error
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(content)
	return OK


func _file_error(path: String, write_error: Error) -> GDSQLOperationResult:
	return _error(
		&"GDSQL_MCP_MODEL_FILE_WRITE_FAILED",
		"Could not write '%s' (%s)." % [path, error_string(write_error)],
	)


func _cleanup_expired() -> void:
	for token in _tickets.keys():
		if (_tickets[token] as GDSQLMcpModelMutationTicket).is_expired():
			_tickets.erase(token)


func _unknown_key(values: Dictionary, allowed: Array[String]) -> String:
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
