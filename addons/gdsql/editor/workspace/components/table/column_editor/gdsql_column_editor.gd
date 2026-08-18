@tool
class_name GDSQLEditorColumnEditor
extends VBoxContainer
## Scene-backed, scrollable table-column editor.

signal changed

const ROW_SCENE := preload(
	"res://addons/gdsql/editor/workspace/components/table/column_editor/gdsql_column_editor_row.tscn"
)

var _drafts: Array[GDSQLEditorColumnDraft] = []
var _baseline_drafts: Array[GDSQLEditorColumnDraft] = []
var _rows: Array[GDSQLEditorColumnEditorRow] = []

@onready var _column_order: OptionButton = %ColumnOrder
@onready var _move_up: Button = %MoveUp
@onready var _move_down: Button = %MoveDown
@onready var _rows_host: VBoxContainer = %Rows
@onready var _preview_row: GDSQLEditorColumnEditorRow = %PreviewRow


func _ready() -> void:
	_preview_row.changed.connect(_on_row_changed)
	_column_order.item_selected.connect(_update_order_buttons.unbind(1))
	_move_up.pressed.connect(_move_selected_column.bind(-1))
	_move_down.pressed.connect(_move_selected_column.bind(1))
	_refresh_order_controls()


func configure_new_table() -> void:
	var draft := GDSQLEditorColumnDraft.create_new(true)
	_drafts.assign([draft])
	_baseline_drafts.assign([draft])
	_render_rows()


func configure_existing(table: GDSQLTableDefinition) -> void:
	_drafts.clear()
	_baseline_drafts.clear()
	for column in table.columns:
		var draft := GDSQLEditorColumnDraft.from_definition(
			column,
			column.name == table.primary_key,
		)
		_drafts.append(draft)
		_baseline_drafts.append(draft)
	_render_rows()


func add_draft_column() -> void:
	var draft := GDSQLEditorColumnDraft.create_new()
	_drafts.append(draft)
	_baseline_drafts.append(draft)
	var row := _create_row(draft)
	_refresh_order_controls(_drafts.size() - 1)
	row.focus_name.call_deferred()
	changed.emit()


func build_definitions() -> Array[GDSQLColumnDefinition]:
	_sync_rows()
	var definitions: Array[GDSQLColumnDefinition] = []
	for draft in _drafts:
		if not draft.remove:
			definitions.append(draft.build_definition())
	return definitions


func build_alterations() -> Array[GDSQLTableAlteration]:
	_sync_rows()
	var alterations: Array[GDSQLTableAlteration] = []
	for draft in _drafts:
		alterations.append_array(draft.build_alterations())
	var desired_order := _active_column_names(_drafts)
	if desired_order != _active_column_names(_baseline_drafts):
		alterations.append(GDSQLTableAlteration.reorder_columns(desired_order))
	return alterations


func get_validation_errors(primary_key: StringName) -> Array[String]:
	_sync_rows()
	var errors: Array[String] = []
	var names: Dictionary[StringName, bool] = { }
	var auto_increment_columns := 0
	for draft in _drafts:
		if draft.remove:
			continue
		errors.append_array(draft.get_validation_errors())
		var column_name := draft.get_column_name()
		if names.has(column_name):
			errors.append("Column '%s' is declared more than once." % column_name)
		names[column_name] = true
		if draft.auto_increment:
			auto_increment_columns += 1
	if names.is_empty():
		errors.append("A table requires at least one column.")
	if primary_key == &"" or not names.has(primary_key):
		errors.append("Primary key '%s' must reference a declared column." % primary_key)
	if auto_increment_columns > 1:
		errors.append("Only one auto-increment column is supported.")
	elif auto_increment_columns == 1:
		for draft in _drafts:
			if not draft.remove and draft.auto_increment \
					and draft.get_column_name() != primary_key:
				errors.append("Auto-increment is supported only on the primary key.")
	return errors


func has_column(column_name: StringName) -> bool:
	for draft in _drafts:
		if not draft.remove and draft.get_column_name() == column_name:
			return true
	return false


func _render_rows() -> void:
	for row in _rows:
		if row != _preview_row:
			_rows_host.remove_child(row)
			row.queue_free()
	_rows.clear()
	if _drafts.is_empty():
		_preview_row.hide()
		return
	_preview_row.show()
	_preview_row.configure(_drafts[0])
	_rows.append(_preview_row)
	for index in range(1, _drafts.size()):
		_create_row(_drafts[index])
	_refresh_order_controls()


func _create_row(draft: GDSQLEditorColumnDraft) -> GDSQLEditorColumnEditorRow:
	var row := ROW_SCENE.instantiate() as GDSQLEditorColumnEditorRow
	_rows_host.add_child(row)
	row.configure(draft)
	row.changed.connect(_on_row_changed)
	_rows.append(row)
	return row


func _sync_rows() -> void:
	for row in _rows:
		row.sync_default_value()


func _active_column_names(drafts: Array[GDSQLEditorColumnDraft]) -> Array[StringName]:
	var names: Array[StringName] = []
	for draft in drafts:
		if not draft.remove:
			names.append(draft.get_column_name())
	return names


func _refresh_order_controls(selected_index: int = -1) -> void:
	if selected_index < 0:
		selected_index = _column_order.selected
	_column_order.clear()
	for draft in _drafts:
		var label := draft.name.strip_edges()
		_column_order.add_item(label if not label.is_empty() else "Unnamed column")
	if not _drafts.is_empty():
		_column_order.select(clampi(selected_index, 0, _drafts.size() - 1))
	_update_order_buttons()


func _update_order_buttons() -> void:
	var index := _column_order.selected
	_move_up.disabled = index <= 0
	_move_down.disabled = index < 0 or index >= _drafts.size() - 1


func _move_selected_column(direction: int) -> void:
	var index := _column_order.selected
	if index < 0:
		return
	var target := clampi(index + direction, 0, _drafts.size() - 1)
	if index == target:
		return
	var draft: GDSQLEditorColumnDraft = _drafts[index]
	var row: GDSQLEditorColumnEditorRow = _rows[index]
	_drafts.remove_at(index)
	_rows.remove_at(index)
	_drafts.insert(target, draft)
	_rows.insert(target, row)
	_rows_host.move_child(row, target)
	_refresh_order_controls(target)
	changed.emit()


func _on_row_changed() -> void:
	_refresh_order_controls()
	changed.emit()
