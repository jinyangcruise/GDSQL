class_name GDSQLMcpInspectionService
extends RefCounted
## Projects editor-known GDSQL state into bounded JSON-compatible MCP data.

const SURFACE_VERSION := "1.0.0"
const DEFAULT_LIMIT := 25
const MAX_LIMIT := 100
const CURSOR_PREFIX := "gdsql-v1:"

var _workbench: GDSQLWorkbench
var _profile_store: GDSQLSetupProfileStore
var _managed_configuration_store: GDSQLManagedContentConfigurationStore
var _manifest_store: GDSQLContentPackageManifestStore
var _cache_store: GDSQLContentCacheStore
var _explorer: GDSQLDatabaseExplorer
var _model_count_provider: Callable
var _runtime_adapter_provider: Callable
var _model_inspection_service: RefCounted


func _init(
		workbench: GDSQLWorkbench,
		profile_store: GDSQLSetupProfileStore,
		managed_configuration_store: GDSQLManagedContentConfigurationStore,
		manifest_store: GDSQLContentPackageManifestStore,
		cache_store: GDSQLContentCacheStore,
		explorer: GDSQLDatabaseExplorer,
		model_count_provider: Callable = Callable(),
		runtime_adapter_provider: Callable = Callable(),
		model_inspection_service: RefCounted = null,
) -> void:
	_workbench = workbench
	_profile_store = profile_store
	_managed_configuration_store = managed_configuration_store
	_manifest_store = manifest_store
	_cache_store = cache_store
	_explorer = explorer
	_model_count_provider = model_count_provider
	_runtime_adapter_provider = runtime_adapter_provider
	_model_inspection_service = model_inspection_service


func get_capabilities() -> GDSQLOperationResult:
	var dependencies := _require_dependencies(false)
	if not dependencies.is_successful():
		return dependencies
	var loaded_profile := _profile_store.load_profile()
	if not loaded_profile.is_successful():
		return loaded_profile
	return _success(
		{
			"project_scope": "current_project",
			"selected_profile": _profile_id(loaded_profile.get_value()),
			"features": [
				{ "id": "capabilities", "enabled": true },
				{ "id": "model_inspection", "enabled": true },
				{ "id": "mutations", "enabled": false },
				{ "id": "query_drafting", "enabled": false },
				{ "id": "schema_inspection", "enabled": true },
				{ "id": "setup_inspection", "enabled": true },
			],
			"limits": {
				"default_items": DEFAULT_LIMIT,
				"maximum_items": MAX_LIMIT,
				"row_values_exposed": false,
			},
			"tools": [
				{ "name": "gdsql_capabilities", "read_only": true },
				{ "name": "gdsql_inspect_models", "read_only": true },
				{ "name": "gdsql_inspect_schema", "read_only": true },
				{ "name": "gdsql_inspect_setup", "read_only": true },
			],
		},
	)


func inspect_models(
		registration_name: StringName = &"",
		table_name: StringName = &"",
		cursor: String = "",
		limit: int = DEFAULT_LIMIT,
) -> GDSQLOperationResult:
	var dependencies := _require_dependencies(false)
	if not dependencies.is_successful():
		return dependencies
	if _model_inspection_service == null:
		return _error(
			&"GDSQL_MCP_MODEL_INSPECTION_UNAVAILABLE",
			"Model binding inspection is unavailable.",
		)
	if limit < 1 or limit > MAX_LIMIT:
		return _error(
			&"GDSQL_MCP_LIMIT_INVALID",
			"Limit must be between 1 and %d." % MAX_LIMIT,
		)
	var inspected := _model_inspection_service.call(
		"inspect",
		registration_name,
		table_name,
		cursor,
		limit,
	) as GDSQLOperationResult
	if not inspected.is_successful():
		return inspected
	var projection := inspected.get_value() as Dictionary
	return _success(
		projection.get("data", { }),
		[],
		projection.get("meta", { }),
	)


func inspect_setup(requested_profile: StringName = &"selected") -> GDSQLOperationResult:
	var dependencies := _require_dependencies(true)
	if not dependencies.is_successful():
		return dependencies
	var loaded_profile := _profile_store.load_profile()
	if not loaded_profile.is_successful():
		return loaded_profile
	var selected := loaded_profile.get_value() as GDSQLSetupProfile.Kind
	var profile := selected
	match requested_profile:
		&"selected":
			pass
		&"direct":
			profile = GDSQLSetupProfile.Kind.DIRECT
		&"managed":
			profile = GDSQLSetupProfile.Kind.MANAGED
		_:
			return _error(
				&"GDSQL_MCP_PROFILE_INVALID",
				"Profile must be 'selected', 'direct', or 'managed'.",
			)
	var report := _build_setup_report(profile)
	var next := report.get_next_incomplete()
	var checks: Array[Dictionary] = []
	for check in report.checks:
		checks.append(
			{
				"id": String(check.id),
				"label": check.label,
				"complete": check.complete,
				"detail": check.detail,
				"next_action": String(check.next_action),
			},
		)
	return _success(
		{
			"selected_profile": _profile_id(selected),
			"inspected_profile": _profile_id(profile),
			"ready": report.is_ready(),
			"next_check": String(next.id) if next != null else "",
			"checks": checks,
		},
		_serialize_diagnostics(report.diagnostics),
	)


func inspect_schema(
		registration_name: StringName = &"",
		table_name: StringName = &"",
		cursor: String = "",
		limit: int = DEFAULT_LIMIT,
) -> GDSQLOperationResult:
	var dependencies := _require_dependencies(false)
	if not dependencies.is_successful():
		return dependencies
	if limit < 1 or limit > MAX_LIMIT:
		return _error(
			&"GDSQL_MCP_LIMIT_INVALID",
			"Limit must be between 1 and %d." % MAX_LIMIT,
		)
	if registration_name == &"" and table_name != &"":
		return _error(
			&"GDSQL_MCP_REGISTRATION_REQUIRED",
			"A registration is required when inspecting a table.",
		)
	var offset_result := _decode_cursor(cursor)
	if not offset_result.is_successful():
		return offset_result
	var offset := int(offset_result.get_value())
	if registration_name == &"":
		return _registration_page(offset, limit)
	var registration := _workbench.get_registration(registration_name)
	if registration == null:
		return _error(
			&"GDSQL_MCP_REGISTRATION_NOT_FOUND",
			"Database registration '%s' was not found." % registration_name,
		)
	var inspection := _workbench.get_inspection(registration_name)
	if table_name == &"":
		return _table_page(registration, inspection, offset, limit)
	if not cursor.is_empty():
		return _error(
			&"GDSQL_MCP_CURSOR_NOT_APPLICABLE",
			"A cursor cannot be used when inspecting one table.",
		)
	return _table_detail(registration, inspection, table_name)


func _registration_page(offset: int, limit: int) -> GDSQLOperationResult:
	var registrations := _workbench.get_registrations()
	registrations.sort_custom(
		func(left: GDSQLDatabaseRegistration, right: GDSQLDatabaseRegistration) -> bool:
			return String(left.name).naturalnocasecmp_to(String(right.name)) < 0,
	)
	if offset > registrations.size():
		return _error(&"GDSQL_MCP_CURSOR_INVALID", "The schema cursor is out of range.")
	var items: Array[Dictionary] = []
	for index in range(offset, mini(offset + limit, registrations.size())):
		var registration := registrations[index]
		items.append(
			_registration_summary(
				registration,
				_workbench.get_inspection(registration.name),
			),
		)
	return _success(
		{ "kind": "registrations", "items": items },
		[],
		_page_meta(offset, limit, registrations.size()),
	)


func _table_page(
		registration: GDSQLDatabaseRegistration,
		inspection: GDSQLDatabaseInspection,
		offset: int,
		limit: int,
) -> GDSQLOperationResult:
	var tables: Array[GDSQLTableInspection] = []
	if inspection != null:
		tables = inspection.tables.duplicate()
	tables.sort_custom(
		func(left: GDSQLTableInspection, right: GDSQLTableInspection) -> bool:
			return String(left.name).naturalnocasecmp_to(String(right.name)) < 0,
	)
	if offset > tables.size():
		return _error(&"GDSQL_MCP_CURSOR_INVALID", "The schema cursor is out of range.")
	var items: Array[Dictionary] = []
	for index in range(offset, mini(offset + limit, tables.size())):
		items.append(_table_summary(tables[index]))
	return _success(
		{
			"kind": "tables",
			"registration": _registration_summary(registration, inspection),
			"items": items,
		},
		[],
		_page_meta(offset, limit, tables.size()),
	)


func _table_detail(
		registration: GDSQLDatabaseRegistration,
		inspection: GDSQLDatabaseInspection,
		table_name: StringName,
) -> GDSQLOperationResult:
	if inspection == null or inspection.get_table(table_name) == null:
		return _error(
			&"GDSQL_MCP_TABLE_NOT_FOUND",
			"Table '%s' was not found in registration '%s'." % [
				table_name,
				registration.name,
			],
		)
	var opened := GDSQLRuntimeFactory.open_authoring_registration(registration)
	if not opened.is_successful():
		return opened
	var database := opened.get_database()
	var table := database.context.catalog.get_table(database.database_name, table_name)
	if table == null:
		return _error(
			&"GDSQL_MCP_TABLE_NOT_FOUND",
			"Table '%s' could not be loaded from registration '%s'." % [
				table_name,
				registration.name,
			],
		)
	return _success(
		{
			"kind": "table",
			"registration": _registration_summary(registration, inspection),
			"table": _serialize_table(table, inspection.get_table(table_name)),
		},
	)


func _build_setup_report(profile: GDSQLSetupProfile.Kind) -> GDSQLSetupReport:
	if profile == GDSQLSetupProfile.Kind.DIRECT:
		return GDSQLDirectSetupInspector.inspect_editor(
			_workbench.snapshot,
			_workbench.get_inspections(),
			_model_count(),
			_runtime_adapter_configured(),
		)
	if profile == GDSQLSetupProfile.Kind.MANAGED:
		return _build_managed_report()
	var report := GDSQLSetupReport.new("GDSQL_SETUP")
	report.add_check(
		GDSQLSetupCheck.new(
			&"profile",
			"Content profile",
			false,
			"Choose Direct Content or Managed Content in the GDSQL welcome page.",
		),
	)
	return report


func _build_managed_report() -> GDSQLManagedSetupReport:
	var source_diagnostics := GDSQLDiagnostics.new()
	var configuration: GDSQLManagedContentConfiguration
	var loaded_configuration := _managed_configuration_store.load_configuration()
	source_diagnostics.merge(loaded_configuration.diagnostics)
	if loaded_configuration.is_successful():
		configuration = loaded_configuration.get_value()
	var source: GDSQLContentPackageSource
	var base_inspection: GDSQLDatabaseInspection
	if configuration != null:
		var loaded_manifest := _manifest_store.load_manifest(configuration.base_package_root)
		source_diagnostics.merge(loaded_manifest.diagnostics)
		if loaded_manifest.is_successful():
			source = GDSQLContentPackageSource.new(
				configuration.base_package_root,
				loaded_manifest.get_value(),
			)
			var inspected := _explorer.inspect_root(source.get_data_root())
			source_diagnostics.merge(inspected.diagnostics)
			if inspected.is_successful():
				for value in inspected.get_value():
					var candidate := value as GDSQLDatabaseInspection
					if candidate.registration.database_name \
							== GDSQLContentOverlayLoader.DEFAULT_SOURCE_DATABASE:
						base_inspection = candidate
						break
	var cached := _cache_store.load_manifest()
	source_diagnostics.merge(cached.diagnostics)
	var report := GDSQLManagedSetupInspector.inspect_editor(
		source,
		base_inspection,
		cached.get_value() as GDSQLContentCacheManifest,
		_workbench.snapshot,
		_model_count(),
		_runtime_adapter_configured(),
	)
	report.diagnostics.merge(source_diagnostics)
	return report


func _registration_summary(
		registration: GDSQLDatabaseRegistration,
		inspection: GDSQLDatabaseInspection,
) -> Dictionary:
	var roles: Array[String] = []
	for binding in _workbench.snapshot.role_bindings:
		if binding.registration_name == registration.name:
			roles.append(String(binding.role))
	roles.sort()
	var result := {
		"name": String(registration.name),
		"database": String(registration.database_name),
		"storage_backend": String(registration.storage_backend_id),
		"roles": roles,
		"catalog_exists": inspection != null and inspection.catalog_exists,
		"table_count": inspection.tables.size() if inspection != null else 0,
	}
	if registration.data_root.begins_with("res://") or registration.data_root.begins_with("user://"):
		result["data_root"] = registration.data_root
	else:
		result["data_root_scope"] = "custom"
	return result


func _table_summary(table: GDSQLTableInspection) -> Dictionary:
	return {
		"name": String(table.name),
		"schema_exists": table.schema_exists,
		"storage_exists": table.storage_exists,
		"row_count": table.row_count,
		"column_count": table.column_count,
		"index_count": table.index_count,
		"primary_key": String(table.primary_key),
	}


func _serialize_table(
		table: GDSQLTableDefinition,
		inspection: GDSQLTableInspection,
) -> Dictionary:
	var columns: Array[Dictionary] = []
	for column in table.columns:
		columns.append(_serialize_column(column))
	var indexes := table.indexes.duplicate()
	indexes.sort_custom(
		func(left: GDSQLIndexDefinition, right: GDSQLIndexDefinition) -> bool:
			return String(left.name).naturalnocasecmp_to(String(right.name)) < 0,
	)
	var serialized_indexes: Array[Dictionary] = []
	for index in indexes:
		var names: Array[String] = []
		for column_name in index.columns:
			names.append(String(column_name))
		serialized_indexes.append(
			{ "name": String(index.name), "columns": names, "unique": index.unique },
		)
	var foreign_keys := table.foreign_keys.duplicate()
	foreign_keys.sort_custom(
		func(left: GDSQLForeignKeyDefinition, right: GDSQLForeignKeyDefinition) -> bool:
			return String(left.name).naturalnocasecmp_to(String(right.name)) < 0,
	)
	var serialized_foreign_keys: Array[Dictionary] = []
	for foreign_key in foreign_keys:
		serialized_foreign_keys.append(
			{
				"name": String(foreign_key.name),
				"column": String(foreign_key.column),
				"referenced_table": String(foreign_key.referenced_table),
				"referenced_column": String(foreign_key.referenced_column),
				"on_delete": "restrict",
				"on_update": "restrict",
			},
		)
	return {
		"name": String(table.name),
		"primary_key": String(table.primary_key),
		"row_count": inspection.row_count,
		"columns": columns,
		"indexes": serialized_indexes,
		"foreign_keys": serialized_foreign_keys,
	}


func _serialize_column(column: GDSQLColumnDefinition) -> Dictionary:
	var result := {
		"name": String(column.name),
		"type": column.display_type_name(),
		"variant_type": type_string(column.data_type),
		"nullable": column.nullable,
		"unique": column.unique,
		"auto_increment": column.auto_increment,
		"generation": _generation_id(column.generation),
		"has_default": column.has_default(),
	}
	if column.data_type == TYPE_OBJECT and column.resource_type != null:
		result["resource"] = {
			"class": String(column.resource_type.resource_class),
			"ownership": String(GDSQLResourceOwnership.to_id(column.resource_ownership)),
		}
		if column.resource_type.script_path.begins_with("res://"):
			result["resource"]["script_path"] = column.resource_type.script_path
	if column.has_default():
		var default_value: Variant = column.get_default_value()
		result["default_type"] = type_string(typeof(default_value))
		if typeof(default_value) in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME]:
			result["default"] = String(default_value) if default_value is StringName else default_value
	return result


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
		return _error(&"GDSQL_MCP_CURSOR_INVALID", "The schema cursor is invalid.")
	var offset_text := decoded.trim_prefix(CURSOR_PREFIX)
	if not offset_text.is_valid_int() or int(offset_text) < 0:
		return _error(&"GDSQL_MCP_CURSOR_INVALID", "The schema cursor is invalid.")
	result.value = int(offset_text)
	return result


func _success(
		data: Dictionary,
		diagnostics: Array[Dictionary] = [],
		meta: Dictionary = { },
) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	var response_meta := { "scope": "current_project", "truncated": false, "next_cursor": "" }
	response_meta.merge(meta, true)
	result.value = {
		"surface_version": SURFACE_VERSION,
		"ok": true,
		"data": data,
		"diagnostics": diagnostics,
		"meta": response_meta,
	}
	return result


func _error(code: StringName, message: String) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result


func _require_dependencies(include_setup: bool) -> GDSQLOperationResult:
	if _workbench == null:
		return _error(&"GDSQL_MCP_WORKBENCH_REQUIRED", "The GDSQL workbench is unavailable.")
	if _profile_store == null:
		return _error(&"GDSQL_MCP_PROFILE_STORE_REQUIRED", "The setup profile store is unavailable.")
	if include_setup and (
			_managed_configuration_store == null
			or _manifest_store == null
			or _cache_store == null
			or _explorer == null
	):
		return _error(&"GDSQL_MCP_SETUP_SERVICES_REQUIRED", "Setup inspection services are unavailable.")
	var result := GDSQLOperationResult.new()
	result.value = true
	return result


func _serialize_diagnostics(diagnostics: GDSQLDiagnostics) -> Array[Dictionary]:
	var serialized: Array[Dictionary] = []
	for diagnostic in diagnostics.entries:
		serialized.append(
			{
				"code": String(diagnostic.code),
				"severity": _severity_id(diagnostic.severity),
				"message": diagnostic.message,
			},
		)
	serialized.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			var severity_order := { "error": 0, "warning": 1, "info": 2 }
			var left_key := "%d:%s" % [severity_order[left["severity"]], left["code"]]
			var right_key := "%d:%s" % [severity_order[right["severity"]], right["code"]]
			return left_key < right_key,
	)
	return serialized


func _profile_id(profile: GDSQLSetupProfile.Kind) -> String:
	var id := GDSQLSetupProfile.get_id(profile)
	return String(id) if id != &"" else "unselected"


func _severity_id(severity: GDSQLQueryDiagnostic.Severity) -> String:
	match severity:
		GDSQLQueryDiagnostic.Severity.INFO:
			return "info"
		GDSQLQueryDiagnostic.Severity.WARNING:
			return "warning"
	return "error"


func _generation_id(generation: GDSQLColumnDefinition.Generation) -> String:
	match generation:
		GDSQLColumnDefinition.Generation.CREATED_AT:
			return "created_at"
		GDSQLColumnDefinition.Generation.UPDATED_AT:
			return "updated_at"
	return "none"


func _model_count() -> int:
	return maxi(int(_model_count_provider.call()), 0) if _model_count_provider.is_valid() else 0


func _runtime_adapter_configured() -> bool:
	return bool(_runtime_adapter_provider.call()) if _runtime_adapter_provider.is_valid() else false
