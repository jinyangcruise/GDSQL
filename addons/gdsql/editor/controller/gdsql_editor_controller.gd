@tool
class_name GDSQLEditorController
extends RefCounted
## Coordinates GDSQL editor actions, workbench state, and editor surfaces.
##
## Godot plugin lifecycle and control placement remain in the EditorPlugin.

const PROJECT_DATA_ROOT := "res://data"
const SAVE_SLOTS_ROOT := "user://gdsql/saves"
const RUNTIME_AUTOLOAD_SETTING := "autoload/GDSQLRuntime"
const RUNTIME_NODE_PATH := "res://addons/gdsql/runtime/gdsql_runtime_node.tscn"
const TABLE_COUNT_ALIAS := &"row_count"

var action_hub: GDSQLEditorActionHub
var workbench: GDSQLWorkbench
var _workspace: GDSQLWorkspace
var _database_dock: GDSQLDatabaseDock
var _logs_panel: GDSQLLogsPanel
var _workspace_loaded := false
var _request_filesystem_scan: Callable
var _mutation_histories: Dictionary[String, GDSQLEditorMutationHistory] = { }


static func _registration_prefix_for_root(
		database_name: StringName,
		data_root: String,
) -> StringName:
	var normalized_root := data_root.strip_edges().simplify_path()
	if normalized_root == PROJECT_DATA_ROOT:
		return &"project"
	var root_name := normalized_root.trim_suffix("/").get_file()
	if root_name.is_empty() or root_name in [".", ".."]:
		return database_name
	return StringName(root_name)


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
			and _workspace.database_destroy_submitted.is_connected(_destroy_database):
		_workspace.database_destroy_submitted.disconnect(_destroy_database)
	if is_instance_valid(_workspace) \
			and _workspace.table_rows_requested.is_connected(_load_table_rows):
		_workspace.table_rows_requested.disconnect(_load_table_rows)
	if is_instance_valid(_workspace) \
			and _workspace.table_reference_rows_requested.is_connected(
				_load_table_reference_rows,
			):
		_workspace.table_reference_rows_requested.disconnect(_load_table_reference_rows)
	if is_instance_valid(_workspace) \
			and _workspace.table_row_insert_requested.is_connected(_insert_table_row):
		_workspace.table_row_insert_requested.disconnect(_insert_table_row)
	if is_instance_valid(_workspace) \
			and _workspace.table_rows_update_requested.is_connected(_update_table_rows):
		_workspace.table_rows_update_requested.disconnect(_update_table_rows)
	if is_instance_valid(_workspace) \
			and _workspace.table_rows_delete_requested.is_connected(_delete_table_rows):
		_workspace.table_rows_delete_requested.disconnect(_delete_table_rows)
	if is_instance_valid(_workspace) \
			and _workspace.table_undo_requested.is_connected(_undo_table_mutation):
		_workspace.table_undo_requested.disconnect(_undo_table_mutation)
	if is_instance_valid(_workspace) \
			and _workspace.table_redo_requested.is_connected(_redo_table_mutation):
		_workspace.table_redo_requested.disconnect(_redo_table_mutation)
	if is_instance_valid(_workspace) \
			and _workspace.query_graph_submitted.is_connected(_execute_query_graph):
		_workspace.query_graph_submitted.disconnect(_execute_query_graph)
	if is_instance_valid(_workspace) \
			and _workspace.query_result_row_insert_requested.is_connected(
				_insert_query_result_row,
			):
		_workspace.query_result_row_insert_requested.disconnect(
			_insert_query_result_row,
		)
	if is_instance_valid(_workspace) \
			and _workspace.query_result_row_update_requested.is_connected(
				_update_query_result_row,
			):
		_workspace.query_result_row_update_requested.disconnect(
			_update_query_result_row,
		)
	if is_instance_valid(_workspace) \
			and _workspace.query_result_row_delete_requested.is_connected(
				_delete_query_result_row,
			):
		_workspace.query_result_row_delete_requested.disconnect(
			_delete_query_result_row,
		)
	_workspace = null
	_database_dock = null
	_mutation_histories.clear()
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
		GDSQLEditorActionIds.SHOW_SAVE_SLOTS: _show_save_slots,
		GDSQLEditorActionIds.SHOW_MANAGED_CONTENT: _show_managed_content,
		GDSQLEditorActionIds.CREATE_SAVE_SLOT: _show_create_save_slot,
		GDSQLEditorActionIds.SELECT_SAVE_SLOT: _select_save_slot,
		GDSQLEditorActionIds.DELETE_SAVE_SLOT: _delete_save_slot,
		GDSQLEditorActionIds.INSTALL_RUNTIME_ADAPTER: _install_runtime_adapter,
	}
	var registered := GDSQLEditorActionRegistrar.new() \
			.register_global_actions(action_hub, handlers)
	assert(registered.is_successful())


func _configure_surfaces() -> void:
	_workspace.configure(action_hub, workbench)
	_workspace.database_create_submitted.connect(_create_database)
	_workspace.database_save_submitted.connect(_save_database)
	_workspace.database_refresh_submitted.connect(_refresh_database_document)
	_workspace.database_destroy_submitted.connect(_destroy_database)
	_workspace.table_rows_requested.connect(_load_table_rows)
	_workspace.table_reference_rows_requested.connect(_load_table_reference_rows)
	_workspace.table_row_insert_requested.connect(_insert_table_row)
	_workspace.table_rows_update_requested.connect(_update_table_rows)
	_workspace.table_rows_delete_requested.connect(_delete_table_rows)
	_workspace.table_undo_requested.connect(_undo_table_mutation)
	_workspace.table_redo_requested.connect(_redo_table_mutation)
	_workspace.query_graph_submitted.connect(_execute_query_graph)
	_workspace.query_result_row_insert_requested.connect(_insert_query_result_row)
	_workspace.query_result_row_update_requested.connect(_update_query_result_row)
	_workspace.query_result_row_delete_requested.connect(_delete_query_result_row)
	_database_dock.configure(workbench, action_hub)


func _show_create_database() -> GDSQLOperationResult:
	_workspace.open_create_database_page(PROJECT_DATA_ROOT)
	var result := GDSQLOperationResult.new()
	result.value = _workspace
	return result


func _show_create_save_slot() -> GDSQLOperationResult:
	_workspace.open_create_save_slot_page()
	var result := GDSQLOperationResult.new()
	result.value = _workspace
	return result


func _install_runtime_adapter() -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	var current_path := String(
		ProjectSettings.get_setting(RUNTIME_AUTOLOAD_SETTING, ""),
	).trim_prefix("*")
	if not current_path.is_empty() and current_path != RUNTIME_NODE_PATH:
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_RUNTIME_AUTOLOAD_NAME_IN_USE",
				"The GDSQLRuntime autoload name is already used by '%s'." % current_path,
			),
		)
		_record_result("Install runtime adapter", result)
		return result
	ProjectSettings.set_setting(
		RUNTIME_AUTOLOAD_SETTING,
		"*%s" % RUNTIME_NODE_PATH,
	)
	var error := ProjectSettings.save()
	if error != OK:
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_RUNTIME_AUTOLOAD_SAVE_FAILED",
				"Could not save the GDSQLRuntime autoload setting: %s." % error_string(error),
			),
		)
	else:
		result.value = true
		_refresh_surfaces()
	_record_result("Install runtime adapter", result)
	return result


func _create_database(
		database_name: StringName,
		data_root: String,
		storage_backend_id: StringName,
		database_role: StringName,
		package_root: String,
) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if not package_root.is_empty():
		var scaffolded := GDSQLConfigFileContentPackageScaffolder.new().scaffold(
			package_root,
			GDSQLContentPackageManifest.new(
				&"base.game",
				"Base Game",
				"1.0.0",
				GDSQLContentPackageKind.Kind.BASE_GAME,
				0,
				data_root.get_file(),
				"assets",
			),
		)
		result.diagnostics.merge(scaffolded.diagnostics)
		if not scaffolded.is_successful():
			_record_result("Scaffold base content package", result)
			return result
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
		var discovered := workbench.discover_root(
			data_root,
			_registration_prefix_for_root(database_name, data_root),
		)
		result.diagnostics.merge(discovered.diagnostics)
		if discovered.is_successful():
			var registration_name := _find_registration(database_name, data_root)
			if registration_name != &"":
				var selected_backend := workbench.set_storage_backend(
					registration_name,
					storage_backend_id,
				)
				result.diagnostics.merge(selected_backend.diagnostics)
				if result.is_successful() and database_role != &"":
					var bound_role := workbench.bind_role(database_role, registration_name)
					result.diagnostics.merge(bound_role.diagnostics)
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
		_clear_registration_histories(registration_name)
		_workspace.close_registration(registration_name)
	_refresh_surfaces()
	_record_result("Remove database", result)
	return result


func _destroy_database(registration_name: StringName) -> GDSQLOperationResult:
	var result := _ensure_active_registration(registration_name)
	if result.is_successful():
		var dropped := workbench.active_session.database.drop()
		result.diagnostics.merge(dropped.diagnostics)
	if result.is_successful():
		var removed := workbench.remove_registration(registration_name)
		result.diagnostics.merge(removed.diagnostics)
	if result.is_successful():
		_scan_project_filesystem()
		_clear_registration_histories(registration_name)
		_workspace.close_registration(registration_name)
		result.value = true
	_refresh_surfaces()
	_record_result("Destroy database files", result)
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
		query: GDSQLSelectQuerySpec,
		count_query: GDSQLSelectQuerySpec,
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
	var database := workbench.active_session.database
	var result := database.execute(query)
	var total_rows := -1
	if result.is_successful() and count_query != null:
		var count_result := database.execute(count_query)
		result.diagnostics.merge(count_result.diagnostics)
		if count_result.is_successful() and not count_result.rows.is_empty():
			total_rows = int(count_result.rows[0].get_value(TABLE_COUNT_ALIAS))
	_workspace.present_table_rows(registration_name, table_name, result, total_rows)
	if record_logs:
		_record_result("Load table rows", result)
	return result


func _load_table_reference_rows(
		registration_name: StringName,
		source_table_name: StringName,
		constraint_name: StringName,
		query: GDSQLSelectQuerySpec,
) -> GDSQLQueryResult:
	var result := GDSQLQueryResult.new()
	var activation := _ensure_active_registration(registration_name)
	result.diagnostics.merge(activation.diagnostics)
	var foreign_key: GDSQLForeignKeyDefinition
	var target_table: GDSQLTableDefinition
	if result.is_successful():
		var database := workbench.active_session.database
		var source_table := database.context.catalog.get_table(
			database.database_name,
			source_table_name,
		)
		if source_table == null:
			result.add_diagnostic(
				GDSQLQueryDiagnostic.new(
					&"GDSQL_EDITOR_REFERENCE_SOURCE_NOT_FOUND",
					"Source table '%s' was not found." % source_table_name,
				),
			)
		else:
			foreign_key = source_table.get_foreign_key(constraint_name)
			if foreign_key == null:
				result.add_diagnostic(
					GDSQLQueryDiagnostic.new(
						&"GDSQL_EDITOR_FOREIGN_KEY_NOT_FOUND",
						"Foreign key '%s' was not found." % constraint_name,
					),
				)
			else:
				target_table = database.context.catalog.get_table(
					database.database_name,
					foreign_key.referenced_table,
				)
				if target_table == null:
					result.add_diagnostic(
						GDSQLQueryDiagnostic.new(
							&"GDSQL_EDITOR_REFERENCE_TARGET_NOT_FOUND",
							"Referenced table '%s' was not found." \
									% foreign_key.referenced_table,
						),
					)
				else:
					result = database.execute(query)
	_workspace.present_table_reference_rows(
		registration_name,
		source_table_name,
		foreign_key,
		target_table,
		result,
	)
	if not result.is_successful():
		_record_result("Load foreign key references", result)
	return result


func _execute_query_graph(
		document_key: StringName,
		source_node_name: StringName,
		registration_name: StringName,
		query: GDSQLQuerySpec,
) -> GDSQLQueryResult:
	var result := GDSQLQueryResult.new()
	var activation := _ensure_active_registration(registration_name)
	result.diagnostics.merge(activation.diagnostics)
	var table: GDSQLTableDefinition
	if result.is_successful():
		var executed := workbench.active_session.database.execute(query)
		executed.diagnostics.merge(result.diagnostics)
		result = executed
		if query is GDSQLSelectQuerySpec:
			var source := (query as GDSQLSelectQuerySpec).source \
					as GDSQLTableReference
			if source != null:
				table = workbench.active_session.database.context.catalog.get_table(
					source.database_name,
					source.table_name,
				)
		else:
			var refreshed := workbench.refresh_inspections()
			result.diagnostics.merge(refreshed.diagnostics)
			var catalog := workbench.active_session.refresh_catalog()
			result.diagnostics.merge(catalog.diagnostics)
			_refresh_surfaces()
	_workspace.present_query_graph_result(
		document_key,
		source_node_name,
		registration_name,
		table,
		result,
	)
	_record_result("Run query graph", result)
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
	if result.is_successful():
		_clear_table_history(registration_name, table_name)
	_complete_row_mutation(registration_name, table_name, result)
	_record_result("Insert table row", result)
	return result


func _update_table_rows(
		registration_name: StringName,
		table_name: StringName,
		updates: Array[Dictionary],
) -> GDSQLOperationResult:
	var result := _ensure_active_registration(registration_name)
	if not result.is_successful():
		_record_result("Update table rows", result)
		return result
	var database := workbench.active_session.database
	var table := database.context.catalog.get_table(database.database_name, table_name)
	if table == null:
		result = _error(
			&"GDSQL_EDITOR_TABLE_NOT_FOUND",
			"Table '%s' was not found." % table_name,
		)
	else:
		var planned := GDSQLEditorRowBatch.build_updates(table, updates)
		result.diagnostics.merge(planned.diagnostics)
		if planned.is_successful():
			var batch := planned.get_value() as GDSQLEditorRowBatch
			var executed := batch.execute(database)
			result.diagnostics.merge(executed.diagnostics)
			result.value = executed.value
			if executed.is_successful():
				var entry := batch.create_history_entry(registration_name)
				if entry != null:
					result.diagnostics.merge(
						_history_for(registration_name, table_name).record(entry).diagnostics,
					)
				else:
					_clear_table_history(registration_name, table_name)
	_complete_row_mutation(registration_name, table_name, result)
	_refresh_table_history_state(registration_name, table_name)
	_record_result("Update table rows", result)
	return result


func _undo_table_mutation(
		registration_name: StringName,
		table_name: StringName,
) -> GDSQLOperationResult:
	var result := _apply_table_history(registration_name, table_name, true)
	_record_result("Undo table row update", result)
	return result


func _redo_table_mutation(
		registration_name: StringName,
		table_name: StringName,
) -> GDSQLOperationResult:
	var result := _apply_table_history(registration_name, table_name, false)
	_record_result("Redo table row update", result)
	return result


func _apply_table_history(
		registration_name: StringName,
		table_name: StringName,
		undo: bool,
) -> GDSQLOperationResult:
	var history := _get_history(registration_name, table_name)
	var entry: GDSQLEditorMutationHistoryEntry
	if history != null:
		entry = history.get_undo_entry() if undo else history.get_redo_entry()
	if entry == null:
		return _error(
			&"GDSQL_EDITOR_MUTATION_HISTORY_EMPTY",
			"There is no row update to %s." % ("undo" if undo else "redo"),
		)
	var result := _ensure_active_registration(registration_name)
	if not result.is_successful():
		return result
	var database := workbench.active_session.database
	var table := database.context.catalog.get_table(database.database_name, table_name)
	if table == null:
		return _error(
			&"GDSQL_EDITOR_TABLE_NOT_FOUND",
			"Table '%s' was not found." % table_name,
		)
	var snapshots := entry.duplicate_before_rows() if undo else entry.duplicate_after_rows()
	var planned := GDSQLEditorRowBatch.build_updates(
		table,
		_history_updates(table, snapshots),
	)
	result.diagnostics.merge(planned.diagnostics)
	if result.is_successful():
		var executed := (planned.get_value() as GDSQLEditorRowBatch).execute(database)
		result.diagnostics.merge(executed.diagnostics)
	if result.is_successful():
		var moved := history.mark_undone(entry) if undo else history.mark_redone(entry)
		result.diagnostics.merge(moved.diagnostics)
		result.value = entry
	_complete_row_mutation(registration_name, table_name, result)
	_refresh_table_history_state(registration_name, table_name)
	if result.is_successful():
		_workspace.present_table_history_result(
			registration_name,
			table_name,
			"%s complete: %s." % ["Undo" if undo else "Redo", entry.get_summary()],
		)
	return result


func _history_updates(
		table: GDSQLTableDefinition,
		rows: Array[GDSQLRowRecord],
) -> Array[Dictionary]:
	var updates: Array[Dictionary] = []
	for row in rows:
		var values := row.values.duplicate(true)
		var identity: Variant = values.get(table.primary_key)
		values.erase(table.primary_key)
		updates.append({ "primary_key": identity, "values": values })
	return updates


func _update_row(
		registration_name: StringName,
		table_name: StringName,
		original_primary_key: Variant,
		values: Dictionary,
		query_document_key: StringName = &"",
		query_source_name: StringName = &"",
) -> GDSQLOperationResult:
	var result := _ensure_active_registration(registration_name)
	if not result.is_successful():
		return result
	var database := workbench.active_session.database
	var table := database.context.catalog.get_table(
		database.database_name,
		table_name,
	)
	if table == null:
		return _error(
			&"GDSQL_EDITOR_TABLE_NOT_FOUND",
			"Table '%s' was not found." % table_name,
		)
	var updates: Array[Dictionary] = [
		{
			"primary_key": original_primary_key,
			"values": values,
		},
	]
	var planned := GDSQLEditorRowBatch.build_updates(table, updates)
	result.diagnostics.merge(planned.diagnostics)
	if planned.is_successful():
		var executed := (planned.get_value() as GDSQLEditorRowBatch).execute(database)
		result.diagnostics.merge(executed.diagnostics)
		result.value = executed.value
	if result.is_successful():
		_clear_table_history(registration_name, table_name)
	_complete_row_mutation(
		registration_name,
		table_name,
		result,
		query_document_key,
		query_source_name,
	)
	return result


func _delete_table_rows(
		registration_name: StringName,
		table_name: StringName,
		primary_keys: Array[Variant],
) -> GDSQLOperationResult:
	var result := _ensure_active_registration(registration_name)
	if not result.is_successful():
		_record_result("Delete table rows", result)
		return result
	var database := workbench.active_session.database
	var table := database.context.catalog.get_table(database.database_name, table_name)
	if table == null:
		result = _error(
			&"GDSQL_EDITOR_TABLE_NOT_FOUND",
			"Table '%s' was not found." % table_name,
		)
	else:
		var planned := GDSQLEditorRowBatch.build_deletes(table, primary_keys)
		result.diagnostics.merge(planned.diagnostics)
		if planned.is_successful():
			var executed := (planned.get_value() as GDSQLEditorRowBatch).execute(database)
			result.diagnostics.merge(executed.diagnostics)
			result.value = executed.value
	if result.is_successful():
		_clear_table_history(registration_name, table_name)
	_complete_row_mutation(registration_name, table_name, result)
	_refresh_table_history_state(registration_name, table_name)
	_record_result("Delete table rows", result)
	return result


func _delete_row(
		registration_name: StringName,
		table_name: StringName,
		primary_key: Variant,
		query_document_key: StringName = &"",
		query_source_name: StringName = &"",
) -> GDSQLOperationResult:
	var result := _ensure_active_registration(registration_name)
	if result.is_successful():
		var database := workbench.active_session.database
		var table := workbench.active_session.database.context.catalog.get_table(
			database.database_name,
			table_name,
		)
		if table == null:
			return _error(
				&"GDSQL_EDITOR_TABLE_NOT_FOUND",
				"Table '%s' was not found." % table_name,
			)
		var primary_keys: Array[Variant] = [primary_key]
		var planned := GDSQLEditorRowBatch.build_deletes(table, primary_keys)
		result.diagnostics.merge(planned.diagnostics)
		if planned.is_successful():
			var executed := (planned.get_value() as GDSQLEditorRowBatch).execute(database)
			result.diagnostics.merge(executed.diagnostics)
			result.value = executed.value
	if result.is_successful():
		_clear_table_history(registration_name, table_name)
	_complete_row_mutation(
		registration_name,
		table_name,
		result,
		query_document_key,
		query_source_name,
	)
	return result


func _complete_row_mutation(
		registration_name: StringName,
		table_name: StringName,
		result: GDSQLOperationResult,
		query_document_key: StringName = &"",
		query_source_name: StringName = &"",
) -> void:
	if not result.is_successful():
		return
	var refreshed := workbench.refresh_inspections()
	result.diagnostics.merge(refreshed.diagnostics)
	workbench.active_session.refresh_catalog()
	_refresh_surfaces()
	if query_document_key == &"":
		_workspace.request_table_rows(registration_name, table_name)
	else:
		var query_result := _workspace.request_query_graph(
			query_document_key,
			query_source_name,
		)
		result.diagnostics.merge(query_result.diagnostics)


func _insert_query_result_row(
		document_key: StringName,
		source_node_name: StringName,
		registration_name: StringName,
		table_name: StringName,
		values: Dictionary,
) -> GDSQLOperationResult:
	var result := _ensure_active_registration(registration_name)
	if result.is_successful():
		var inserted := workbench.active_session.database.insert(table_name, values)
		result.diagnostics.merge(inserted.diagnostics)
		result.value = inserted
	if result.is_successful():
		_clear_table_history(registration_name, table_name)
	_complete_row_mutation(
		registration_name,
		table_name,
		result,
		document_key,
		source_node_name,
	)
	_record_result("Insert query result row", result)
	return result


func _update_query_result_row(
		document_key: StringName,
		source_node_name: StringName,
		registration_name: StringName,
		table_name: StringName,
		original_primary_key: Variant,
		values: Dictionary,
) -> GDSQLOperationResult:
	var result := _update_row(
		registration_name,
		table_name,
		original_primary_key,
		values,
		document_key,
		source_node_name,
	)
	_record_result("Update query result row", result)
	return result


func _delete_query_result_row(
		document_key: StringName,
		source_node_name: StringName,
		registration_name: StringName,
		table_name: StringName,
		primary_key: Variant,
) -> GDSQLOperationResult:
	var result := _delete_row(
		registration_name,
		table_name,
		primary_key,
		document_key,
		source_node_name,
	)
	_record_result("Delete query result row", result)
	return result


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
		_clear_table_history(registration_name, table_name)
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
		_workspace.show_table(
			workbench.get_inspections(),
			workbench.get_inspection(registration_name),
			workbench.active_session,
		)
		_refresh_table_history_state(registration_name, table_name)
	_record_result("Select table", result)
	return result


func _show_welcome() -> GDSQLOperationResult:
	_workspace.show_welcome()
	var result := GDSQLOperationResult.new()
	result.value = _workspace
	return result


func _show_save_slots() -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if DirAccess.open(SAVE_SLOTS_ROOT) != null:
		var discovered := workbench.discover_children(SAVE_SLOTS_ROOT)
		result.diagnostics.merge(discovered.diagnostics)
	if result.is_successful():
		_workspace.show_save_slots()
	_refresh_surfaces()
	result.value = _workspace
	_record_result("Refresh save slots", result)
	return result


func _show_managed_content() -> GDSQLOperationResult:
	_workspace.show_managed_content()
	var result := GDSQLOperationResult.new()
	result.value = _workspace
	return result


func _select_save_slot(registration_name: StringName) -> GDSQLOperationResult:
	var result := workbench.bind_role(
		GDSQLDatabaseRegistry.SAVE_ROLE,
		registration_name,
	)
	_refresh_surfaces()
	_record_result("Select save slot", result)
	return result


func _delete_save_slot(registration_name: StringName) -> GDSQLOperationResult:
	var registration := workbench.get_registration(registration_name)
	var planned := GDSQLSaveSlotDeletionPlan.build(
		registration,
		_get_role_registration(GDSQLDatabaseRegistry.SAVE_ROLE),
	)
	if not planned.is_successful():
		_record_result("Delete save slot data", planned)
		return planned
	var plan := planned.get_value() as GDSQLSaveSlotDeletionPlan
	var result := GDSQLOperationResult.new()
	var opened := _ensure_active_registration(plan.registration_name)
	result.diagnostics.merge(opened.diagnostics)
	if result.is_successful():
		var dropped := workbench.active_session.database.drop()
		result.diagnostics.merge(dropped.diagnostics)
	if result.is_successful():
		var removed := workbench.remove_registration(plan.registration_name)
		result.diagnostics.merge(removed.diagnostics)
	if result.is_successful():
		_workspace.close_registration(plan.registration_name)
		result.value = plan
	_refresh_surfaces()
	_record_result("Delete save slot data", result)
	return result


func _get_role_registration(role: StringName) -> StringName:
	for binding in workbench.snapshot.role_bindings:
		if binding.role == role:
			return binding.registration_name
	return &""


func _find_registration(database_name: StringName, data_root: String) -> StringName:
	for registration in workbench.get_registrations():
		if registration.database_name == database_name \
				and registration.data_root == data_root:
			return registration.name
	return &""


func _history_key(registration_name: StringName, table_name: StringName) -> String:
	return "%s:%s" % [registration_name, table_name]


func _history_for(
		registration_name: StringName,
		table_name: StringName,
) -> GDSQLEditorMutationHistory:
	var key := _history_key(registration_name, table_name)
	if not _mutation_histories.has(key):
		_mutation_histories[key] = GDSQLEditorMutationHistory.new()
	return _mutation_histories[key]


func _get_history(
		registration_name: StringName,
		table_name: StringName,
) -> GDSQLEditorMutationHistory:
	return _mutation_histories.get(_history_key(registration_name, table_name))


func _clear_table_history(registration_name: StringName, table_name: StringName) -> void:
	var key := _history_key(registration_name, table_name)
	var history: GDSQLEditorMutationHistory = _mutation_histories.get(key)
	if history == null:
		return
	history.clear()
	_mutation_histories.erase(key)
	_refresh_table_history_state(registration_name, table_name)


func _clear_registration_histories(registration_name: StringName) -> void:
	var prefix := "%s:" % registration_name
	for key in _mutation_histories.keys():
		var history_key := String(key)
		if history_key.begins_with(prefix):
			(_mutation_histories[history_key] as GDSQLEditorMutationHistory).clear()
			_mutation_histories.erase(history_key)


func _refresh_table_history_state(
		registration_name: StringName,
		table_name: StringName,
) -> void:
	var history := _get_history(registration_name, table_name)
	var undo_entry := history.get_undo_entry() if history != null else null
	var redo_entry := history.get_redo_entry() if history != null else null
	_workspace.set_table_history_state(
		registration_name,
		table_name,
		undo_entry.get_summary() if undo_entry != null else "",
		redo_entry.get_summary() if redo_entry != null else "",
	)


func _refresh_surfaces() -> void:
	if is_instance_valid(_database_dock):
		_database_dock.render()
	if is_instance_valid(_workspace):
		_workspace.refresh_welcome()
		_workspace.refresh_save_slots()
		_workspace.refresh_managed_content()
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
