@tool
class_name GDSQLLogsPanel
extends VBoxContainer
## Bounded, resizable editor log feed for operations and diagnostics.

signal entry_selected(entry_id: int)

const LOG_ENTRY_SCENE := preload("res://addons/gdsql/editor/debug/gdsql_log_entry.tscn")
const CONTEXT_COPY_MESSAGE := 1
const CONTEXT_DELETE_ENTRY := 2
const CONTEXT_CLEAR_ALL := 3

@export_range(1, 10000, 1) var log_limit: int = 200

var selected_entry_id: int = -1
var _last_entry_id: int = -1

@onready var _empty_state: Label = $EmptyState
@onready var _scroll: ScrollContainer = $Scroll
@onready var _entries: VBoxContainer = $Scroll/Entries
@onready var _context_menu: PopupMenu = $ContextMenu


func _ready() -> void:
	_context_menu.id_pressed.connect(_on_context_action)
	gui_input.connect(_on_container_gui_input)
	_scroll.gui_input.connect(_on_container_gui_input)
	_entries.gui_input.connect(_on_container_gui_input)
	_update_empty_state()


func append_result(action_label: String, result: GDSQLOperationResult) -> void:
	if result == null:
		append_message("Error", action_label, "The action returned no result.")
		return
	if result.diagnostics.is_empty():
		append_message("OK", action_label, "Completed.")
		return
	for diagnostic in result.diagnostics.entries:
		append_message(_severity_label(diagnostic.severity), action_label, diagnostic.message)


func append_message(status: String, action_label: String, message: String) -> int:
	var entry := LOG_ENTRY_SCENE.instantiate() as GDSQLLogEntry
	var entry_id := _next_entry_id()
	entry.context_requested.connect(_on_entry_context_requested)
	_entries.add_child(entry)
	entry.configure(entry_id, Time.get_time_string_from_system(), status, action_label, message)
	_trim_to_limit()
	_update_empty_state()
	_scroll_to_latest()
	if status == "Error":
		_focus_log_dock()
	return entry_id


func clear() -> void:
	for entry in _entries.get_children():
		_entries.remove_child(entry)
		entry.queue_free()
	selected_entry_id = -1
	_update_empty_state()


func delete_entry(entry_id: int) -> bool:
	var entry := get_entry(entry_id)
	if entry == null:
		return false
	_entries.remove_child(entry)
	entry.queue_free()
	if selected_entry_id == entry_id:
		selected_entry_id = -1
	_update_empty_state()
	return true


func get_entry(entry_id: int) -> GDSQLLogEntry:
	for child in _entries.get_children():
		var entry := child as GDSQLLogEntry
		if entry != null and entry.entry_id == entry_id:
			return entry
	return null


func copy_entry_message(entry_id: int) -> bool:
	var entry := get_entry(entry_id)
	if entry == null:
		return false

	var clipboard_message := {
		"status": entry.status_text,
		"tick": Time.get_ticks_usec(),
		"action": entry.action_text,
		"message": entry.message_text,
	}

	DisplayServer.clipboard_set(
		"[{status}-T{tick}] Action: {action} | {message}]".format(clipboard_message)
	)
	return true


func select_entry(entry_id: int) -> bool:
	if get_entry(entry_id) == null:
		return false
	selected_entry_id = entry_id
	entry_selected.emit(entry_id)
	return true


func _next_entry_id() -> int:
	var unix_milliseconds := int(Time.get_unix_time_from_system() * 1000.0)
	_last_entry_id = maxi(unix_milliseconds, _last_entry_id + 1)
	return _last_entry_id


func _trim_to_limit() -> void:
	while _entries.get_child_count() > log_limit:
		var oldest := _entries.get_child(0)
		if oldest is GDSQLLogEntry \
				and (oldest as GDSQLLogEntry).entry_id == selected_entry_id:
			selected_entry_id = -1
		_entries.remove_child(oldest)
		oldest.queue_free()


func _scroll_to_latest() -> void:
	var scroll_bar := _scroll.get_v_scroll_bar()
	await scroll_bar.changed
	_scroll.scroll_vertical = int(scroll_bar.max_value - scroll_bar.page)


func _update_empty_state() -> void:
	var is_empty := _entries.get_child_count() == 0
	_empty_state.visible = is_empty
	_scroll.visible = not is_empty


func _focus_log_dock() -> void:
	var control: Control = get_parent_control()
	# Floating docks already own focus independently from the editor dock tabs.
	if control is TabContainer:
		var tab_container := control as TabContainer
		for tab_index in tab_container.get_tab_count():
			if tab_container.get_tab_title(tab_index) == "GDSQL Logs":
				tab_container.set_current_tab(tab_index)
				return


func _on_container_gui_input(event: InputEvent) -> void:
	var mouse_event := event as InputEventMouseButton
	if mouse_event == null \
			or mouse_event.button_index != MOUSE_BUTTON_RIGHT \
			or not mouse_event.pressed:
		return
	selected_entry_id = -1
	_context_menu.position = DisplayServer.mouse_get_position()
	_set_context_items(false)
	_context_menu.popup()


func _on_entry_context_requested(entry_id: int, screen_position: Vector2i) -> void:
	if not select_entry(entry_id):
		return
	_set_context_items(true)
	_context_menu.position = screen_position
	_context_menu.popup()


func _set_context_items(has_entry: bool) -> void:
	_context_menu.set_item_disabled(
		_context_menu.get_item_index(CONTEXT_COPY_MESSAGE),
		not has_entry,
	)
	_context_menu.set_item_disabled(
		_context_menu.get_item_index(CONTEXT_DELETE_ENTRY),
		not has_entry,
	)


func _on_context_action(id: int) -> void:
	match id:
		CONTEXT_COPY_MESSAGE:
			copy_entry_message(selected_entry_id)
		CONTEXT_DELETE_ENTRY:
			delete_entry(selected_entry_id)
		CONTEXT_CLEAR_ALL:
			clear()


func _severity_label(severity: GDSQLQueryDiagnostic.Severity) -> String:
	match severity:
		GDSQLQueryDiagnostic.Severity.INFO:
			return "Info"
		GDSQLQueryDiagnostic.Severity.WARNING:
			return "Warning"
		_:
			return "Error"
