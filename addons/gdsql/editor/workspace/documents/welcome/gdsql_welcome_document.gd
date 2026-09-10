@tool
extends MarginContainer
## Actionable project setup status shown at the workbench root.

const SETTINGS_PATH := "res://.gdsql/settings.cfg"

var _action_hub: GDSQLEditorActionHub
var _workbench: GDSQLWorkbench

@onready var _create_database_button: GDSQLEditorActionButton = %CreateDatabase
@onready var _refresh_button: GDSQLEditorActionButton = %RefreshDatabases
@onready var _save_slots_button: GDSQLEditorActionButton = %ManageSaveSlots
@onready var _database_list: ItemList = %DatabaseList
@onready var _open_database: Button = %OpenDatabase


func _ready() -> void:
	_database_list.item_selected.connect(_on_database_selected)
	_database_list.item_activated.connect(_open_database_at)
	_open_database.pressed.connect(_open_selected_database)
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
	var role_count := 0
	if _workbench != null:
		registrations = _workbench.get_registrations()
		inspections = _workbench.get_inspections()
		role_count = _workbench.snapshot.role_bindings.size()
	registrations.sort_custom(
		func(left: GDSQLDatabaseRegistration, right: GDSQLDatabaseRegistration) -> bool:
			return String(left.database_name).naturalnocasecmp_to(String(right.database_name)) < 0,
	)
	var table_count := 0
	var row_count := 0
	var model_count := _count_model_scripts()
	var direct_profile_issues := _get_direct_profile_issues()
	var direct_profile_ready := direct_profile_issues.is_empty()
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
	var completed := [
		not registrations.is_empty(),
		table_count > 0,
		row_count > 0,
		direct_profile_ready,
		model_count > 0,
	]
	var details := [
		"Database available under a registered data root." if completed[0] \
		else "Create or discover an authored content database under res://data.",
		"At least one table is ready for content." if completed[1] \
		else "Open a database, then add and save its first table.",
		"The project contains editable content rows." if completed[2] \
		else "Open a table and add its first row.",
		"Content and save roles use the recommended runtime roots." if completed[3] \
		else "Direct setup: %s." % ", ".join(direct_profile_issues),
		"%d user-owned model binding(s) found." % model_count if completed[4] \
		else "Open a table and use Model to generate its first typed binding.",
	]
	var statuses: Array[Label] = [
		%DatabaseStepStatus,
		%TableStepStatus,
		%RowStepStatus,
		%RoleStepStatus,
		%ModelStepStatus,
	]
	var detail_labels: Array[Label] = [
		%DatabaseStepDetail,
		%TableStepDetail,
		%RowStepDetail,
		%RoleStepDetail,
		%ModelStepDetail,
	]
	var next_step := completed.find(false)
	for index in completed.size():
		_set_step_state(
			statuses[index],
			detail_labels[index],
			completed[index],
			index == next_step,
			details[index],
		)
	_populate_databases(registrations, inspections)
	_refresh_profile_status(direct_profile_ready, direct_profile_issues, role_count)
	%NextStep.text = _next_step_text(next_step)


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


func _next_step_text(step: int) -> String:
	match step:
		0:
			return "Next: create the project content database."
		1:
			return "Next: open a database from the list or dock and create a table."
		2:
			return "Next: open a table and add its first content row."
		3:
			return "Next: create or bind the missing content and save databases."
		4:
			return "Next: open a table and generate its model binding."
	return "Project data setup is complete."


func _get_direct_profile_issues() -> Array[String]:
	var issues: Array[String] = []
	var content := _get_role_registration(GDSQLDatabaseRegistry.CONTENT_ROLE)
	var save := _get_role_registration(GDSQLDatabaseRegistry.SAVE_ROLE)
	if content == null:
		issues.append("content role is missing")
	elif not content.data_root.begins_with("res://"):
		issues.append("content should use a res:// source")
	if save == null:
		issues.append("save role is missing")
	elif not save.data_root.begins_with("user://"):
		issues.append("save should use a writable user:// root")
	return issues


func _get_role_registration(role: StringName) -> GDSQLDatabaseRegistration:
	if _workbench == null:
		return null
	for binding in _workbench.snapshot.role_bindings:
		if binding.role == role:
			return _workbench.get_registration(binding.registration_name)
	return null


func _refresh_profile_status(
		direct_ready: bool,
		direct_issues: Array[String],
		role_count: int,
) -> void:
	%DirectProfileStatus.text = "READY" if direct_ready else "SETUP REQUIRED"
	%DirectProfileStatus.modulate = (
			Color(0.42, 0.82, 0.55) if direct_ready else Color(1.0, 0.72, 0.32)
	)
	%DirectProfileDetail.text = (
			"Content definitions and the active save are ready. %d total role binding(s)."
			% role_count
			if direct_ready
			else "Missing or unsafe configuration: %s." % ", ".join(direct_issues)
	)
	%ManagedProfileStatus.text = "PLANNED"
	%ManagedProfileDetail.text = (
			"Effective-content cache, package overlays, and mod orchestration are not implemented yet."
	)


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
