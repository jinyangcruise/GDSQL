@tool
class_name GDSQLQueryTableResultNode
extends GDSQLQueryGraphNode
## Reusable tabular presentation for a graph query result.
##
## It emits row mutation intents and derives editing capabilities from the
## returned schema. It never executes queries or accesses storage directly.

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

var _registration_name: StringName
var _table: GDSQLTableDefinition
var _view_table: GDSQLTableDefinition
var _can_add_rows := false
var _can_edit_rows := false
var _dirty_rows: Dictionary[Control, bool] = { }

@onready var _title: Label = %ResultTitle
@onready var _details: Label = %Details
@onready var _status: Label = %Status
@onready var _header: HBoxContainer = %Header
@onready var _data_rows: VBoxContainer = %DataRows
@onready var _add_row: GDSQLEditorActionButton = %AddRow


func _ready() -> void:
	super._ready()
	set_slot(0, true, ROW_SET_PORT_TYPE, ROW_SET_COLOR, false, ROW_SET_PORT_TYPE, ROW_SET_COLOR)


func configure_action(hub: GDSQLEditorActionHub, definition: GDSQLEditorActionDefinition) -> void:
	_add_row.configure(hub, definition)


func present(
	registration_name: StringName,
	table: GDSQLTableDefinition,
	result: GDSQLQueryResult,
) -> void:
	_registration_name = registration_name
	_table = table
	_clear_rows()
	if result == null or not result.is_successful():
		_view_table = null
		_can_add_rows = false
		_can_edit_rows = false
		_title.text = "QUERY RESULT"
		_details.text = "The query did not return an editable table."
		_status.text = "Query failed. See the activity log for diagnostics."
		_render_header()
		_emit_capabilities()
		return
	if table == null:
		_view_table = null
		_can_add_rows = false
		_can_edit_rows = false
		_title.text = "MUTATION RESULT"
		_details.text = "%d row(s) affected." % result.get_affected_rows()
		_status.text = "Mutation completed successfully."
		_render_header()
		_emit_capabilities()
		return
	_view_table = _build_view_table(table, result.schema)
	_can_add_rows = _has_all_columns(table, _view_table)
	_can_edit_rows = (table.primary_key != &"" and _view_table.has_column(table.primary_key))
	_title.text = "QUERY RESULT · %s" % table.name
	_details.text = _capability_summary(result.rows.size())
	_render_header()
	for record in result.rows:
		_add_data_row(record)
	_status.text = (
		"No rows returned."
		if result.rows.is_empty()
		else "%d row(s) returned." % result.rows.size()
	)
	_emit_capabilities()


func can_add_rows() -> bool:
	return _can_add_rows


func has_dirty_rows() -> bool:
	return not _dirty_rows.is_empty()


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
	var row := _add_data_row(null)
	result.value = row
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


func _render_header() -> void:
	for child in _header.get_children():
		_header.remove_child(child)
		child.queue_free()
	if _view_table == null:
		return
	for column in _view_table.columns:
		var label := Label.new()
		label.custom_minimum_size = Vector2(190, 0)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text = "%s (%s)" % [column.name, type_string(column.data_type)]
		_header.add_child(label)
	var actions := Control.new()
	actions.custom_minimum_size = Vector2(126, 0)
	_header.add_child(actions)


func _add_data_row(record: GDSQLRowRecord) -> Control:
	var row := DATA_ROW_SCENE.instantiate() as Control
	_data_rows.add_child(row)
	row.connect("save_requested", _on_row_save.bind(record))
	row.connect("delete_requested", _on_row_delete)
	row.connect("discard_requested", _discard_row)
	row.connect("dirty_changed", _on_row_dirty_changed)
	row.call("configure", _view_table, record, _can_edit_rows or record == null)
	return row


func _clear_rows() -> void:
	_dirty_rows.clear()
	for child in _data_rows.get_children():
		_data_rows.remove_child(child)
		child.queue_free()


func _on_row_save(
	original_primary_key: Variant,
	values: Dictionary,
	source: GDSQLRowRecord,
) -> void:
	if source == null:
		row_insert_requested.emit(_registration_name, _table.name, values)
	else:
		row_update_requested.emit(_registration_name, _table.name, original_primary_key, values)


func _on_row_delete(primary_key: Variant) -> void:
	row_delete_requested.emit(_registration_name, _table.name, primary_key)


func _discard_row(row: Control) -> void:
	_dirty_rows.erase(row)
	_data_rows.remove_child(row)
	row.queue_free()
	_emit_capabilities()


func _on_row_dirty_changed(row: Control, dirty: bool) -> void:
	if dirty:
		_dirty_rows[row] = true
	else:
		_dirty_rows.erase(row)
	_status.text = (
		"%d unsaved row(s)." % _dirty_rows.size()
		if not _dirty_rows.is_empty()
		else _status.text
	)
	_emit_capabilities()


func _emit_capabilities() -> void:
	capabilities_changed.emit(_can_add_rows, has_dirty_rows())
