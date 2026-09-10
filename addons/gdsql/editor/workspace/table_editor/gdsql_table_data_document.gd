@tool
extends MarginContainer
## Compact table-first data document backed by the shared typed result grid.

signal rows_requested(
		registration_name: StringName,
		table_name: StringName,
		query: GDSQLSelectQuerySpec,
		count_query: GDSQLSelectQuerySpec,
)
signal row_insert_requested(
		registration_name: StringName,
		table_name: StringName,
		values: Dictionary,
)
signal rows_update_requested(
		registration_name: StringName,
		table_name: StringName,
		updates: Array[Dictionary],
)
signal rows_delete_requested(
		registration_name: StringName,
		table_name: StringName,
		primary_keys: Array[Variant],
)
signal model_assistant_requested(
		registration_name: StringName,
		table: GDSQLTableDefinition,
)

const PAGE_SIZES: Array[int] = [10, 25, 50, 100]
const COLUMN_SELECT_ALL := 10_000
const ROW_NUMBER_COLUMN := &"__gdsql_row_number"

var registration_name: StringName
var table_name: StringName
var _table: GDSQLTableDefinition
var _records: Array[GDSQLRowRecord] = []
var _pending_delete_keys: Array[Variant] = []
var _page_index := 0
var _page_size := 25
var _total_rows := 0
var _catalog_total_rows := 0
var _presentation_revision := 0
var _mutation_in_flight := false
var _applied_predicate: GDSQLQueryExpression
var _applied_filter_summary := ""
var _filter_dirty := false
var _visible_columns: Array[StringName] = []
var _order_column: StringName
var _order_direction := GDSQLOrderClause.SortDirection.ASCENDING

@onready var _table_view: GDSQLQueryTableResultTable = %TableView
@onready var _insert_editor: GDSQLQueryTableResultTable = %InsertEditor
@onready var _where_expression: GDSQLWhereExpressionEditor = %WhereExpression
@onready var _column_menu: PopupMenu = %ColumnMenu


func _ready() -> void:
	if _is_scene_preview():
		return
	%ScenePreview.hide()
	%Refresh.pressed.connect(request_rows)
	%Model.pressed.connect(_open_model_assistant)
	%AddRow.pressed.connect(_begin_insert)
	%SaveChanges.pressed.connect(_save_changes)
	%DiscardChanges.pressed.connect(_discard_changes)
	%DeleteSelected.pressed.connect(_request_selected_rows_delete)
	%FirstPage.pressed.connect(_go_to_page.bind(0))
	%PreviousPage.pressed.connect(_change_page.bind(-1))
	%NextPage.pressed.connect(_change_page.bind(1))
	%LastPage.pressed.connect(_go_to_last_page)
	%PageSize.item_selected.connect(_on_page_size_selected)
	%DeleteConfirmation.confirmed.connect(_confirm_rows_delete)
	_column_menu.id_pressed.connect(_on_column_toggled)
	_column_menu.hide_on_checkable_item_selection = false
	_table_view.inline_changes_changed.connect(_on_inline_changes_changed)
	_table_view.column_title_clicked.connect(_on_column_title_clicked)
	_table_view.item_selected.connect(_refresh_actions)
	_table_view.multi_selected.connect(_on_multi_selected)
	_insert_editor.inline_changes_changed.connect(_on_insert_changes_changed)
	_where_expression.changed.connect(_on_filter_changed)
	_where_expression.apply_requested.connect(_apply_filter)
	_where_expression.clear_requested.connect(_clear_filter)
	_refresh_actions()


func configure(
		target_registration: StringName,
		table: GDSQLTableDefinition,
		total_rows: int = 0,
) -> void:
	var source_changed := registration_name != target_registration \
			or table_name != table.name
	registration_name = target_registration
	table_name = table.name
	_table = table
	_catalog_total_rows = maxi(0, total_rows)
	if source_changed:
		_page_index = 0
		_applied_predicate = null
		_applied_filter_summary = ""
		_filter_dirty = false
		_where_expression.configure(table.columns)
	else:
		_where_expression.configure(table.columns, true)
	_configure_query_options(not source_changed)
	if _applied_predicate == null:
		_total_rows = _catalog_total_rows
	_page_index = clampi(_page_index, 0, _page_count() - 1)
	%Title.text = String(table.name)
	%Details.text = "%d columns · Primary key: %s" % [
		table.columns.size(),
		table.primary_key,
	]
	_update_pagination()
	_refresh_filter_actions()
	_refresh_actions()


func present_rows(result: GDSQLQueryResult, total_rows: int = -1) -> void:
	_presentation_revision += 1
	_close_insert_editor(false)
	if total_rows >= 0:
		_total_rows = total_rows
		var previous_page := _page_index
		_page_index = clampi(_page_index, 0, _page_count() - 1)
		if _page_index != previous_page:
			request_rows()
			return
	_records.clear()
	if result == null or not result.is_successful():
		_table_view.configure(_table, _table, _records, true)
		_table_view.clear()
		%Status.text = "Could not load table rows."
		_refresh_actions()
		return
	_records.assign(result.rows)
	for index in range(_records.size()):
		_records[index].set_value(
			ROW_NUMBER_COLUMN,
			_page_index * _page_size + index + 1,
		)
	_table_view.configure(_table, _build_view_table(), _records, true)
	_table_view.set_safe_mode(false)
	_render_table()
	%Status.text = (
			"No rows on this page."
			if _records.is_empty()
			else "Showing rows %d–%d." % [
				_page_index * _page_size + 1,
				_page_index * _page_size + _records.size(),
			]
	)
	_update_pagination()
	_refresh_actions()


func has_unsaved_changes() -> bool:
	return %InsertSection.visible or _table_view.has_pending_changes()


func request_rows() -> void:
	if has_unsaved_changes() and not _mutation_in_flight:
		%Status.text = "Save or discard changes before loading another page."
		return
	%Status.text = "Loading rows…"
	var count_query: GDSQLSelectQuerySpec
	if _applied_predicate != null:
		count_query = _build_select_query(true)
	rows_requested.emit(
		registration_name,
		table_name,
		_build_select_query(),
		count_query,
	)


func _is_scene_preview() -> bool:
	if not Engine.is_editor_hint():
		return false
	var edited_scene_root := EditorInterface.get_edited_scene_root()
	return edited_scene_root == self \
			or (edited_scene_root != null and edited_scene_root.is_ancestor_of(self))


func _open_model_assistant() -> void:
	if _table != null:
		model_assistant_requested.emit(registration_name, _table)


func _build_select_query(count_rows: bool = false) -> GDSQLSelectQuerySpec:
	var builder := GDSQLQuery.new(_table.database_name).select().from_table(table_name)
	if _applied_predicate != null:
		builder.where(_applied_predicate)
	if count_rows:
		builder.count(null, &"row_count")
	else:
		var projected_columns := _visible_columns.duplicate()
		if not projected_columns.has(_table.primary_key):
			projected_columns.append(_table.primary_key)
		builder.columns(projected_columns)
		if _order_column != &"":
			builder.order_by_column(_order_column, _order_direction)
		builder.limit(_page_size).offset(_page_index * _page_size)
	return builder.build()


func _build_view_table() -> GDSQLTableDefinition:
	var view := GDSQLTableDefinition.new(_table.name, _table.primary_key)
	view.database_name = _table.database_name
	view.add_column(GDSQLColumnDefinition.new(ROW_NUMBER_COLUMN, TYPE_INT, false))
	for column in _table.columns:
		if _visible_columns.has(column.name):
			view.add_column(column)
	return view


func _configure_query_options(preserve_state: bool) -> void:
	if not preserve_state:
		_visible_columns.clear()
		_order_column = &""
		_order_direction = GDSQLOrderClause.SortDirection.ASCENDING
	else:
		_visible_columns = _valid_visible_columns()
		if _table.get_column(_order_column) == null:
			_order_column = &""
	if _visible_columns.is_empty():
		for column in _table.columns:
			_visible_columns.append(column.name)
	_populate_columns()


func _valid_visible_columns() -> Array[StringName]:
	var valid: Array[StringName] = []
	for column in _table.columns:
		if _visible_columns.has(column.name):
			valid.append(column.name)
	return valid


func _populate_columns() -> void:
	_column_menu.clear()
	_column_menu.add_item("Show all", COLUMN_SELECT_ALL)
	_column_menu.add_separator()
	for column in _table.columns:
		_column_menu.add_check_item(String(column.name), _column_menu.item_count)
		var index := _column_menu.item_count - 1
		_column_menu.set_item_metadata(index, column.name)
		_column_menu.set_item_checked(index, _visible_columns.has(column.name))


func _on_column_toggled(id: int) -> void:
	if has_unsaved_changes():
		%Status.text = "Save or discard row changes before changing visible columns."
		return
	if id == COLUMN_SELECT_ALL:
		_visible_columns.clear()
		for column in _table.columns:
			_visible_columns.append(column.name)
	else:
		var index := _column_menu.get_item_index(id)
		if index < 0 or not _column_menu.is_item_checkable(index):
			return
		var column_name := StringName(_column_menu.get_item_metadata(index))
		if _visible_columns.has(column_name):
			if _visible_columns.size() == 1:
				%Status.text = "At least one column must remain visible."
				return
			_visible_columns.erase(column_name)
		else:
			_visible_columns.append(column_name)
	_populate_columns()
	_page_index = 0
	request_rows()


func _on_column_title_clicked(column_index: int, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_LEFT:
		return
	if column_index == 0:
		_column_menu.position = DisplayServer.mouse_get_position()
		_column_menu.popup()
		return
	if has_unsaved_changes():
		%Status.text = "Save or discard row changes before changing row order."
		return
	var view := _build_view_table()
	if column_index < 1 or column_index >= view.columns.size():
		return
	var selected_column := view.columns[column_index].name
	if selected_column != _order_column:
		_order_column = selected_column
		_order_direction = GDSQLOrderClause.SortDirection.ASCENDING
	elif _order_direction == GDSQLOrderClause.SortDirection.ASCENDING:
		_order_direction = GDSQLOrderClause.SortDirection.DESCENDING
	else:
		_order_column = &""
		_order_direction = GDSQLOrderClause.SortDirection.ASCENDING
	_decorate_table_headers()
	_page_index = 0
	request_rows()


func _render_table() -> void:
	_table_view.render_page(0, _records.size(), -1, _page_size)
	_decorate_table_headers()


func _decorate_table_headers() -> void:
	if _table == null or _table_view.columns < 1:
		return
	_table_view.set_column_title(0, "# ▾")
	_table_view.set_column_title_tooltip_text(
		0,
		"Row number · Click to choose visible columns",
	)
	_table_view.set_column_custom_minimum_width(0, 42)
	_table_view.set_column_expand(0, false)
	var view := _build_view_table()
	for index in range(1, view.columns.size()):
		var column := view.columns[index]
		var suffix := ""
		if column.name == _order_column:
			suffix = (
					" ▼"
					if _order_direction == GDSQLOrderClause.SortDirection.DESCENDING
					else " ▲"
			)
		_table_view.set_column_title(index, "%s%s" % [column.name, suffix])
		_table_view.set_column_title_tooltip_text(
			index,
			"%s · %s · Click to change row order"
			% [column.name, column.display_type_name()],
		)


func _apply_filter() -> void:
	if has_unsaved_changes():
		%Status.text = "Save or discard row changes before applying a filter."
		return
	var predicate_result := _where_expression.build_expression()
	if not predicate_result.is_successful():
		%Status.text = (
				predicate_result.diagnostics.entries[0].message
				if not predicate_result.diagnostics.entries.is_empty()
				else "The WHERE filter is invalid."
		)
		return
	_applied_predicate = predicate_result.get_value() as GDSQLQueryExpression
	_applied_filter_summary = _where_expression.get_summary().strip_edges()
	_filter_dirty = false
	_page_index = 0
	if _applied_predicate == null:
		_total_rows = _catalog_total_rows
	request_rows()
	_refresh_filter_actions()


func _clear_filter() -> void:
	if has_unsaved_changes():
		%Status.text = "Save or discard row changes before clearing the filter."
		return
	_where_expression.configure(_table.columns)
	_applied_predicate = null
	_applied_filter_summary = ""
	_filter_dirty = false
	_page_index = 0
	_total_rows = _catalog_total_rows
	request_rows()
	_refresh_filter_actions()


func _on_filter_changed() -> void:
	_filter_dirty = true
	_refresh_filter_actions()


func _refresh_filter_actions() -> void:
	if not is_node_ready():
		return
	var summary := (
			"All rows" if _applied_filter_summary.is_empty() else _applied_filter_summary
	)
	if _filter_dirty:
		summary += " · unapplied changes"
	_where_expression.set_header_actions_state(
		not _mutation_in_flight and _filter_dirty,
		not _mutation_in_flight and (_filter_dirty or _applied_predicate != null),
		summary,
	)


func _begin_insert() -> void:
	if _table == null:
		return
	if _table_view.has_pending_changes():
		%Status.text = "Save or discard edited rows before adding a row."
		return
	_table_view.deselect_all()
	_table_view.set_safe_mode(true)
	_render_table()
	_insert_editor.configure_insert_draft(_table, _table)
	%InsertSection.show()
	%Status.text = "Enter the new row, then save it from the action bar."
	_refresh_actions()


func _save_changes() -> void:
	if %InsertSection.visible:
		_save_insert()
		return
	if _table_view.has_validation_errors():
		%Status.text = "Correct the highlighted invalid values before saving."
		return
	var updates := _table_view.get_pending_updates()
	if updates.is_empty():
		return
	%Status.text = "Saving changes to %d row(s)…" % updates.size()
	var previous_revision := _presentation_revision
	_mutation_in_flight = true
	rows_update_requested.emit(registration_name, table_name, updates)
	_mutation_in_flight = false
	if _presentation_revision == previous_revision:
		%Status.text = "Could not save changes; pending edits were preserved."
	_refresh_actions()


func _save_insert() -> void:
	if _insert_editor.has_validation_errors():
		%Status.text = "Correct the highlighted invalid values before saving."
		return
	var conversion := _insert_editor.get_insert_values_result()
	if not bool(conversion.get("valid", false)):
		%Status.text = String(conversion.get("message", "Invalid row values."))
		return
	%Status.text = "Adding row…"
	var previous_revision := _presentation_revision
	_mutation_in_flight = true
	row_insert_requested.emit(
		registration_name,
		table_name,
		conversion.get("values", { }),
	)
	_mutation_in_flight = false
	if _presentation_revision == previous_revision:
		%Status.text = "Could not add the row; its values were preserved."
	_refresh_actions()


func _discard_changes() -> void:
	if %InsertSection.visible:
		_close_insert_editor()
		%Status.text = "New row discarded."
	else:
		_table_view.clear_pending_changes()
		_render_table()
		%Status.text = "Pending changes discarded."
	_refresh_actions()


func _close_insert_editor(restore_table: bool = true) -> void:
	var empty_records: Array[GDSQLRowRecord] = []
	_insert_editor.configure(null, null, empty_records, false)
	_insert_editor.clear()
	%InsertSection.hide()
	if restore_table and _table != null:
		_table_view.set_safe_mode(false)
		_render_table()


func _request_selected_rows_delete() -> void:
	if has_unsaved_changes():
		%Status.text = "Save or discard changes before deleting rows."
		return
	_pending_delete_keys = _table_view.get_selected_primary_keys()
	if _pending_delete_keys.is_empty():
		return
	%DeleteConfirmation.dialog_text = (
			"Delete %d selected row(s)? This operation is atomic."
			% _pending_delete_keys.size()
	)
	%DeleteConfirmation.popup_centered(Vector2i(440, 160))


func _confirm_rows_delete() -> void:
	if _pending_delete_keys.is_empty():
		return
	var keys := _pending_delete_keys.duplicate()
	_pending_delete_keys.clear()
	%Status.text = "Deleting %d row(s)…" % keys.size()
	var previous_revision := _presentation_revision
	_mutation_in_flight = true
	rows_delete_requested.emit(registration_name, table_name, keys)
	_mutation_in_flight = false
	if _presentation_revision == previous_revision:
		%Status.text = "Could not delete the selected rows."
	_refresh_actions()


func _on_inline_changes_changed(status: String) -> void:
	%Status.text = status
	_refresh_actions()


func _on_insert_changes_changed(status: String) -> void:
	%Status.text = status
	_refresh_actions()


func _on_multi_selected(_item: TreeItem, _column: int, _selected: bool) -> void:
	_refresh_actions()


func _refresh_actions() -> void:
	if not is_node_ready():
		return
	var inserting: bool = %InsertSection.visible
	var has_edits: bool = _table_view.has_pending_changes()
	var selected_count: int = _table_view.get_selected_primary_keys().size()
	%AddRow.disabled = _mutation_in_flight or _table == null or inserting or has_edits
	%SaveChanges.disabled = _mutation_in_flight or (not inserting and not has_edits)
	%DiscardChanges.disabled = _mutation_in_flight or (not inserting and not has_edits)
	%DeleteSelected.disabled = (
			_mutation_in_flight or inserting or has_edits or selected_count == 0
	)
	%DeleteSelected.text = (
			"Delete Selected (%d)" % selected_count
			if selected_count > 0
			else "Delete Selected"
	)
	_refresh_filter_actions()


func _change_page(delta: int) -> void:
	_go_to_page(_page_index + delta)


func _go_to_last_page() -> void:
	_go_to_page(_page_count() - 1)


func _go_to_page(index: int) -> void:
	var target := clampi(index, 0, _page_count() - 1)
	if target == _page_index:
		return
	if has_unsaved_changes():
		%Status.text = "Save or discard changes before changing pages."
		return
	_page_index = target
	_update_pagination()
	request_rows()


func _on_page_size_selected(index: int) -> void:
	if index < 0 or index >= PAGE_SIZES.size():
		return
	if has_unsaved_changes():
		%PageSize.select(PAGE_SIZES.find(_page_size))
		%Status.text = "Save or discard changes before changing page size."
		return
	var first_row := _page_index * _page_size
	_page_size = PAGE_SIZES[index]
	_page_index = floori(float(first_row) / float(_page_size))
	_update_pagination()
	request_rows()


func _page_count() -> int:
	return maxi(1, ceili(float(_total_rows) / float(_page_size)))


func _update_pagination() -> void:
	if not is_node_ready():
		return
	var pages := _page_count()
	%PageStatus.text = "Page %d of %d · %d rows" % [
		_page_index + 1,
		pages,
		_total_rows,
	]
	%FirstPage.disabled = _page_index <= 0
	%PreviousPage.disabled = _page_index <= 0
	%NextPage.disabled = _page_index >= pages - 1
	%LastPage.disabled = _page_index >= pages - 1
