@tool
extends GraphNode
## SELECT operation presentation backed by lightweight schema inspections.

signal source_changed(
		registration_name: StringName,
		database_name: StringName,
		table_name: StringName,
)
signal query_changed
signal query_activated
signal remove_requested

const VARIANT_FIELD := preload(
	"res://addons/gdsql/editor/workspace/components/gdsql_editor_variant_value_field.gd"
)
const ROW_SET_PORT_TYPE := 0
const ROW_SET_COLOR := Color("62b5e5")
const CONTEXT_REMOVE := 1
const COLUMN_SELECT_ALL := 10_000
const COLUMN_CLEAR := 10_001
const WHERE_IS_NULL := 100
const WHERE_IS_NOT_NULL := 101

var _inspections: Array[GDSQLDatabaseInspection] = []
var _column_count := 0
var _where_value_field: Control

@onready var _database: OptionButton = %Database
@onready var _table: OptionButton = %Table
@onready var _columns: MenuButton = %Columns
@onready var _use_where: CheckButton = %UseWhere
@onready var _where_column: OptionButton = %WhereColumn
@onready var _where_operator: OptionButton = %WhereOperator
@onready var _where_value_host: Control = %WhereValueHost
@onready var _selection_summary: Label = %SelectionSummary
@onready var _validation_status: Label = %ValidationStatus
@onready var _query: GDSQLEditorActionButton = %Query
@onready var _context_menu: PopupMenu = %NodeContextMenu


func _ready() -> void:
	_database.item_selected.connect(_on_database_selected)
	_table.item_selected.connect(_on_table_selected)
	_columns.get_popup().id_pressed.connect(_on_column_toggled)
	_columns.get_popup().hide_on_checkable_item_selection = false
	_use_where.toggled.connect(_on_where_toggled)
	_where_column.item_selected.connect(_on_where_column_selected)
	_where_operator.item_selected.connect(_on_where_operator_selected)
	_query.pressed.connect(query_activated.emit)
	gui_input.connect(_on_node_gui_input)
	_context_menu.add_item("Remove node", CONTEXT_REMOVE)
	_context_menu.id_pressed.connect(_on_context_action)
	_populate_where_operators()
	set_slot(
		%OutputRow.get_index(),
		false,
		ROW_SET_PORT_TYPE,
		ROW_SET_COLOR,
		true,
		ROW_SET_PORT_TYPE,
		ROW_SET_COLOR,
	)
	_update_where_controls()


func configure_query_action(
		hub: GDSQLEditorActionHub,
		definition: GDSQLEditorActionDefinition,
) -> void:
	_query.configure(hub, definition)


func configure(
		inspections: Array[GDSQLDatabaseInspection],
		selected_registration: StringName,
		selected_table: StringName,
) -> void:
	var previous_registration := get_selected_registration()
	var previous_table := get_selected_table()
	var previous_columns := get_selected_columns()
	var previous_where := _capture_where_state()
	_inspections.clear()
	for inspection in inspections:
		if inspection != null and inspection.registration != null:
			_inspections.append(inspection)
	_inspections.sort_custom(_sort_inspections)
	_populate_databases(selected_registration)
	_populate_tables(selected_table)
	var same_source := (
		previous_registration == get_selected_registration()
		and previous_table == get_selected_table()
	)
	_populate_columns(previous_columns, same_source)
	_populate_where_columns(
		StringName(previous_where.get("column", &"")) if same_source else &"",
	)
	_restore_where_state(previous_where if same_source else { })
	_update_selection()


func get_selected_registration() -> StringName:
	if _database == null or _database.selected < 0:
		return &""
	return StringName(_database.get_item_metadata(_database.selected))


func get_selected_database() -> StringName:
	var inspection := _get_selected_inspection()
	return inspection.registration.database_name if inspection != null else &""


func get_selected_table() -> StringName:
	if _table == null or _table.selected < 0:
		return &""
	return StringName(_table.get_item_metadata(_table.selected))


func get_selected_columns() -> Array[StringName]:
	var selected: Array[StringName] = []
	if _columns == null:
		return selected
	var popup := _columns.get_popup()
	for index in range(popup.item_count):
		if popup.is_item_checkable(index) and popup.is_item_checked(index):
			selected.append(StringName(popup.get_item_metadata(index)))
	return selected


func are_all_columns_selected() -> bool:
	return _column_count > 0 and get_selected_columns().size() == _column_count


func build_predicate() -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if not _use_where.button_pressed:
		result.value = null
		return result
	var column := _get_selected_where_column()
	if column == null:
		return _predicate_error(
			&"GDSQL_QUERY_GRAPH_WHERE_COLUMN_REQUIRED",
			"Choose a column for the WHERE expression.",
		)
	var expression := GDSQLExpr.column(column.name)
	var operator_id := _get_where_operator_id()
	if operator_id == WHERE_IS_NULL:
		result.value = expression.is_null()
		return result
	if operator_id == WHERE_IS_NOT_NULL:
		result.value = expression.is_not_null()
		return result
	if _where_value_field == null:
		return _predicate_error(
			&"GDSQL_QUERY_GRAPH_WHERE_VALUE_REQUIRED",
			"Enter a value for the WHERE comparison.",
		)
	var converted: Dictionary = _where_value_field.call("get_value_result")
	if not converted.valid:
		return _predicate_error(
			&"GDSQL_QUERY_GRAPH_WHERE_VALUE_INVALID",
			"WHERE value for '%s' must be %s." % [
				column.name,
				type_string(column.data_type),
			],
		)
	match operator_id:
		GDSQLComparisonExpression.ComparisonOperator.EQUAL:
			result.value = expression.equals(converted.value)
		GDSQLComparisonExpression.ComparisonOperator.NOT_EQUAL:
			result.value = expression.not_equals(converted.value)
		GDSQLComparisonExpression.ComparisonOperator.GREATER_THAN:
			result.value = expression.greater_than(converted.value)
		GDSQLComparisonExpression.ComparisonOperator.GREATER_THAN_OR_EQUAL:
			result.value = expression.greater_than_or_equal(converted.value)
		GDSQLComparisonExpression.ComparisonOperator.LESS_THAN:
			result.value = expression.less_than(converted.value)
		GDSQLComparisonExpression.ComparisonOperator.LESS_THAN_OR_EQUAL:
			result.value = expression.less_than_or_equal(converted.value)
		_:
			return _predicate_error(
				&"GDSQL_QUERY_GRAPH_WHERE_OPERATOR_UNSUPPORTED",
				"The selected WHERE operator is not supported.",
			)
	return result


func _populate_databases(selected_registration: StringName) -> void:
	_database.clear()
	for inspection in _inspections:
		var registration := inspection.registration
		_database.add_item(String(registration.database_name))
		var item_index := _database.item_count - 1
		_database.set_item_metadata(item_index, registration.name)
		_database.set_item_tooltip(
			item_index,
			"Location: %s\nRuntime storage: %s" % [
				registration.data_root,
				GDSQLStorageBackendIds.get_display_name(
					registration.storage_backend_id,
				),
			],
		)
		if registration.name == selected_registration:
			_database.select(item_index)
	_database.disabled = _database.item_count == 0
	if _database.item_count > 0 and _database.selected < 0:
		_database.select(0)


func _populate_tables(selected_table: StringName = &"") -> void:
	_table.clear()
	var inspection := _get_selected_inspection()
	if inspection == null:
		_table.disabled = true
		return
	var tables := inspection.tables.duplicate()
	tables.sort_custom(_sort_tables)
	for table_inspection in tables:
		_table.add_item(String(table_inspection.name))
		var item_index := _table.item_count - 1
		_table.set_item_metadata(item_index, table_inspection.name)
		_table.set_item_tooltip(
			item_index,
			"%d columns · %d rows" % [
				table_inspection.column_count,
				table_inspection.row_count,
			],
		)
		if table_inspection.name == selected_table:
			_table.select(item_index)
	_table.disabled = _table.item_count == 0
	if _table.item_count > 0 and _table.selected < 0:
		_table.select(0)


func _populate_columns(
		selected_columns: Array[StringName] = [],
		preserve_selection: bool = false,
) -> void:
	var popup := _columns.get_popup()
	popup.clear()
	_column_count = 0
	var table_inspection := _get_selected_table_inspection()
	if table_inspection == null:
		_columns.disabled = true
		_columns.text = "No columns"
		return
	_column_count = table_inspection.columns.size()
	if _column_count > 0:
		popup.add_item("Select all", COLUMN_SELECT_ALL)
		popup.add_item("Clear", COLUMN_CLEAR)
		popup.add_separator()
	for column in table_inspection.columns:
		popup.add_check_item(String(column.name), popup.item_count)
		var index := popup.item_count - 1
		popup.set_item_metadata(index, column.name)
		popup.set_item_checked(
			index,
			column.name in selected_columns if preserve_selection else true,
		)
	_columns.disabled = _column_count == 0
	_update_columns_label()


func _populate_where_columns(selected_column: StringName = &"") -> void:
	_where_column.clear()
	var table_inspection := _get_selected_table_inspection()
	if table_inspection == null:
		return
	for column in table_inspection.columns:
		_where_column.add_item(String(column.name))
		var index := _where_column.item_count - 1
		_where_column.set_item_metadata(index, column.name)
		if column.name == selected_column:
			_where_column.select(index)
	if _where_column.item_count > 0 and _where_column.selected < 0:
		_where_column.select(0)


func _populate_where_operators() -> void:
	var operators: Array = [
		["Equals", GDSQLComparisonExpression.ComparisonOperator.EQUAL],
		["Not equal", GDSQLComparisonExpression.ComparisonOperator.NOT_EQUAL],
		["Greater than", GDSQLComparisonExpression.ComparisonOperator.GREATER_THAN],
		["Greater or equal", GDSQLComparisonExpression.ComparisonOperator.GREATER_THAN_OR_EQUAL],
		["Less than", GDSQLComparisonExpression.ComparisonOperator.LESS_THAN],
		["Less or equal", GDSQLComparisonExpression.ComparisonOperator.LESS_THAN_OR_EQUAL],
		["Is null", WHERE_IS_NULL],
		["Is not null", WHERE_IS_NOT_NULL],
	]
	for definition in operators:
		_where_operator.add_item(definition[0])
		_where_operator.set_item_metadata(
			_where_operator.item_count - 1,
			definition[1],
		)


func _restore_where_state(state: Dictionary) -> void:
	_use_where.button_pressed = bool(state.get("enabled", false))
	var operator_id := int(
		state.get(
			"operator",
			GDSQLComparisonExpression.ComparisonOperator.EQUAL,
		),
	)
	for index in range(_where_operator.item_count):
		if int(_where_operator.get_item_metadata(index)) == operator_id:
			_where_operator.select(index)
			break
	_rebuild_where_value(state)
	_update_where_controls()


func _capture_where_state() -> Dictionary:
	var state := {
		"enabled": _use_where != null and _use_where.button_pressed,
		"column": (
			StringName(_where_column.get_item_metadata(_where_column.selected))
			if _where_column != null and _where_column.selected >= 0
			else &""
		),
		"operator": _get_where_operator_id(),
	}
	if _where_value_field != null:
		var converted: Dictionary = _where_value_field.call("get_value_result")
		if converted.valid:
			state["has_value"] = true
			state["value"] = converted.value
	return state


func _rebuild_where_value(state: Dictionary = { }) -> void:
	for child in _where_value_host.get_children():
		_where_value_host.remove_child(child)
		child.queue_free()
	_where_value_field = null
	if _get_where_operator_id() in [WHERE_IS_NULL, WHERE_IS_NOT_NULL]:
		return
	var column := _get_selected_where_column()
	if column == null:
		return
	_where_value_field = VARIANT_FIELD.new() as Control
	_where_value_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_where_value_host.add_child(_where_value_field)
	_where_value_field.call(
		"configure",
		column.data_type,
		state.get("value") if state.get("has_value", false) else _default_value(column.data_type),
		false,
		true,
	)
	_where_value_field.connect("changed", _on_where_value_changed)


func _get_selected_inspection() -> GDSQLDatabaseInspection:
	var registration_name := get_selected_registration()
	for inspection in _inspections:
		if inspection.registration.name == registration_name:
			return inspection
	return null


func _get_selected_table_inspection() -> GDSQLTableInspection:
	var inspection := _get_selected_inspection()
	return inspection.get_table(get_selected_table()) if inspection != null else null


func _get_selected_where_column() -> GDSQLColumnDefinition:
	if _where_column.selected < 0:
		return null
	var table_inspection := _get_selected_table_inspection()
	if table_inspection == null:
		return null
	return table_inspection.get_column(
		StringName(_where_column.get_item_metadata(_where_column.selected)),
	)


func _get_where_operator_id() -> int:
	if _where_operator == null or _where_operator.selected < 0:
		return GDSQLComparisonExpression.ComparisonOperator.EQUAL
	return int(_where_operator.get_item_metadata(_where_operator.selected))


func _update_selection() -> void:
	var database_name := get_selected_database()
	var table_name := get_selected_table()
	if database_name == &"":
		_selection_summary.text = "No database is available."
	elif table_name == &"":
		_selection_summary.text = "No table is available in %s." % database_name
	else:
		var projection := _projection_summary()
		_selection_summary.text = "SELECT %s FROM %s.%s%s" % [
			projection,
			database_name,
			table_name,
			_where_summary(),
		]
	source_changed.emit(
		get_selected_registration(),
		database_name,
		table_name,
	)
	query_changed.emit()
	_update_where_validation()


func _projection_summary() -> String:
	if are_all_columns_selected():
		return "*"
	var names: Array[String] = []
	for column_name in get_selected_columns():
		names.append(String(column_name))
	return ", ".join(names) if not names.is_empty() else "<no columns>"


func _where_summary() -> String:
	if not _use_where.button_pressed or _where_column.selected < 0:
		return ""
	return " WHERE %s %s" % [
		_where_column.get_item_text(_where_column.selected),
		_where_operator.get_item_text(_where_operator.selected),
	]


func _update_columns_label() -> void:
	var total := _column_count
	var selected := get_selected_columns().size()
	if total == 0:
		_columns.text = "No columns"
	elif selected == total:
		_columns.text = "All columns"
	elif selected == 0:
		_columns.text = "No columns"
	else:
		_columns.text = "%d of %d columns" % [selected, total]


func _update_where_controls() -> void:
	var enabled := _use_where.button_pressed and _where_column.item_count > 0
	_where_column.disabled = not enabled
	_where_operator.disabled = not enabled
	_where_value_host.visible = enabled \
			and _get_where_operator_id() not in [WHERE_IS_NULL, WHERE_IS_NOT_NULL]
	_update_where_validation()


func _update_where_validation() -> void:
	_validation_status.visible = false
	_validation_status.text = ""
	if not _use_where.button_pressed:
		return
	var predicate_result := build_predicate()
	if predicate_result.is_successful():
		return
	if not predicate_result.diagnostics.entries.is_empty():
		_validation_status.text = predicate_result.diagnostics.entries[0].message
		_validation_status.visible = true


func _on_database_selected(_index: int) -> void:
	_populate_tables()
	_populate_columns()
	_populate_where_columns()
	_restore_where_state({ })
	_update_selection()


func _on_table_selected(_index: int) -> void:
	_populate_columns()
	_populate_where_columns()
	_restore_where_state({ })
	_update_selection()


func _on_column_toggled(id: int) -> void:
	var popup := _columns.get_popup()
	if id in [COLUMN_SELECT_ALL, COLUMN_CLEAR]:
		var checked := id == COLUMN_SELECT_ALL
		for item_index in range(popup.item_count):
			if popup.is_item_checkable(item_index):
				popup.set_item_checked(item_index, checked)
		_update_columns_label()
		_update_selection()
		return
	var index := popup.get_item_index(id)
	if index < 0 or not popup.is_item_checkable(index):
		return
	popup.set_item_checked(index, not popup.is_item_checked(index))
	_update_columns_label()
	_update_selection()


func _on_where_toggled(_enabled: bool) -> void:
	_update_where_controls()
	_update_selection()


func _on_where_column_selected(_index: int) -> void:
	_rebuild_where_value()
	_update_selection()


func _on_where_operator_selected(_index: int) -> void:
	_rebuild_where_value()
	_update_where_controls()
	_update_selection()


func _on_where_value_changed() -> void:
	_update_where_validation()
	query_changed.emit()


func _on_node_gui_input(event: InputEvent) -> void:
	var mouse_event := event as InputEventMouseButton
	if mouse_event == null \
			or mouse_event.button_index != MOUSE_BUTTON_RIGHT \
			or not mouse_event.pressed:
		return
	query_activated.emit()
	_context_menu.position = DisplayServer.mouse_get_position()
	_context_menu.popup()
	accept_event()


func _on_context_action(id: int) -> void:
	if id == CONTEXT_REMOVE:
		remove_requested.emit()


func _predicate_error(code: StringName, message: String) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result


func _default_value(type: Variant.Type) -> Variant:
	match type:
		TYPE_BOOL:
			return false
		TYPE_INT:
			return 0
		TYPE_FLOAT:
			return 0.0
		TYPE_STRING:
			return ""
		TYPE_STRING_NAME:
			return &""
		TYPE_NODE_PATH:
			return NodePath()
	return null


func _sort_inspections(
		left: GDSQLDatabaseInspection,
		right: GDSQLDatabaseInspection,
) -> bool:
	return String(left.registration.database_name) \
			< String(right.registration.database_name)


func _sort_tables(
		left: GDSQLTableInspection,
		right: GDSQLTableInspection,
) -> bool:
	return String(left.name) < String(right.name)
