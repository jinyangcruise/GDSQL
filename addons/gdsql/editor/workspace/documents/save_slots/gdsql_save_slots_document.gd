@tool
extends MarginContainer
## Lists standard save registrations and selects the editor-authored active slot.

const SAVE_SLOTS_ROOT := "user://gdsql/saves"

var _action_hub: GDSQLEditorActionHub
var _workbench: GDSQLWorkbench
var _pending_delete: GDSQLSaveSlotDeletionPlan
var _pending_unregister: StringName

@onready var _create: GDSQLEditorActionButton = %CreateSaveSlot
@onready var _tree: Tree = %SaveSlotTree
@onready var _empty_state: Label = %EmptyState
@onready var _active_slot: Label = %ActiveSlot
@onready var _summary: Label = %Summary
@onready var _status: Label = %Status
@onready var _use_slot: Button = %UseSlot
@onready var _open_slot: Button = %OpenSlot
@onready var _unregister_slot: Button = %UnregisterSlot
@onready var _delete_slot: Button = %DeleteSlot
@onready var _unregister_confirmation: ConfirmationDialog = %UnregisterConfirmation
@onready var _delete_confirmation: ConfirmationDialog = %DeleteConfirmation
@onready var _runtime_content: VBoxContainer = %RuntimeContent
@onready var _scene_preview: VBoxContainer = %ScenePreview


func _ready() -> void:
	_tree.item_selected.connect(_update_selection)
	_tree.item_activated.connect(_open_selected_slot)
	%RefreshSlots.pressed.connect(_refresh_requested)
	_use_slot.pressed.connect(_select_requested)
	_open_slot.pressed.connect(_open_selected_slot)
	_unregister_slot.pressed.connect(_request_unregister)
	_delete_slot.pressed.connect(_request_delete)
	_unregister_confirmation.confirmed.connect(_unregister_confirmed)
	_delete_confirmation.confirmed.connect(_delete_confirmed)
	_configure_tree()
	if _is_scene_preview():
		return
	_scene_preview.hide()
	_runtime_content.show()
	refresh_slots()


func _configure_tree() -> void:
	var titles := ["Slot", "State", "Storage", "Location"]
	for column in titles.size():
		_tree.set_column_title(column, titles[column])
		_tree.set_column_expand(column, column in [0, 3])
	_tree.set_column_custom_minimum_width(0, 160)
	_tree.set_column_custom_minimum_width(1, 90)
	_tree.set_column_custom_minimum_width(2, 130)
	_tree.set_column_custom_minimum_width(3, 260)


func configure(action_hub: GDSQLEditorActionHub, workbench: GDSQLWorkbench) -> void:
	_action_hub = action_hub
	_workbench = workbench
	_create.configure_action(action_hub, GDSQLEditorActionIds.CREATE_SAVE_SLOT)
	refresh_slots()


func refresh_slots() -> void:
	if not is_node_ready() or _is_scene_preview():
		return
	var active := _active_registration()
	var slots := _save_registrations(active)
	_tree.clear()
	var root := _tree.create_item()
	var active_item: TreeItem
	for registration in slots:
		var item := _tree.create_item(root)
		item.set_text(0, String(registration.database_name))
		item.set_text(1, "Active" if registration.name == active else "Available")
		item.set_text(
			2,
			GDSQLStorageBackendIds.get_display_name(registration.storage_backend_id),
		)
		item.set_text(3, registration.data_root)
		item.set_metadata(0, registration.name)
		item.set_tooltip_text(
			0,
			"Registration: %s\nDatabase: %s" \
					% [registration.name, registration.database_name],
		)
		if registration.name == active:
			active_item = item
	_empty_state.visible = slots.is_empty()
	_tree.visible = not slots.is_empty()
	_summary.text = "%d save slot(s) registered" % slots.size()
	_active_slot.text = "None selected" if active == &"" else String(active)
	if active_item != null:
		active_item.select(0)
	elif root != null and root.get_first_child() != null:
		root.get_first_child().select(0)
	_status.text = (
			"Create the first save slot to configure the runtime save role."
			if slots.is_empty()
			else "Selection changes project runtime configuration; it does not alter slot data."
	)
	_update_selection()


func _save_registrations(active: StringName) -> Array[GDSQLDatabaseRegistration]:
	var slots: Array[GDSQLDatabaseRegistration] = []
	if _workbench == null:
		return slots
	for registration in _workbench.get_registrations():
		if registration.name == active \
				or registration.data_root.begins_with(SAVE_SLOTS_ROOT + "/"):
			slots.append(registration)
	slots.sort_custom(
		func(left: GDSQLDatabaseRegistration, right: GDSQLDatabaseRegistration) -> bool:
			if left.name == active:
				return true
			if right.name == active:
				return false
			return String(left.database_name).naturalnocasecmp_to(
				String(right.database_name),
			) < 0,
	)
	return slots


func _active_registration() -> StringName:
	if _workbench == null:
		return &""
	for binding in _workbench.snapshot.role_bindings:
		if binding.role == GDSQLDatabaseRegistry.SAVE_ROLE:
			return binding.registration_name
	return &""


func _selected_registration() -> StringName:
	var item := _tree.get_selected()
	return StringName(item.get_metadata(0)) if item != null else &""


func _update_selection() -> void:
	var selected := _selected_registration()
	var has_selection := selected != &""
	var is_active := has_selection and selected == _active_registration()
	_open_slot.disabled = not has_selection
	_use_slot.disabled = not has_selection or is_active
	_use_slot.text = "Active Slot" if is_active else "Use This Slot"
	_unregister_slot.disabled = not has_selection
	_delete_slot.disabled = not _build_selected_deletion_plan().is_successful()


func _refresh_requested() -> void:
	if _action_hub != null:
		_action_hub.invoke(GDSQLEditorActionIds.SHOW_SAVE_SLOTS)


func _select_requested() -> void:
	var selected := _selected_registration()
	if _action_hub == null or selected == &"":
		return
	var result := _action_hub.invoke(
		GDSQLEditorActionIds.SELECT_SAVE_SLOT,
		[selected],
	)
	if result.is_successful():
		refresh_slots()
		_status.text = "'%s' is now the active save slot." % selected
	elif not result.diagnostics.entries.is_empty():
		_status.text = result.diagnostics.entries[0].message


func _open_selected_slot() -> void:
	var selected := _selected_registration()
	if _action_hub != null and selected != &"":
		_action_hub.invoke(
			GDSQLEditorActionIds.OPEN_REGISTRATION,
			[selected],
			true,
		)


func _request_unregister() -> void:
	var registration := _selected_registration_value()
	if registration == null:
		return
	_pending_unregister = registration.name
	_unregister_confirmation.dialog_text = (
			"Unregister save slot '%s'?\n\n"
			+ "Its database files at '%s' will remain unchanged, but this logical "
			+ "database will no longer appear as a slot until it is registered again."
	) % [registration.database_name, registration.data_root]
	_unregister_confirmation.popup_centered(Vector2i(560, 210))


func _unregister_confirmed() -> void:
	if _action_hub == null or _pending_unregister == &"":
		return
	var registration_name := _pending_unregister
	_pending_unregister = &""
	var result := _action_hub.invoke(
		GDSQLEditorActionIds.REMOVE_REGISTRATION,
		[registration_name],
	)
	_handle_destructive_result(result, "Save slot unregistered; its files were kept.")


func _request_delete() -> void:
	var planned := _build_selected_deletion_plan()
	if not planned.is_successful():
		_show_first_diagnostic(planned)
		return
	_pending_delete = planned.get_value() as GDSQLSaveSlotDeletionPlan
	var active_warning := (
			"\n\nThis is the active runtime save. The save role will be unbound."
			if _pending_delete.was_active
			else ""
	)
	_delete_confirmation.dialog_text = (
			"Permanently delete save slot database '%s'?\n\n"
			+ "Database data: %s\n"
			+ "Slot root: %s\n\n"
			+ "Schemas and rows for this database will be deleted. This cannot be undone.%s"
	) % [
		_pending_delete.database_name,
		_pending_delete.database_path,
		_pending_delete.data_root,
		active_warning,
	]
	_delete_confirmation.popup_centered(Vector2i(600, 260))


func _delete_confirmed() -> void:
	if _action_hub == null or _pending_delete == null:
		return
	var registration_name := _pending_delete.registration_name
	_pending_delete = null
	var result := _action_hub.invoke(
		GDSQLEditorActionIds.DELETE_SAVE_SLOT,
		[registration_name],
	)
	_handle_destructive_result(result, "Save slot data permanently deleted.")


func _build_selected_deletion_plan() -> GDSQLOperationResult:
	return GDSQLSaveSlotDeletionPlan.build(
		_selected_registration_value(),
		_active_registration(),
	)


func _selected_registration_value() -> GDSQLDatabaseRegistration:
	if _workbench == null:
		return null
	return _workbench.get_registration(_selected_registration())


func _handle_destructive_result(result: GDSQLOperationResult, success: String) -> void:
	if result.is_successful():
		refresh_slots()
		_status.text = success
	else:
		_show_first_diagnostic(result)


func _show_first_diagnostic(result: GDSQLOperationResult) -> void:
	if not result.diagnostics.entries.is_empty():
		_status.text = result.diagnostics.entries[0].message


func _is_scene_preview() -> bool:
	if not Engine.is_editor_hint():
		return false
	var edited_scene_root := EditorInterface.get_edited_scene_root()
	return edited_scene_root == self \
			or (edited_scene_root != null and edited_scene_root.is_ancestor_of(self))
