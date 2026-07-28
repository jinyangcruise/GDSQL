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
var _activity_panel: GDSQLActivityPanel
var _workspace_loaded := false


func _init(
		workspace: GDSQLWorkspace,
		database_dock: GDSQLDatabaseDock,
		activity_panel: GDSQLActivityPanel,
) -> void:
	_workspace = workspace
	_database_dock = database_dock
	_activity_panel = activity_panel
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
	if loaded.is_successful() \
			and FileAccess.file_exists(
				PROJECT_DATA_ROOT.path_join("databases.cfg"),
			):
		var discovered := workbench.discover_root(
			PROJECT_DATA_ROOT,
			&"project",
		)
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
			and _workspace.database_create_submitted.is_connected(
				_create_database,
			):
		_workspace.database_create_submitted.disconnect(_create_database)
	_workspace = null
	_database_dock = null
	_activity_panel = null
	action_hub = null
	workbench = null


func _create_workbench() -> void:
	var store := GDSQLConfigFileDatabaseRegistryStore.new()
	var registry := GDSQLDatabaseRegistry.new(store)
	workbench = GDSQLWorkbench.new(
		registry,
		GDSQLConfigFileDatabaseExplorer.new(),
	)


func _create_actions() -> void:
	action_hub = GDSQLEditorActionHub.new()
	var handlers: Dictionary[StringName, Callable] = {
		GDSQLEditorActionIds.CREATE_DATABASE: _show_create_database,
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
	_database_dock.configure(workbench, action_hub)


func _show_create_database() -> GDSQLOperationResult:
	_workspace.open_create_database_dialog(PROJECT_DATA_ROOT)
	var result := GDSQLOperationResult.new()
	result.value = _workspace
	return result


func _create_database(
		database_name: StringName,
		data_root: String,
) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	var created := GDSQLDatabase.create(database_name, data_root)
	result.diagnostics.merge(created.diagnostics)
	if created.is_successful():
		var discovered := workbench.discover_root(data_root, &"project")
		result.diagnostics.merge(discovered.diagnostics)
		if discovered.is_successful():
			var registration_name := _find_registration(
				database_name,
				data_root,
			)
			if registration_name != &"":
				var opened := _open_registration(registration_name, false)
				result.diagnostics.merge(opened.diagnostics)
	result.value = created.get_value()
	_refresh_surfaces()
	_record_result("Create database", result)
	return result


func _discover_project() -> GDSQLOperationResult:
	var result := workbench.discover_root(PROJECT_DATA_ROOT, &"project")
	_refresh_surfaces()
	_record_result("Discover project", result)
	return result


func _refresh_databases() -> GDSQLOperationResult:
	var result := workbench.refresh_inspections()
	_refresh_surfaces()
	_record_result("Refresh databases", result)
	return result


func _open_registration(
		registration_name: StringName,
		record_activity: bool = true,
) -> GDSQLOperationResult:
	var result := workbench.select_registration(registration_name)
	if result.is_successful():
		_workspace.show_database(
			workbench.get_inspection(registration_name),
			workbench.active_session,
		)
	if record_activity:
		_record_result("Open database", result)
	return result


func _select_table(
		registration_name: StringName,
		table_name: StringName,
) -> GDSQLOperationResult:
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
		_workspace.show_database(
			workbench.get_inspection(registration_name),
			workbench.active_session,
		)
	_record_result("Select table", result)
	return result


func _show_welcome() -> GDSQLOperationResult:
	_workspace.show_welcome()
	var result := GDSQLOperationResult.new()
	result.value = _workspace
	return result


func _find_registration(
		database_name: StringName,
		data_root: String,
) -> StringName:
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
		_workspace.show_database(
			workbench.get_inspection(registration_name),
			workbench.active_session,
		)


func _record_result(
		action_label: String,
		result: GDSQLOperationResult,
) -> void:
	if is_instance_valid(_activity_panel):
		_activity_panel.append_result(action_label, result)


func _error(code: StringName, message: String) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
