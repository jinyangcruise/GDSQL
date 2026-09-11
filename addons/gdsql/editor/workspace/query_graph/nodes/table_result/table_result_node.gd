@tool
class_name GDSQLQueryTableResultNode
extends GDSQLQueryGraphNode
## Paginated tabular presentation for a graph query result.
##
## One native table component owns both paginated display and focused editing.

signal row_insert_requested(
	registration_name: StringName,
	table_name: StringName,
	values: Dictionary,
)
signal row_update_requested(
	registration_name: StringName,
	table_name: StringName,
	original_primary_key: Variant,
	values: Dictionary,
)
signal row_delete_requested(
	registration_name: StringName,
	table_name: StringName,
	primary_key: Variant,
)
signal capabilities_changed(can_add_rows: bool, has_dirty_rows: bool)

const ROW_SET_PORT_TYPE := 0
const ROW_SET_COLOR := Color("62b5e5")
const PAGE_SIZES: Array[int] = [10, 25, 50, 100]
const MINIMUM_NODE_SIZE := Vector2(720, 420)

var _registration_name: StringName
var _table: GDSQLTableDefinition
var _view_table: GDSQLTableDefinition
var _records: Array[GDSQLRowRecord] = []
var _can_add_rows := false
var _can_edit_rows := false
var _page_index := 0
var _page_size := 10
var _selected_record_index := -1
var _editor_active := false
var _editor_insert_draft := false
var _editor_source: GDSQLRowRecord
var _mutation_in_flight := false
var _safe_mode := true
var _safe_mode_toggle: CheckButton
var _presentation_revision := 0
var _resize_limits := Vector2(INF, INF)
var _resize_chrome := Vector2.ZERO
var _resize_chrome_measured := false
var _page_layout_initialized := false
var _applying_resize := false

@onready var _title: Label = %ResultTitle
@onready var _details: Label = %Details
@onready var _status: Label = %Status
@onready var _table_scroll: ScrollContainer = %ScrollContainer
@onready var _table_view: GDSQLQueryTableResultTable = %TableView
@onready var _pagination: HBoxContainer = %Pagination
@onready var _first_page: Button = %FirstPage
@onready var _previous_page: Button = %PreviousPage
@onready var _page_status: Label = %PageStatus
@onready var _next_page: Button = %NextPage
@onready var _last_page: Button = %LastPage
@onready var _page_size_selector: OptionButton = %PageSize
@onready var _editor_section: VBoxContainer = %EditorSection
@onready var _editor_table: GDSQLQueryTableResultTable = %EditorTable
@onready var _result_actions: HBoxContainer = %ResultActions
@onready var _add_row: GDSQLEditorActionButton = %AddRow
@onready var _save_changes: Button = %SaveChanges
@onready var _discard_changes: Button = %DiscardChanges
@onready var _delete_row: Button = %DeleteRow
@onready var _delete_confirmation: ConfirmationDialog = %DeleteConfirmation


func _ready() -> void:
	super._ready()
	_safe_mode_toggle = CheckButton.new()
	_safe_mode_toggle.text = "Safe Mode"
	_safe_mode_toggle.tooltip_text = (
		"Edit one selected row in a focused table editor. "
		+ "Disable to edit table cells directly."
	)
	_safe_mode_toggle.focus_mode = Control.FOCUS_NONE
	_safe_mode_toggle.button_pressed = true
	add_header_action(_safe_mode_toggle)
	set_slot(0, true, ROW_SET_PORT_TYPE, ROW_SET_COLOR, false, ROW_SET_PORT_TYPE, ROW_SET_COLOR)
	_table_view.item_selected.connect(_on_table_row_selected)
	_table_view.inline_changes_changed.connect(_on_inline_changes_changed)
	_editor_table.inline_changes_changed.connect(_on_editor_changes_changed)
	_safe_mode_toggle.toggled.connect(_on_safe_mode_toggled)
	_first_page.pressed.connect(_go_to_page.bind(0))
	_previous_page.pressed.connect(_change_page.bind(-1))
	_next_page.pressed.connect(_change_page.bind(1))
	_last_page.pressed.connect(_go_to_last_page)
	_page_size_selector.item_selected.connect(_on_page_size_selected)
	_save_changes.pressed.connect(_save_changes_requested)
	_discard_changes.pressed.connect(_discard_changes_requested)
	_delete_row.pressed.connect(_request_delete_editor_row)
	_delete_confirmation.confirmed.connect(_confirm_delete_editor_row)
	resize_request.connect(_on_resize_request)
	resized.connect(_enforce_resize_limits)
	_populate_page_sizes()
	_refresh_editor_actions()
	_initialize_resize_limits.call_deferred()


func configure_action(hub: GDSQLEditorActionHub, definition: GDSQLEditorActionDefinition) -> void:
	_add_row.configure(hub, definition)


func present(
	registration_name: StringName,
	table: GDSQLTableDefinition,
	result: GDSQLQueryResult,
) -> void:
	_presentation_revision += 1
	var selected_key: Variant = null
	var preserve_selection := _editor_source != null and _table != null
	if preserve_selection:
		selected_key = _editor_source.get_value(_table.primary_key)
	_registration_name = registration_name
	_table = table
	_clear_editor()
	_records.clear()
	_table_view.configure(null, null, _records, false)
	_table_view.set_safe_mode(_safe_mode)
	if result == null or not result.is_successful():
		_view_table = null
		_can_add_rows = false
		_can_edit_rows = false
		_title.text = "QUERY RESULT"
		_details.text = "The query did not return an editable table."
		_status.text = "Query failed. See the activity log for diagnostics."
		_set_table_visible(false)
		_emit_capabilities()
		return
	if table == null:
		_view_table = null
		_can_add_rows = false
		_can_edit_rows = false
		_title.text = "MUTATION RESULT"
		_details.text = "%d row(s) affected." % result.get_affected_rows()
		_status.text = "Mutation completed successfully."
		_set_table_visible(false)
		_emit_capabilities()
		return
	_view_table = _build_view_table(table, result.schema)
	_records = result.rows.duplicate()
	_can_add_rows = _has_all_columns(table, _view_table)
	_can_edit_rows = table.primary_key != &"" and _view_table.has_column(table.primary_key)
	_table_view.configure(_table, _view_table, _records, _can_edit_rows)
	_table_view.set_safe_mode(_safe_mode)
	_title.text = "QUERY RESULT · %s" % table.name
	_details.text = _capability_summary(_records.size())
	_set_table_visible(true)
	_page_index = clampi(_page_index, 0, maxi(0, _page_count() - 1))
	_selected_record_index = _find_record_index(selected_key) if preserve_selection else -1
	if _selected_record_index >= 0:
		_page_index = floori(float(_selected_record_index) / float(_page_size))
	_render_table()
	if not _page_layout_initialized:
		_fit_initial_page.call_deferred()
	_status.text = ("No rows returned."
		if _records.is_empty()
		else _result_status_text())
	if _safe_mode and _selected_record_index >= 0:
		_open_record_editor(_selected_record_index)
	_refresh_editor_actions()
	_emit_capabilities()


func can_add_rows() -> bool:
	return _can_add_rows


func has_dirty_rows() -> bool:
	return (
		(_editor_active and _editor_table.has_pending_changes())
		or (is_instance_valid(_table_view) and _table_view.has_pending_changes())
	)


func is_mutation_in_flight() -> bool:
	return _mutation_in_flight


func add_empty_row() -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if not _can_add_rows or _view_table == null:
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_QUERY_RESULT_INSERT_UNAVAILABLE",
				"Rows can only be added when the result contains every table column.",
			),
		)
		return result
	if has_dirty_rows():
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_QUERY_RESULT_DIRTY_ROW_ACTIVE",
				"Save or discard the current row before adding another row.",
			),
		)
		return result
	_selected_record_index = -1
	_clear_editor()
	_editor_source = null
	_editor_active = true
	_editor_insert_draft = true
	_editor_table.configure_insert_draft(_table, _view_table)
	_editor_section.visible = true
	_status.text = "Creating a new row."
	_refresh_editor_actions()
	result.value = _editor_table
	return result


func _build_view_table(
	table: GDSQLTableDefinition,
	schema: GDSQLResultSchema,
) -> GDSQLTableDefinition:
	var view := GDSQLTableDefinition.new(table.name, table.primary_key)
	view.database_name = table.database_name
	if schema == null:
		return view
	var result_columns: Dictionary[StringName, GDSQLColumnDefinition] = { }
	for result_column in schema.columns:
		result_columns[result_column.name] = result_column
	for table_column in table.columns:
		if result_columns.has(table_column.name):
			view.add_column(table_column)
			result_columns.erase(table_column.name)
	for result_column in schema.columns:
		if result_columns.has(result_column.name):
			view.add_column(result_column)
	return view


func _has_all_columns(table: GDSQLTableDefinition, view: GDSQLTableDefinition) -> bool:
	if table == null or view == null or table.columns.size() != view.columns.size():
		return false
	for column in table.columns:
		if not view.has_column(column.name):
			return false
	return true


func _capability_summary(row_count: int) -> String:
	var capabilities: Array[String] = ["%d row(s)" % row_count]
	capabilities.append("editable" if _can_edit_rows else "read only")
	capabilities.append(
		"rows can be added" if _can_add_rows else "projected result; adding rows is unavailable",
	)
	return " · ".join(capabilities)


func _set_table_visible(visible: bool) -> void:
	_table_view.visible = visible
	_pagination.visible = visible
	_result_actions.visible = visible
	_editor_section.visible = visible and _editor_active
	if not visible:
		_table_view.clear()


func _render_table() -> void:
	var first_index := _page_index * _page_size
	var end_index := mini(first_index + _page_size, _records.size())
	_table_view.render_page(first_index, end_index, _selected_record_index, _page_size)
	_update_pagination()
	_refresh_resize_limits.call_deferred(true, false)


func _on_table_row_selected() -> void:
	if _table_view.is_rendering():
		return
	var item := _table_view.get_selected()
	if item == null:
		return
	var record_index := int(item.get_metadata(0))
	if record_index == _selected_record_index:
		return
	if _safe_mode and has_dirty_rows():
		_status.text = "Save or discard the current row before selecting another row."
		_render_table()
		return
	if _safe_mode:
		_open_record_editor(record_index)
	else:
		_selected_record_index = record_index
		_status.text = "Row %d selected. Double-click a value to edit it." % (record_index + 1)
		_refresh_editor_actions()


func _on_inline_changes_changed(message: String) -> void:
	_status.text = message
	_refresh_editor_actions()
	_emit_capabilities()


func _on_editor_changes_changed(message: String) -> void:
	_status.text = message
	_refresh_editor_actions()
	_emit_capabilities()


func _open_record_editor(record_index: int) -> void:
	if record_index < 0 or record_index >= _records.size():
		return
	_clear_editor()
	_selected_record_index = record_index
	_editor_source = _records[record_index]
	_editor_active = true
	_editor_insert_draft = false
	var editor_records: Array[GDSQLRowRecord] = [_editor_source]
	_editor_table.configure(_table, _view_table, editor_records, _can_edit_rows)
	_editor_table.set_safe_mode(false)
	_editor_table.render_page(0, 1, 0, 1)
	_editor_section.visible = true
	_status.text = "Editing row %d of %d." % [record_index + 1, _records.size()]
	_refresh_editor_actions()


func _clear_editor() -> void:
	_editor_active = false
	_editor_insert_draft = false
	_editor_source = null
	if is_node_ready():
		var empty_records: Array[GDSQLRowRecord] = []
		_editor_table.configure(null, null, empty_records, false)
		_editor_table.clear()
	_editor_section.visible = false
	_refresh_editor_actions()
	if _safe_mode:
		_refresh_resize_limits.call_deferred(false, true)


func _save_changes_requested() -> void:
	if _editor_active:
		_save_editor_row()
	else:
		_save_inline_changes()


func _save_editor_row() -> void:
	if not _editor_active or not has_dirty_rows():
		return
	if _editor_table.has_validation_errors():
		_status.text = "Correct the highlighted invalid values before saving."
		return
	_mutation_in_flight = true
	if _editor_insert_draft:
		var conversion := _editor_table.get_insert_values_result()
		if not bool(conversion.get("valid", false)):
			_status.text = String(conversion.get("message", "Invalid row values."))
			_mutation_in_flight = false
			return
		row_insert_requested.emit(_registration_name, _table.name, conversion.get("values", { }))
	else:
		var pending := _editor_table.get_pending_updates()
		if pending.is_empty():
			_mutation_in_flight = false
			return
		row_update_requested.emit(
			_registration_name,
			_table.name,
			_editor_source.get_value(_table.primary_key),
			pending[0].values,
		)
	_mutation_in_flight = false


func _save_inline_changes() -> void:
	if not _table_view.has_pending_changes():
		return
	if _table_view.has_validation_errors():
		_status.text = "Correct the highlighted invalid values before saving."
		return
	var pending := _table_view.get_pending_updates()
	var failed: Array[Dictionary] = []
	var saved_count := 0
	_mutation_in_flight = true
	for update in pending:
		var previous_revision := _presentation_revision
		row_update_requested.emit(
			_registration_name,
			_table.name,
			update.primary_key,
			update.values,
		)
		if _presentation_revision == previous_revision:
			failed.append(update)
		else:
			saved_count += 1
	_mutation_in_flight = false
	_table_view.clear_pending_changes()
	_table_view.restore_pending_updates(failed)
	_render_table()
	_status.text = (
		"Saved changes to %d row(s)." % saved_count
		if failed.is_empty()
		else "%d row(s) saved; %d failed update(s) remain pending." % [saved_count, failed.size()]
	)
	_refresh_editor_actions()
	_emit_capabilities()


func _request_delete_editor_row() -> void:
	var source := _selected_source_record()
	if source == null:
		if _editor_active and _editor_insert_draft:
			_discard_editor_row()
		return
	_delete_confirmation.dialog_text = (
		"Delete the row whose primary key is %s?"
		% _value_text(source.get_value(_table.primary_key))
	)
	_delete_confirmation.popup_centered(Vector2i(420, 160))


func _confirm_delete_editor_row() -> void:
	var source := _selected_source_record()
	if source == null:
		return
	_mutation_in_flight = true
	row_delete_requested.emit(_registration_name, _table.name, source.get_value(_table.primary_key))
	_mutation_in_flight = false


func _discard_editor_row() -> void:
	_selected_record_index = -1
	_clear_editor()
	_table_view.deselect_all()
	_status.text = "New row discarded."
	_emit_capabilities()


func _discard_editor_changes() -> void:
	if not _editor_active or not has_dirty_rows():
		return
	if _editor_insert_draft:
		_discard_editor_row()
		return
	var record_index := _selected_record_index
	_open_record_editor(record_index)
	_status.text = "Unsaved changes were discarded."
	_emit_capabilities()


func _discard_changes_requested() -> void:
	if _editor_active:
		_discard_editor_changes()
		return
	if not _table_view.has_pending_changes():
		return
	_table_view.clear_pending_changes()
	_render_table()
	_status.text = "Unsaved cell changes were discarded."
	_refresh_editor_actions()
	_emit_capabilities()


func _on_safe_mode_toggled(enabled: bool) -> void:
	if enabled == _safe_mode:
		return
	if has_dirty_rows():
		_safe_mode_toggle.set_pressed_no_signal(_safe_mode)
		_status.text = "Save or discard pending changes before switching edit modes."
		return
	_safe_mode = enabled
	_table_view.set_safe_mode(_safe_mode)
	_clear_editor()
	_render_table()
	if _safe_mode and _selected_record_index >= 0:
		_open_record_editor(_selected_record_index)
	else:
		_status.text = _result_status_text()
	_refresh_editor_actions()


func _refresh_editor_actions() -> void:
	if not is_node_ready():
		return
	var has_editor := _editor_active
	var editor_can_mutate := has_editor and _editor_table.can_mutate()
	var inline_can_mutate := not _safe_mode and _can_edit_rows
	var can_save := editor_can_mutate or inline_can_mutate
	_save_changes.disabled = not can_save or not has_dirty_rows()
	_discard_changes.disabled = not can_save or not has_dirty_rows()
	_delete_row.disabled = (
		_selected_source_record() == null or (has_editor and not editor_can_mutate)
		or (not _safe_mode and has_dirty_rows())
	)


func _selected_source_record() -> GDSQLRowRecord:
	if _selected_record_index < 0 or _selected_record_index >= _records.size():
		return null
	return _records[_selected_record_index]


func _result_status_text() -> String:
	if _records.is_empty():
		return "No rows returned."
	if _safe_mode:
		return "%d row(s) returned. Select a row to inspect or edit it." % _records.size()
	return "%d row(s) returned. Double-click an editable value to change it." % _records.size()


func _populate_page_sizes() -> void:
	_page_size_selector.clear()
	for size in PAGE_SIZES:
		_page_size_selector.add_item(str(size))
		_page_size_selector.set_item_metadata(_page_size_selector.item_count - 1, size)
		if size == _page_size:
			_page_size_selector.select(_page_size_selector.item_count - 1)


func _page_count() -> int:
	return maxi(1, ceili(float(_records.size()) / float(_page_size)))


func _update_pagination() -> void:
	var count := _page_count()
	_page_index = clampi(_page_index, 0, count - 1)
	var first_row := _page_index * _page_size + 1 if not _records.is_empty() else 0
	var last_row := mini((_page_index + 1) * _page_size, _records.size())
	_page_status.text = "Page %d of %d · rows %d–%d of %d" % [
		_page_index + 1,
		count,
		first_row,
		last_row,
		_records.size(),
	]
	_first_page.disabled = _page_index == 0
	_previous_page.disabled = _page_index == 0
	_next_page.disabled = _page_index >= count - 1
	_last_page.disabled = _page_index >= count - 1


func _change_page(offset: int) -> void:
	_go_to_page(_page_index + offset)


func _go_to_last_page() -> void:
	_go_to_page(_page_count() - 1)


func _go_to_page(page: int) -> void:
	if has_dirty_rows():
		_status.text = "Save or discard the current row before changing pages."
		return
	_selected_record_index = -1
	_clear_editor()
	_page_index = clampi(page, 0, _page_count() - 1)
	_render_table()


func _on_page_size_selected(index: int) -> void:
	if has_dirty_rows():
		_status.text = "Save or discard the current row before changing page size."
		_populate_page_sizes()
		return
	_page_size = int(_page_size_selector.get_item_metadata(index))
	_page_index = 0
	_selected_record_index = -1
	_clear_editor()
	_render_table()
	_page_layout_initialized = true
	_refresh_resize_limits.call_deferred(true, true)


func _find_record_index(primary_key: Variant) -> int:
	if _table == null or _table.primary_key == &"":
		return -1
	for index in range(_records.size()):
		if _records[index].get_value(_table.primary_key) == primary_key:
			return index
	return -1


func _initialize_resize_limits() -> void:
	await get_tree().process_frame
	if not is_inside_tree():
		return
	if Engine.is_editor_hint():
		var edited_scene_root := EditorInterface.get_edited_scene_root()
		if edited_scene_root == self \
				or (edited_scene_root != null and edited_scene_root.is_ancestor_of(self)):
			return
	_measure_resize_chrome()


func _measure_resize_chrome() -> void:
	_resize_chrome = Vector2(
		maxf(0.0, size.x - _table_scroll.size.x),
		maxf(0.0, size.y - _table_scroll.size.y),
	)
	_resize_chrome_measured = _table_scroll.size.x > 0.0 and _table_scroll.size.y > 0.0


func _fit_initial_page() -> void:
	if _page_layout_initialized or _view_table == null:
		return
	if not _resize_chrome_measured:
		await get_tree().process_frame
		if not is_inside_tree() or _view_table == null:
			return
		_measure_resize_chrome()
	_refresh_resize_limits(true, true)
	_page_layout_initialized = true


func _refresh_resize_limits(resize_width: bool, resize_height: bool) -> void:
	if not is_node_ready():
		return
	if not _resize_chrome_measured:
		return
	var content_width := maxf(
		MINIMUM_NODE_SIZE.x - _resize_chrome.x,
		_table_view.get_content_width(),
	)
	var content_height := _table_view.estimate_height_for_rows(_page_size)
	if _safe_mode and _editor_section.visible:
		content_height += maxf(
			_editor_section.size.y,
			_editor_section.get_combined_minimum_size().y,
		)
		var editor_parent := _editor_section.get_parent() as VBoxContainer
		if editor_parent != null:
			content_height += editor_parent.get_theme_constant(&"separation")
	_resize_limits = Vector2(
		maxf(MINIMUM_NODE_SIZE.x, content_width + _resize_chrome.x),
		maxf(MINIMUM_NODE_SIZE.y, content_height + _resize_chrome.y),
	)
	var target := Vector2(
		(_resize_limits.x
			if resize_width
			else clampf(size.x, MINIMUM_NODE_SIZE.x, _resize_limits.x)),
		(_resize_limits.y
			if resize_height
			else clampf(size.y, MINIMUM_NODE_SIZE.y, _resize_limits.y)),
	)
	_apply_node_size(target)


func _on_resize_request(requested_size: Vector2) -> void:
	_apply_node_size(
		Vector2(
			clampf(requested_size.x, MINIMUM_NODE_SIZE.x, _resize_limits.x),
			clampf(requested_size.y, MINIMUM_NODE_SIZE.y, _resize_limits.y),
		),
	)


func _enforce_resize_limits() -> void:
	if _applying_resize or not is_node_ready():
		return
	_on_resize_request(size)


func _apply_node_size(target: Vector2) -> void:
	if size.is_equal_approx(target):
		return
	_applying_resize = true
	size = target
	_applying_resize = false


func _value_text(value: Variant) -> String:
	if value == null:
		return "null"
	if value is Resource:
		return (
			value.resource_path
			if not value.resource_path.is_empty()
			else "<%s>" % value.get_class()
		)
	if value is String or value is StringName or value is NodePath:
		return String(value)
	return var_to_str(value)


func _emit_capabilities() -> void:
	capabilities_changed.emit(_can_add_rows, has_dirty_rows())
