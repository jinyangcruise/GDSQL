@tool
extends MarginContainer
## Data-only table document. Schema changes remain in the database document.

signal rows_requested(registration_name: StringName, table_name: StringName)
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

const DATA_ROW_SCENE := preload(
	"res://addons/gdsql/editor/workspace/components/table/gdsql_table_data_row.tscn"
)

var registration_name: StringName
var table_name: StringName
var _table: GDSQLTableDefinition
var _pending_delete_key: Variant


func _ready() -> void:
	%Refresh.pressed.connect(_request_rows)
	%AddRow.pressed.connect(_add_empty_row)
	%DeleteConfirmation.confirmed.connect(_confirm_row_delete)


func configure(
		target_registration: StringName,
		table: GDSQLTableDefinition,
) -> void:
	registration_name = target_registration
	table_name = table.name
	_table = table
	%Title.text = String(table.name)
	%Details.text = "%d columns · Primary key: %s" % [
		table.columns.size(),
		table.primary_key,
	]
	_render_header()


func present_rows(result: GDSQLQueryResult) -> void:
	for child in %DataRows.get_children():
		%DataRows.remove_child(child)
		child.queue_free()
	if result == null or not result.is_successful():
		%Status.text = "Could not load table rows."
		return
	for record in result.rows:
		_add_data_row(record)
	%Status.text = (
			"No rows."
			if result.rows.is_empty()
			else "%d row(s) loaded." % result.rows.size()
	)


func _render_header() -> void:
	for child in %Header.get_children():
		%Header.remove_child(child)
		child.queue_free()
	for column in _table.columns:
		var label := Label.new()
		label.custom_minimum_size = Vector2(120, 0)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text = "%s\n%s" % [
			column.name,
			column.display_type_name(),
		]
		label.tooltip_text = _column_capabilities(column)
		%Header.add_child(label)
	var actions := Control.new()
	actions.custom_minimum_size = Vector2(126, 0)
	%Header.add_child(actions)


func _column_capabilities(column: GDSQLColumnDefinition) -> String:
	var capabilities: Array[String] = [column.display_type_name()]
	capabilities.append("nullable" if column.nullable else "required")
	if column.name == _table.primary_key:
		capabilities.append("primary key")
	if column.unique:
		capabilities.append("unique")
	if column.auto_increment:
		capabilities.append("auto increment")
	if column.has_default():
		capabilities.append("default: %s" % var_to_str(column.get_default_value()))
	if column.generation != GDSQLColumnDefinition.Generation.NONE:
		capabilities.append(
			String(GDSQLColumnDefinition.Generation.keys()[column.generation]),
		)
	return " · ".join(capabilities)


func _request_rows() -> void:
	%Status.text = "Loading rows…"
	rows_requested.emit(registration_name, table_name)


func _add_empty_row() -> void:
	_add_data_row(null)


func _add_data_row(record: GDSQLRowRecord) -> void:
	var container := HBoxContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_theme_constant_override("separation", 6)
	%DataRows.add_child(container)
	var row := DATA_ROW_SCENE.instantiate() as Control
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_child(row)
	var save := Button.new()
	save.text = "Save"
	save.custom_minimum_size = Vector2(60, 0)
	save.pressed.connect(_save_data_row.bind(row, record))
	container.add_child(save)
	var remove := Button.new()
	remove.text = "Delete" if record != null else "Discard"
	remove.custom_minimum_size = Vector2(60, 0)
	remove.pressed.connect(_request_row_delete.bind(container, row, record))
	container.add_child(remove)
	row.call("configure", _table, record)


func _save_data_row(row: Control, source: GDSQLRowRecord) -> void:
	if not bool(row.call("is_dirty")):
		return
	var conversion: Dictionary = row.call("get_values_result")
	if not bool(conversion.get("valid", false)):
		row.call("set_status", String(conversion.get("message", "Invalid row values.")))
		return
	row.call("set_status", "")
	if source == null:
		row_insert_requested.emit(
			registration_name,
			table_name,
			conversion.get("values", { }),
		)
	else:
		row_update_requested.emit(
			registration_name,
			table_name,
			row.call("get_original_primary_key"),
			conversion.get("values", { }),
		)


func _request_row_delete(
		container: HBoxContainer,
		row: Control,
		source: GDSQLRowRecord,
) -> void:
	if source == null:
		%DataRows.remove_child(container)
		container.queue_free()
		return
	_pending_delete_key = row.call("get_original_primary_key")
	%DeleteConfirmation.dialog_text = (
			"Delete the row whose primary key is %s?" % var_to_str(_pending_delete_key)
	)
	%DeleteConfirmation.popup_centered(Vector2i(420, 160))


func _confirm_row_delete() -> void:
	row_delete_requested.emit(registration_name, table_name, _pending_delete_key)
