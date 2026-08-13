@tool
class_name GDSQLQueryTableResultNode
extends GDSQLQueryGraphNode
## Paginated tabular presentation for a graph query result.
##
## A native Tree owns aligned, scrollable columns. Selecting a row opens the
## existing typed Variant editor below the table; this keeps Resource and
## non-string values out of Tree's text-only editing path.

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

const DATA_ROW_SCENE := preload(
	"res://addons/gdsql/editor/workspace/components/table/gdsql_table_data_row.tscn"
)
const ROW_SET_PORT_TYPE := 0
const ROW_SET_COLOR := Color("62b5e5")
const PAGE_SIZES: Array[int] = [10, 25, 50, 100]

var _registration_name: StringName
var _table: GDSQLTableDefinition
var _view_table: GDSQLTableDefinition
var _records: Array[GDSQLRowRecord] = []
var _can_add_rows := false
var _can_edit_rows := false
var _page_index := 0
var _page_size := 25
var _selected_record_index := -1
var _editor_row: Control
var _editor_source: GDSQLRowRecord
var _rendering_table := false
var _mutation_in_flight := false

@onready var _title: Label = %ResultTitle
@onready var _details: Label = %Details
@onready var _status: Label = %Status
@onready var _table_view: Tree = %TableView
@onready var _pagination: HBoxContainer = %Pagination
@onready var _first_page: Button = %FirstPage
@onready var _previous_page: Button = %PreviousPage
@onready var _page_status: Label = %PageStatus
@onready var _next_page: Button = %NextPage
@onready var _last_page: Button = %LastPage
@onready var _page_size_selector: OptionButton = %PageSize
@onready var _editor_section: VBoxContainer = %EditorSection
@onready var _editor_host: VBoxContainer = %EditorHost
@onready var _result_actions: HBoxContainer = %ResultActions
@onready var _add_row: GDSQLEditorActionButton = %AddRow
@onready var _save_changes: Button = %SaveChanges
@onready var _discard_changes: Button = %DiscardChanges
@onready var _delete_row: Button = %DeleteRow
@onready var _delete_confirmation: ConfirmationDialog = %DeleteConfirmation


func _ready() -> void:
	super._ready()
	set_slot(
		0,
		true,
		ROW_SET_PORT_TYPE,
		ROW_SET_COLOR,
		false,
		ROW_SET_PORT_TYPE,
		ROW_SET_COLOR,
	)
	_table_view.item_selected.connect(_on_table_row_selected)
	_first_page.pressed.connect(_go_to_page.bind(0))
	_previous_page.pressed.connect(_change_page.bind(-1))
	_next_page.pressed.connect(_change_page.bind(1))
	_last_page.pressed.connect(_go_to_last_page)
	_page_size_selector.item_selected.connect(_on_page_size_selected)
	_save_changes.pressed.connect(_save_editor_row)
	_discard_changes.pressed.connect(_discard_editor_changes)
	_delete_row.pressed.connect(_request_delete_editor_row)
	_delete_confirmation.confirmed.connect(_confirm_delete_editor_row)
	_populate_page_sizes()
	_refresh_editor_actions()


func configure_action(
		hub: GDSQLEditorActionHub,
		definition: GDSQLEditorActionDefinition,
) -> void:
	_add_row.configure(hub, definition)


func present(
		registration_name: StringName,
		table: GDSQLTableDefinition,
		result: GDSQLQueryResult,
) -> void:
	var selected_key: Variant = null
	var preserve_selection := _editor_source != null and _table != null
	if preserve_selection:
		selected_key = _editor_source.get_value(_table.primary_key)
	_registration_name = registration_name
	_table = table
	_clear_editor()
	_records.clear()
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
	_title.text = "QUERY RESULT · %s" % table.name
	_details.text = _capability_summary(_records.size())
	_set_table_visible(true)
	_page_index = clampi(_page_index, 0, maxi(0, _page_count() - 1))
	_selected_record_index = _find_record_index(selected_key) if preserve_selection else -1
	if _selected_record_index >= 0:
		_page_index = floori(float(_selected_record_index) / float(_page_size))
	_render_table()
	_status.text = (
			"No rows returned."
			if _records.is_empty()
			else "%d row(s) returned. Select a row to inspect or edit it." % _records.size()
	)
	if _selected_record_index >= 0:
		_open_record_editor(_selected_record_index)
	_emit_capabilities()


func can_add_rows() -> bool:
	return _can_add_rows


func has_dirty_rows() -> bool:
	return is_instance_valid(_editor_row) and bool(_editor_row.call("is_dirty"))


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
	_editor_row = _create_editor_row(null)
	_status.text = "Creating a new row."
	_refresh_editor_actions()
	result.value = _editor_row
	return result


func _build_view_table(
		table: GDSQLTableDefinition,
		schema: GDSQLResultSchema,
) -> GDSQLTableDefinition:
	var view := GDSQLTableDefinition.new(table.name, table.primary_key)
	view.database_name = table.database_name
	if schema == null:
		return view
	for result_column in schema.columns:
		var source_column := table.get_column(result_column.name)
		view.add_column(source_column if source_column != null else result_column)
	return view


func _has_all_columns(
		table: GDSQLTableDefinition,
		view: GDSQLTableDefinition,
) -> bool:
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
	_editor_section.visible = visible and is_instance_valid(_editor_row)
	if not visible:
		_table_view.clear()


func _render_table() -> void:
	_rendering_table = true
	_table_view.clear()
	if _view_table == null:
		_rendering_table = false
		_update_pagination()
		return
	_table_view.columns = maxi(1, _view_table.columns.size())
	for column_index in range(_view_table.columns.size()):
		var column := _view_table.columns[column_index]
		_table_view.set_column_title(
			column_index,
			"%s (%s)" % [column.name, type_string(column.data_type)],
		)
		_table_view.set_column_title_tooltip_text(
			column_index,
			"%s · %s" % [column.name, type_string(column.data_type)],
		)
		_table_view.set_column_custom_minimum_width(column_index, 140)
		_table_view.set_column_expand(column_index, true)
		_table_view.set_column_expand_ratio(column_index, 1)
		_table_view.set_column_clip_content(column_index, true)
	var root := _table_view.create_item()
	var first_index := _page_index * _page_size
	var end_index := mini(first_index + _page_size, _records.size())
	for record_index in range(first_index, end_index):
		var record := _records[record_index]
		var item := _table_view.create_item(root)
		item.set_metadata(0, record_index)
		for column_index in range(_view_table.columns.size()):
			var value: Variant = record.get_value(_view_table.columns[column_index].name)
			var text := _value_text(value)
			item.set_text(column_index, text)
			item.set_tooltip_text(column_index, text)
		if record_index == _selected_record_index:
			item.select(0)
	_rendering_table = false
	_update_pagination()


func _on_table_row_selected() -> void:
	if _rendering_table:
		return
	var item := _table_view.get_selected()
	if item == null:
		return
	var record_index := int(item.get_metadata(0))
	if record_index == _selected_record_index:
		return
	if has_dirty_rows():
		_status.text = "Save or discard the current row before selecting another row."
		_render_table()
		return
	_open_record_editor(record_index)


func _open_record_editor(record_index: int) -> void:
	if record_index < 0 or record_index >= _records.size():
		return
	_clear_editor()
	_selected_record_index = record_index
	_editor_source = _records[record_index]
	_editor_row = _create_editor_row(_editor_source)
	_editor_section.visible = true
	_status.text = "Editing row %d of %d." % [record_index + 1, _records.size()]
	_refresh_editor_actions()


func _create_editor_row(source: GDSQLRowRecord) -> Control:
	var row := DATA_ROW_SCENE.instantiate() as Control
	_editor_host.add_child(row)
	row.connect("dirty_changed", _on_row_dirty_changed)
	row.call(
		"configure",
		_view_table,
		source,
		_can_add_rows if source == null else _can_edit_rows,
	)
	_editor_section.visible = true
	_refresh_editor_actions()
	return row


func _clear_editor() -> void:
	if is_instance_valid(_editor_row):
		_editor_host.remove_child(_editor_row)
		_editor_row.queue_free()
	_editor_row = null
	_editor_source = null
	_editor_section.visible = false
	_refresh_editor_actions()


func _save_editor_row() -> void:
	if not is_instance_valid(_editor_row) or not has_dirty_rows():
		return
	var conversion: Dictionary = _editor_row.call("get_values_result")
	if not bool(conversion.get("valid", false)):
		_editor_row.call("set_status", String(conversion.get("message", "Invalid row values.")))
		return
	_editor_row.call("set_status", "")
	_mutation_in_flight = true
	if _editor_source == null:
		row_insert_requested.emit(
			_registration_name,
			_table.name,
			conversion.get("values", { }),
		)
	else:
		row_update_requested.emit(
			_registration_name,
			_table.name,
			_editor_row.call("get_original_primary_key"),
			conversion.get("values", { }),
		)
	_mutation_in_flight = false


func _request_delete_editor_row() -> void:
	if not is_instance_valid(_editor_row):
		return
	if _editor_source == null:
		_discard_editor_row()
		return
	_delete_confirmation.dialog_text = (
			"Delete the row whose primary key is %s?"
			% _value_text(_editor_row.call("get_original_primary_key"))
	)
	_delete_confirmation.popup_centered(Vector2i(420, 160))


func _confirm_delete_editor_row() -> void:
	if not is_instance_valid(_editor_row) or _editor_source == null:
		return
	_mutation_in_flight = true
	row_delete_requested.emit(
		_registration_name,
		_table.name,
		_editor_row.call("get_original_primary_key"),
	)
	_mutation_in_flight = false


func _discard_editor_row() -> void:
	_selected_record_index = -1
	_clear_editor()
	_table_view.deselect_all()
	_status.text = "New row discarded."
	_emit_capabilities()


func _discard_editor_changes() -> void:
	if not is_instance_valid(_editor_row) or not has_dirty_rows():
		return
	if _editor_source == null:
		_discard_editor_row()
		return
	var record_index := _selected_record_index
	_open_record_editor(record_index)
	_status.text = "Unsaved changes were discarded."
	_emit_capabilities()


func _on_row_dirty_changed(row: Control, dirty: bool) -> void:
	if row != _editor_row:
		return
	_status.text = "The selected row has unsaved changes." if dirty else _status.text
	_refresh_editor_actions()
	_emit_capabilities()


func _refresh_editor_actions() -> void:
	if not is_node_ready():
		return
	var has_editor := is_instance_valid(_editor_row)
	var can_mutate := has_editor and bool(_editor_row.call("can_mutate"))
	_save_changes.disabled = not can_mutate or not has_dirty_rows()
	_discard_changes.disabled = not can_mutate or not has_dirty_rows()
	_delete_row.disabled = not can_mutate or _editor_source == null


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


func _find_record_index(primary_key: Variant) -> int:
	if _table == null or _table.primary_key == &"":
		return -1
	for index in range(_records.size()):
		if _records[index].get_value(_table.primary_key) == primary_key:
			return index
	return -1


func _value_text(value: Variant) -> String:
	if value == null:
		return "null"
	if value is Resource:
		return value.resource_path if not value.resource_path.is_empty() else value.get_class()
	if value is String or value is StringName or value is NodePath:
		return String(value)
	return var_to_str(value)


func _emit_capabilities() -> void:
	capabilities_changed.emit(_can_add_rows, has_dirty_rows())
