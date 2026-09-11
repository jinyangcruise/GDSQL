@tool
extends MarginContainer
## Actionable project setup status shown at the workbench root.

const SETTINGS_PATH := "res://.gdsql/settings.cfg"
const RUNTIME_AUTOLOAD_SETTING := "autoload/GDSQLRuntime"
const RUNTIME_NODE_PATH := "res://addons/gdsql/runtime/gdsql_runtime_node.tscn"

var _action_hub: GDSQLEditorActionHub
var _workbench: GDSQLWorkbench
var _setup_report: GDSQLDirectSetupReport

@onready var _create_database_button: GDSQLEditorActionButton = %CreateDatabase
@onready var _refresh_button: GDSQLEditorActionButton = %RefreshDatabases
@onready var _save_slots_button: GDSQLEditorActionButton = %ManageSaveSlots
@onready var _database_list: ItemList = %DatabaseList
@onready var _open_database: Button = %OpenDatabase
@onready var _next_action_button: Button = %NextAction


func _ready() -> void:
	_database_list.item_selected.connect(_on_database_selected)
	_database_list.item_activated.connect(_open_database_at)
	_open_database.pressed.connect(_open_selected_database)
	_next_action_button.pressed.connect(_run_next_action)
	if not _is_scene_preview():
		refresh_status()


func configure(action_hub: GDSQLEditorActionHub, workbench: GDSQLWorkbench) -> void:
	_action_hub = action_hub
	_workbench = workbench
	_create_database_button.configure_action(action_hub, GDSQLEditorActionIds.CREATE_DATABASE)
	_refresh_button.configure_action(action_hub, GDSQLEditorActionIds.REFRESH_DATABASES)
	_save_slots_button.configure_action(action_hub, GDSQLEditorActionIds.SHOW_SAVE_SLOTS)
	refresh_status()


func refresh_status() -> void:
	if not is_node_ready() or _is_scene_preview():
		return
	var registrations: Array[GDSQLDatabaseRegistration] = []
	var inspections: Array[GDSQLDatabaseInspection] = []
	var snapshot := GDSQLDatabaseRegistrySnapshot.new()
	if _workbench != null:
		registrations = _workbench.get_registrations()
		inspections = _workbench.get_inspections()
		snapshot = _workbench.snapshot
	registrations.sort_custom(
		func(left: GDSQLDatabaseRegistration, right: GDSQLDatabaseRegistration) -> bool:
			return String(left.database_name).naturalnocasecmp_to(String(right.database_name)) < 0,
	)
	var table_count := 0
	var row_count := 0
	var model_count := _count_model_scripts()
	_setup_report = GDSQLDirectSetupInspector.inspect_editor(
		snapshot,
		inspections,
		model_count,
		_is_runtime_adapter_configured(),
	)
	for inspection in inspections:
		table_count += inspection.tables.size()
		for table in inspection.tables:
			row_count += table.row_count
	%Summary.text = (
			"No project databases detected. Create an authored content database to begin."
			if registrations.is_empty()
			else "%d database(s) · %d table(s) · %d stored row(s)" % [
				registrations.size(),
				table_count,
				row_count,
			]
	)
	var statuses: Array[Label] = [
		%DatabaseStepStatus,
		%TableStepStatus,
		%RowStepStatus,
		%RoleStepStatus,
		%ModelStepStatus,
		%RuntimeStepStatus,
	]
	var detail_labels: Array[Label] = [
		%DatabaseStepDetail,
		%TableStepDetail,
		%RowStepDetail,
		%RoleStepDetail,
		%ModelStepDetail,
		%RuntimeStepDetail,
	]
	var next_check := _setup_report.get_next_incomplete()
	for index in _setup_report.checks.size():
		var check := _setup_report.checks[index]
		_set_step_state(
			statuses[index],
			detail_labels[index],
			check.complete,
			check == next_check,
			check.detail,
		)
	_populate_databases(registrations, inspections)
	_refresh_profile_status(_setup_report, snapshot.role_bindings.size())
	_refresh_next_action(next_check)


func _populate_databases(
		registrations: Array[GDSQLDatabaseRegistration],
		inspections: Array[GDSQLDatabaseInspection],
) -> void:
	_database_list.clear()
	for registration in registrations:
		var inspection := _inspection_for(registration.name, inspections)
		var tables := inspection.tables.size() if inspection != null else 0
		var rows := 0
		if inspection != null:
			for table in inspection.tables:
				rows += table.row_count
		var index := _database_list.add_item(
			"%s  —  %d table(s), %d row(s)\n%s" % [
				registration.database_name,
				tables,
				rows,
				registration.data_root,
			],
		)
		_database_list.set_item_metadata(index, registration.name)
	%NoDatabases.visible = registrations.is_empty()
	_database_list.visible = not registrations.is_empty()
	if not registrations.is_empty():
		_database_list.select(0)
	_open_database.disabled = registrations.is_empty()


func _inspection_for(
		registration_name: StringName,
		inspections: Array[GDSQLDatabaseInspection],
) -> GDSQLDatabaseInspection:
	for inspection in inspections:
		if inspection.registration != null \
				and inspection.registration.name == registration_name:
			return inspection
	return null


func _set_step_state(
		status: Label,
		detail: Label,
		complete: bool,
		is_next: bool,
		message: String,
) -> void:
	status.text = "✓" if complete else ("→" if is_next else "○")
	status.modulate = Color(0.42, 0.82, 0.55) if complete else Color(0.65, 0.7, 0.78)
	detail.text = message
	detail.modulate = Color.WHITE if complete or is_next else Color(0.7, 0.72, 0.76)


func _refresh_profile_status(
		report: GDSQLDirectSetupReport,
		role_count: int,
) -> void:
	var direct_ready := report.is_ready()
	%DirectProfileStatus.text = "READY" if direct_ready else "SETUP REQUIRED"
	%DirectProfileStatus.modulate = (
			Color(0.42, 0.82, 0.55) if direct_ready else Color(1.0, 0.72, 0.32)
	)
	%DirectProfileDetail.text = (
			"Content definitions and the active save are ready. %d total role binding(s)."
			% role_count
			if direct_ready
			else report.get_next_incomplete().detail
	)
	%ManagedProfileStatus.text = "PLANNED"
	%ManagedProfileDetail.text = (
			"Effective-content cache, package overlays, and mod orchestration are not implemented yet."
	)


func _refresh_next_action(check: GDSQLDirectSetupCheck) -> void:
	if check == null:
		%NextStep.text = "Project data setup is complete."
		_next_action_button.visible = false
		return
	%NextStep.text = "Next: %s" % check.detail
	_next_action_button.visible = check.next_action != GDSQLDirectSetupCheck.ACTION_NONE
	match check.next_action:
		GDSQLDirectSetupCheck.ACTION_CREATE_DATABASE:
			_next_action_button.text = "Set Up Content"
		GDSQLDirectSetupCheck.ACTION_OPEN_CONTENT_DATABASE:
			_next_action_button.text = "Open Content"
		GDSQLDirectSetupCheck.ACTION_OPEN_CONTENT_TABLE:
			_next_action_button.text = "Open Content Table"
		GDSQLDirectSetupCheck.ACTION_MANAGE_SAVE_SLOTS:
			_next_action_button.text = "Manage Saves"
		GDSQLDirectSetupCheck.ACTION_INSTALL_RUNTIME:
			_next_action_button.text = "Install Runtime"


func _run_next_action() -> void:
	if _action_hub == null or _setup_report == null:
		return
	var check := _setup_report.get_next_incomplete()
	if check == null:
		return
	match check.next_action:
		GDSQLDirectSetupCheck.ACTION_CREATE_DATABASE:
			_action_hub.invoke(GDSQLEditorActionIds.CREATE_DATABASE, [], true)
		GDSQLDirectSetupCheck.ACTION_OPEN_CONTENT_DATABASE:
			_open_content_database()
		GDSQLDirectSetupCheck.ACTION_OPEN_CONTENT_TABLE:
			_open_content_table()
		GDSQLDirectSetupCheck.ACTION_MANAGE_SAVE_SLOTS:
			_action_hub.invoke(GDSQLEditorActionIds.SHOW_SAVE_SLOTS, [], true)
		GDSQLDirectSetupCheck.ACTION_INSTALL_RUNTIME:
			_action_hub.invoke(GDSQLEditorActionIds.INSTALL_RUNTIME_ADAPTER)
			refresh_status()


func _open_content_database() -> void:
	var registration := _role_registration(GDSQLDatabaseRegistry.CONTENT_ROLE)
	if registration == null:
		_action_hub.invoke(GDSQLEditorActionIds.CREATE_DATABASE, [], true)
		return
	_action_hub.invoke(
		GDSQLEditorActionIds.OPEN_REGISTRATION,
		[registration.name],
		true,
	)


func _open_content_table() -> void:
	var registration := _role_registration(GDSQLDatabaseRegistry.CONTENT_ROLE)
	if registration == null or _workbench == null:
		_open_content_database()
		return
	var inspection := _workbench.get_inspection(registration.name)
	if inspection == null or inspection.tables.is_empty():
		_open_content_database()
		return
	var table := inspection.tables[0]
	for candidate in inspection.tables:
		if candidate.schema_exists and candidate.storage_exists:
			table = candidate
			break
	_action_hub.invoke(
		GDSQLEditorActionIds.SELECT_TABLE,
		[registration.name, table.name],
		true,
	)


func _role_registration(role: StringName) -> GDSQLDatabaseRegistration:
	if _workbench == null:
		return null
	var selected_name := &""
	for binding in _workbench.snapshot.role_bindings:
		if binding.role == role:
			selected_name = binding.registration_name
	return _workbench.get_registration(selected_name)


func _is_runtime_adapter_configured() -> bool:
	var configured_path := String(ProjectSettings.get_setting(RUNTIME_AUTOLOAD_SETTING, ""))
	return configured_path.trim_prefix("*") == RUNTIME_NODE_PATH


func _count_model_scripts() -> int:
	var root := GDSQLModelSourceGenerator.DEFAULT_ROOT
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		root = String(config.get_value("models", "root", root))
	var directory := DirAccess.open(root)
	if directory == null:
		return 0
	var count := 0
	for file_name in directory.get_files():
		if file_name.get_extension() == "gd":
			count += 1
	return count


func _on_database_selected(_index: int) -> void:
	_open_database.disabled = false


func _open_selected_database() -> void:
	var selected := _database_list.get_selected_items()
	if not selected.is_empty():
		_open_database_at(selected[0])


func _open_database_at(index: int) -> void:
	if _action_hub == null or index < 0 or index >= _database_list.item_count:
		return
	_action_hub.invoke(
		GDSQLEditorActionIds.OPEN_REGISTRATION,
		[_database_list.get_item_metadata(index)],
		true,
	)


func _is_scene_preview() -> bool:
	if not Engine.is_editor_hint():
		return false
	var edited_scene_root := EditorInterface.get_edited_scene_root()
	return edited_scene_root == self \
			or (edited_scene_root != null and edited_scene_root.is_ancestor_of(self))
