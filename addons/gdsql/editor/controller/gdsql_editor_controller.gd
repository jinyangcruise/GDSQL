@tool
class_name GDSQLEditorController
extends RefCounted
## Coordinates GDSQL editor actions, workbench state, and editor surfaces.
##
## Godot plugin lifecycle and control placement remain in the EditorPlugin.

const PROJECT_DATA_ROOT := "res://data"

var action_hub: GDSQLEditorActionHub
var workbench: GDSQLWorkbench
var _workspace: GDSQLWorkspace
var _database_dock: GDSQLDatabaseDock
var _logs_panel: GDSQLLogsPanel
var _workspace_loaded := false
var _request_filesystem_scan: Callable


func _init(
		workspace: GDSQLWorkspace,
		database_dock: GDSQLDatabaseDock,
		logs_panel: GDSQLLogsPanel,
		request_filesystem_scan: Callable = Callable(),
) -> void:
	_workspace = workspace
	_database_dock = database_dock
	_logs_panel = logs_panel
	_request_filesystem_scan = request_filesystem_scan
	_create_workbench()
	_create_actions()
	_configure_surfaces()


func load_workspace() -> GDSQLOperationResult:
	if workbench == null:
		return _error(
			&"GDSQL_EDITOR_WORKBENCH_REQUIRED",
			"The editor requires a workbench coordinator.",
		)
	var result := GDSQLOperationResult.new()
	var loaded := workbench.load()
	result.diagnostics.merge(loaded.diagnostics)
	if loaded.is_successful():
		var discovered := workbench.discover_root(PROJECT_DATA_ROOT, &"project")
		result.diagnostics.merge(discovered.diagnostics)
	_refresh_surfaces()
	_workspace_loaded = result.is_successful()
	_record_result("Load workspace", result)
	result.value = workbench
	return result


func ensure_workspace_loaded() -> GDSQLOperationResult:
	if _workspace_loaded:
		var result := GDSQLOperationResult.new()
		result.value = workbench
		return result
	return load_workspace()


func shutdown() -> void:
	if is_instance_valid(_workspace) \
			and _workspace.database_create_submitted.is_connected(_create_database):
		_workspace.database_create_submitted.disconnect(_create_database)
	if is_instance_valid(_workspace) \
			and _workspace.database_save_submitted.is_connected(_save_database):
		_workspace.database_save_submitted.disconnect(_save_database)
	if is_instance_valid(_workspace) \
			and _workspace.database_refresh_submitted.is_connected(_refresh_database_document):
		_workspace.database_refresh_submitted.disconnect(_refresh_database_document)
	if is_instance_valid(_workspace) \
			and _workspace.table_rows_requested.is_connected(_load_table_rows):
		_workspace.table_rows_requested.disconnect(_load_table_rows)
	if is_instance_valid(_workspace) \
			and _workspace.table_row_insert_requested.is_connected(_insert_table_row):
		_workspace.table_row_insert_requested.disconnect(_insert_table_row)
	if is_instance_valid(_workspace) \
			and _workspace.table_row_update_requested.is_connected(_update_table_row):
		_workspace.table_row_update_requested.disconnect(_update_table_row)
	if is_instance_valid(_workspace) \
			and _workspace.table_row_delete_requested.is_connected(_delete_table_row):
		_workspace.table_row_delete_requested.disconnect(_delete_table_row)
	_workspace = null
	_database_dock = null
	_logs_panel = null
	action_hub = null
	workbench = null


func _create_workbench() -> void:
	var store := GDSQLConfigFileDatabaseRegistryStore.new()
	var registry := GDSQLDatabaseRegistry.new(store)
	workbench = GDSQLWorkbench.new(registry, GDSQLConfigFileDatabaseExplorer.new())


func _create_actions() -> void:
	action_hub = GDSQLEditorActionHub.new()
	var handlers: Dictionary[StringName, Callable] = {
		GDSQLEditorActionIds.CREATE_DATABASE: _show_create_database,
		GDSQLEditorActionIds.CREATE_TABLE: _show_create_table,
		GDSQLEditorActionIds.REMOVE_REGISTRATION: _remove_registration,
		GDSQLEditorActionIds.DROP_TABLE: _drop_table,
		GDSQLEditorActionIds.DISCOVER_PROJECT: _discover_project,
		GDSQLEditorActionIds.REFRESH_DATABASES: _refresh_databases,
		GDSQLEditorActionIds.OPEN_REGISTRATION: _open_registration,
		GDSQLEditorActionIds.SELECT_TABLE: _select_table,
		GDSQLEditorActionIds.SHOW_WELCOME: _show_welcome,
	}
	var registered := GDSQLEditorActionRegistrar.new() \
			.register_global_actions(action_hub, handlers)
	assert(registered.is_successful())


func _configure_surfaces() -> void:
	_workspace.configure(action_hub)
	_workspace.database_create_submitted.connect(_create_database)
	_workspace.database_save_submitted.connect(_save_database)
	_workspace.database_refresh_submitted.connect(_refresh_database_document)
	_workspace.table_rows_requested.connect(_load_table_rows)
	_workspace.table_row_insert_requested.connect(_insert_table_row)
	_workspace.table_row_update_requested.connect(_update_table_row)
	_workspace.table_row_delete_requested.connect(_delete_table_row)
	_database_dock.configure(workbench, action_hub)


func _show_create_database() -> GDSQLOperationResult:
	_workspace.open_create_database_page(PROJECT_DATA_ROOT)
	var result := GDSQLOperationResult.new()
	result.value = _workspace
	return result


func _create_database(
		database_name: StringName,
		data_root: String,
		storage_backend_id: StringName,
) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	var database_result := GDSQLDatabase.open(database_name, data_root)
	var loaded_existing := database_result.is_successful()
	if not loaded_existing:
		database_result = GDSQLDatabase.create(database_name, data_root)
		result.diagnostics.merge(database_result.diagnostics)
	if database_result.is_successful():
		if loaded_existing:
			result.add_diagnostic(
				GDSQLQueryDiagnostic.new(
					&"GDSQL_EDITOR_DATABASE_LOADED",
					"Loaded existing database '%s' from '%s'." \
							% [database_name, data_root],
					GDSQLQueryDiagnostic.Severity.INFO,
				),
			)
		else:
			_scan_project_filesystem()
		var discovered := workbench.discover_root(data_root, &"project")
		result.diagnostics.merge(discovered.diagnostics)
		if discovered.is_successful():
			var registration_name := _find_registration(database_name, data_root)
			if registration_name != &"":
				var selected_backend := workbench.set_storage_backend(
					registration_name,
					storage_backend_id,
				)
				result.diagnostics.merge(selected_backend.diagnostics)
				var opened := _open_registration(registration_name, false)
				result.diagnostics.merge(opened.diagnostics)
				if opened.is_successful():
					_workspace.close_database_create()
	result.value = database_result.get_value()
	_refresh_surfaces()
	_record_result(
		"Load database" if loaded_existing else "Create database",
		result,
	)
	return result


func _show_create_table() -> GDSQLOperationResult:
	if workbench.active_session == null:
		return _error(
			&"GDSQL_WORKBENCH_DATABASE_REQUIRED",
			"Open a database before creating a table.",
		)
	_workspace.begin_table_draft()
	var result := GDSQLOperationResult.new()
	result.value = _workspace
	return result


func _save_database(
		registration_name: StringName,
		database_name: StringName,
		new_tables: Array[GDSQLTableDefinition],
		table_changes: Array[GDSQLEditorTableChange],
) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	var durable_catalog_changed := false
	if workbench.active_session == null \
			or workbench.active_session.registration.name != registration_name:
		var opened := _open_registration(registration_name, false)
		result.diagnostics.merge(opened.diagnostics)
	if result.is_successful():
		var database := workbench.active_session.database
		if database.database_name != database_name:
			var renamed := database.rename(database_name)
			result.diagnostics.merge(renamed.diagnostics)
			if renamed.is_successful():
				durable_catalog_changed = true
				var registration_update := workbench.update_database_name(
					registration_name,
					database_name,
				)
				result.diagnostics.merge(registration_update.diagnostics)
	for definition in new_tables:
		if not result.is_successful():
			break
		var created := workbench.active_session.database.create_table(
			definition,
		)
		result.diagnostics.merge(created.diagnostics)
		if created.is_successful():
			durable_catalog_changed = true
	for table_change in table_changes:
		if not result.is_successful():
			break
		var preview := workbench.active_session.database.preview_alter_table(
			table_change.table_name,
			table_change.alterations,
		)
		result.diagnostics.merge(preview.diagnostics)
		if not preview.is_successful():
			break
		var plan := preview.get_value() as GDSQLCatalogChangePlan
		var applied := workbench.active_session.database.apply_change_plan(plan)
		result.diagnostics.merge(applied.diagnostics)
		if applied.is_successful():
			durable_catalog_changed = true
	if result.is_successful():
		if durable_catalog_changed:
			_scan_project_filesystem()
		var refreshed := workbench.refresh_inspections()
		result.diagnostics.merge(refreshed.diagnostics)
		workbench.active_session.refresh_catalog()
	result.value = workbench.active_session.database \
	if workbench.active_session != null else null
	_refresh_surfaces()
	if result.is_successful():
		_workspace.accept_database_saved(
			registration_name,
			workbench.get_inspection(registration_name),
			workbench.active_session,
		)
	_record_result("Save database changes", result)
	return result


func _remove_registration(registration_name: StringName) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if workbench.active_session == null \
			or workbench.active_session.registration.name != registration_name:
		var opened := _open_registration(registration_name, false)
		result.diagnostics.merge(opened.diagnostics)
	if result.is_successful():
		var unregistered := workbench.active_session.database.unregister()
		result.diagnostics.merge(unregistered.diagnostics)
	if result.is_successful():
		var removed := workbench.remove_registration(registration_name)
		result.diagnostics.merge(removed.diagnostics)
	if result.is_successful():
		_scan_project_filesystem()
		_workspace.close_registration(registration_name)
	_refresh_surfaces()
	_record_result("Remove database", result)
	return result


func _refresh_database_document(
		registration_name: StringName,
) -> GDSQLOperationResult:
	var result := _ensure_active_registration(registration_name)
	if result.is_successful():
		var inspections := workbench.refresh_inspections()
		result.diagnostics.merge(inspections.diagnostics)
	if result.is_successful():
		var catalog := workbench.active_session.refresh_catalog()
		result.diagnostics.merge(catalog.diagnostics)
	if result.is_successful():
		_workspace.accept_database_saved(
			registration_name,
			workbench.get_inspection(registration_name),
			workbench.active_session,
		)
		_database_dock.render()
	result.value = workbench.active_session
	_record_result("Refresh database", result)
	return result


func _load_table_rows(
		registration_name: StringName,
		table_name: StringName,
		record_logs: bool = true,
) -> GDSQLQueryResult:
	var activation := _ensure_active_registration(registration_name)
	if not activation.is_successful():
		var failed := GDSQLQueryResult.new()
		failed.diagnostics.merge(activation.diagnostics)
		if record_logs:
			_record_result("Load table rows", failed)
		return failed
	var selected := workbench.active_session.select_table(table_name)
	if not selected.is_successful():
		var failed := GDSQLQueryResult.new()
		failed.diagnostics.merge(selected.diagnostics)
		if record_logs:
			_record_result("Load table rows", failed)
		return failed
	var result := workbench.active_session.load_rows(100)
	_workspace.present_table_rows(registration_name, table_name, result)
	if record_logs:
		_record_result("Load table rows", result)
	return result


func _insert_table_row(
		registration_name: StringName,
		table_name: StringName,
		values: Dictionary,
) -> GDSQLOperationResult:
	var result := _ensure_active_registration(registration_name)
	if result.is_successful():
		var inserted := workbench.active_session.database.insert(table_name, values)
		result.diagnostics.merge(inserted.diagnostics)
		result.value = inserted
	_complete_row_mutation(registration_name, table_name, result)
	_record_result("Insert table row", result)
	return result


func _update_table_row(
		registration_name: StringName,
		table_name: StringName,
		original_primary_key: Variant,
		values: Dictionary,
) -> GDSQLOperationResult:
	var result := _ensure_active_registration(registration_name)
	if not result.is_successful():
		_record_result("Update table row", result)
		return result
	var table := workbench.active_session.database.context.catalog.get_table(
		workbench.active_session.database.database_name,
		table_name,
	)
	if table == null:
		var missing := _error(
			&"GDSQL_EDITOR_TABLE_NOT_FOUND",
			"Table '%s' was not found." % table_name,
		)
		_record_result("Update table row", missing)
		return missing
	var builder := workbench.active_session.database.table(table_name).update()
	for column_name in values:
		var column := table.get_column(StringName(column_name))
		if column == null \
				or column.name == table.primary_key \
				or column.generation != GDSQLColumnDefinition.Generation.NONE:
			continue
		builder.set_value(StringName(column_name), values[column_name])
	var updated := workbench.active_session.database.execute(
		builder.where(
			GDSQLExpr.column(table.primary_key).equals(original_primary_key),
		).build(),
	)
	result.diagnostics.merge(updated.diagnostics)
	result.value = updated
	_complete_row_mutation(registration_name, table_name, result)
	_record_result("Update table row", result)
	return result


func _delete_table_row(
		registration_name: StringName,
		table_name: StringName,
		primary_key: Variant,
) -> GDSQLOperationResult:
	var result := _ensure_active_registration(registration_name)
	if result.is_successful():
		var table := workbench.active_session.database.context.catalog.get_table(
			workbench.active_session.database.database_name,
			table_name,
		)
		if table == null:
			var missing := _error(
				&"GDSQL_EDITOR_TABLE_NOT_FOUND",
				"Table '%s' was not found." % table_name,
			)
			_record_result("Delete table row", missing)
			return missing
		var deleted := workbench.active_session.database.execute(
			workbench.active_session.database.table(table_name) \
					.delete() \
					.where(
						GDSQLExpr.column(table.primary_key).equals(primary_key),
					) \
					.build(),
		)
		result.diagnostics.merge(deleted.diagnostics)
		result.value = deleted
	_complete_row_mutation(registration_name, table_name, result)
	_record_result("Delete table row", result)
	return result


func _complete_row_mutation(
		registration_name: StringName,
		table_name: StringName,
		result: GDSQLOperationResult,
) -> void:
	if not result.is_successful():
		return
	var refreshed := workbench.refresh_inspections()
	result.diagnostics.merge(refreshed.diagnostics)
	workbench.active_session.refresh_catalog()
	_refresh_surfaces()
	_load_table_rows(registration_name, table_name, false)


func _ensure_active_registration(
		registration_name: StringName,
) -> GDSQLOperationResult:
	if workbench.active_session != null \
			and workbench.active_session.registration.name == registration_name:
		var result := GDSQLOperationResult.new()
		result.value = workbench.active_session
		return result
	return _open_registration(registration_name, false)


func _drop_table(registration_name: StringName, table_name: StringName) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if workbench.active_session == null \
			or workbench.active_session.registration.name != registration_name:
		var opened := _open_registration(registration_name, false)
		result.diagnostics.merge(opened.diagnostics)
	if result.is_successful():
		var dropped := workbench.active_session.database.drop_table(table_name)
		result.diagnostics.merge(dropped.diagnostics)
	if result.is_successful():
		_scan_project_filesystem()
		workbench.active_session.refresh_catalog()
		workbench.active_session.selected_table = null
		var refreshed := workbench.refresh_inspections()
		result.diagnostics.merge(refreshed.diagnostics)
		_workspace.close_table(registration_name, table_name)
	_refresh_surfaces()
	if result.is_successful() and workbench.active_session != null:
		_workspace.show_database(
			workbench.get_inspection(registration_name),
			workbench.active_session,
		)
	_record_result("Delete table", result)
	return result


func _discover_project() -> GDSQLOperationResult:
	var result := workbench.discover_root(PROJECT_DATA_ROOT, &"project")
	_refresh_surfaces()
	_record_result("Discover project", result)
	return result


func _refresh_databases() -> GDSQLOperationResult:
	var result := workbench.discover_root(PROJECT_DATA_ROOT, &"project")
	_refresh_surfaces()
	_record_result("Refresh databases", result)
	return result


func _open_registration(
		registration_name: StringName,
		record_logs: bool = true,
) -> GDSQLOperationResult:
	var result := workbench.select_registration(registration_name)
	if result.is_successful():
		_workspace.show_database(
			workbench.get_inspection(registration_name),
			workbench.active_session,
		)
		_database_dock.render()
	if record_logs:
		_record_result("Open database", result)
	return result


func _select_table(registration_name: StringName, table_name: StringName) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if workbench.active_session == null \
			or workbench.active_session.registration.name != registration_name:
		var opened := _open_registration(registration_name, false)
		result.diagnostics.merge(opened.diagnostics)
	if result.is_successful():
		var selected := workbench.active_session.select_table(table_name)
		result.diagnostics.merge(selected.diagnostics)
		result.value = selected.get_value()
	if result.is_successful():
		_workspace.show_table(workbench.get_inspection(registration_name), workbench.active_session)
	_record_result("Select table", result)
	return result


func _show_welcome() -> GDSQLOperationResult:
	_workspace.show_welcome()
	var result := GDSQLOperationResult.new()
	result.value = _workspace
	return result


func _find_registration(database_name: StringName, data_root: String) -> StringName:
	for registration in workbench.get_registrations():
		if registration.database_name == database_name \
				and registration.data_root == data_root:
			return registration.name
	return &""


func _refresh_surfaces() -> void:
	if is_instance_valid(_database_dock):
		_database_dock.render()
	if is_instance_valid(_workspace) and workbench.active_session != null:
		var registration_name := workbench.active_session.registration.name
		_workspace.refresh_database(
			workbench.get_inspection(registration_name),
			workbench.active_session,
		)
	elif is_instance_valid(_workspace) \
			and _workspace.get_active_registration() != &"" \
			and workbench.get_registration(_workspace.get_active_registration()) == null:
		_workspace.show_welcome()


func _scan_project_filesystem() -> void:
	if _request_filesystem_scan.is_valid():
		_request_filesystem_scan.call()


func _record_result(action_label: String, result: GDSQLOperationResult) -> void:
	if is_instance_valid(_logs_panel):
		_logs_panel.append_result(action_label, result)


func _error(code: StringName, message: String) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
