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


func _ready() -> void:
	%Refresh.pressed.connect(_request_rows)
	%AddRow.pressed.connect(_add_empty_row)


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
			type_string(column.data_type),
		]
		label.tooltip_text = _column_capabilities(column)
		%Header.add_child(label)
	var actions := Control.new()
	actions.custom_minimum_size = Vector2(126, 0)
	%Header.add_child(actions)


func _column_capabilities(column: GDSQLColumnDefinition) -> String:
	var capabilities: Array[String] = [type_string(column.data_type)]
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
	var row := DATA_ROW_SCENE.instantiate() as Control
	%DataRows.add_child(row)
	row.connect("save_requested", _on_row_save.bind(record))
	row.connect("delete_requested", _on_row_delete)
	row.connect("discard_requested", _discard_row)
	row.call("configure", _table, record)


func _on_row_save(
		original_primary_key: Variant,
		values: Dictionary,
		source: GDSQLRowRecord,
) -> void:
	if source == null:
		row_insert_requested.emit(registration_name, table_name, values)
	else:
		row_update_requested.emit(
			registration_name,
			table_name,
			original_primary_key,
			values,
		)


func _on_row_delete(primary_key: Variant) -> void:
	row_delete_requested.emit(registration_name, table_name, primary_key)


func _discard_row(row: Control) -> void:
	%DataRows.remove_child(row)
	row.queue_free()
