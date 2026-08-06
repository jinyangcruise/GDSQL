@tool
class_name GDSQLWhereConditionRow
extends VBoxContainer
## One typed condition in the reusable query-graph WHERE editor.

signal changed
signal remove_requested(row: GDSQLWhereConditionRow)
signal move_requested(row: GDSQLWhereConditionRow, direction: int)

const WHERE_IS_NULL := 100
const WHERE_IS_NOT_NULL := 101

var _columns: Array[GDSQLColumnDefinition] = []
var _value_field: GDSQLEditorVariantValueField
var _rebuilding := false

@onready var _first_marker: Label = %FirstMarker
@onready var _connector: OptionButton = %Connector
@onready var _invert: CheckButton = %Invert
@onready var _column: OptionButton = %Column
@onready var _operator: OptionButton = %Operator
@onready var _value_host: HBoxContainer = %ValueHost
@onready var _move_up: Button = %MoveUp
@onready var _move_down: Button = %MoveDown
@onready var _remove: Button = %Remove


func _ready() -> void:
	_populate_connectors()
	_populate_operators()
	_connector.item_selected.connect(_on_control_changed)
	_invert.toggled.connect(_on_control_changed)
	_column.item_selected.connect(_on_column_selected)
	_operator.item_selected.connect(_on_operator_selected)
	_move_up.pressed.connect(move_requested.emit.bind(self, -1))
	_move_down.pressed.connect(move_requested.emit.bind(self, 1))
	_remove.pressed.connect(remove_requested.emit.bind(self))


func configure(
		columns: Array[GDSQLColumnDefinition],
		preserve_state: bool = false,
) -> void:
	var selected_column := get_selected_column_name()
	var selected_operator := get_operator_id()
	var selected_connector := get_connector()
	var was_inverted := _invert.button_pressed
	var value_state := _capture_value()
	_rebuilding = true
	_columns = columns.duplicate()
	_populate_columns(selected_column if preserve_state else &"")
	_select_metadata(
		_operator,
		selected_operator if preserve_state else (
				GDSQLComparisonExpression.ComparisonOperator.EQUAL
		),
	)
	_select_metadata(
		_connector,
		selected_connector if preserve_state else (
				GDSQLLogicalExpression.LogicalOperator.AND
		),
	)
	_invert.button_pressed = was_inverted if preserve_state else false
	_rebuild_value(value_state if preserve_state else { })
	_rebuilding = false


func set_first(is_first: bool) -> void:
	_first_marker.visible = is_first
	_connector.visible = not is_first
	_move_up.disabled = is_first


func set_last(is_last: bool) -> void:
	_move_down.disabled = is_last


func get_connector() -> GDSQLLogicalExpression.LogicalOperator:
	if _connector == null or _connector.selected < 0:
		return GDSQLLogicalExpression.LogicalOperator.AND
	return int(_connector.get_item_metadata(_connector.selected)) \
			as GDSQLLogicalExpression.LogicalOperator


func get_selected_column_name() -> StringName:
	if _column == null or _column.selected < 0:
		return &""
	return StringName(_column.get_item_metadata(_column.selected))


func get_operator_id() -> int:
	if _operator == null or _operator.selected < 0:
		return GDSQLComparisonExpression.ComparisonOperator.EQUAL
	return int(_operator.get_item_metadata(_operator.selected))


func build_expression() -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	var column_definition := _get_selected_column()
	if column_definition == null:
		return _error(
			&"GDSQL_QUERY_GRAPH_WHERE_COLUMN_REQUIRED",
			"Choose a column for this WHERE condition.",
		)
	var left := GDSQLExpr.column(column_definition.name)
	var operator_id := get_operator_id()
	var expression: GDSQLQueryExpression
	if operator_id == WHERE_IS_NULL:
		expression = left.is_null()
	elif operator_id == WHERE_IS_NOT_NULL:
		expression = left.is_not_null()
	else:
		if _value_field == null:
			return _error(
				&"GDSQL_QUERY_GRAPH_WHERE_VALUE_REQUIRED",
				"Enter a value for this WHERE condition.",
			)
		var converted := _value_field.get_value_result()
		if not converted.valid:
			return _error(
				&"GDSQL_QUERY_GRAPH_WHERE_VALUE_INVALID",
				"WHERE value for '%s' must be %s." % [
					column_definition.name,
					type_string(column_definition.data_type),
				],
			)
		expression = _build_comparison(left, operator_id, converted.value)
		if expression == null:
			return _error(
				&"GDSQL_QUERY_GRAPH_WHERE_OPERATOR_UNSUPPORTED",
				"The selected WHERE operator is not supported.",
			)
	result.value = GDSQLExpr.not_(expression) if _invert.button_pressed else expression
	return result


func get_summary() -> String:
	var column_name := String(get_selected_column_name())
	if column_name.is_empty() or _operator.selected < 0:
		return "<incomplete condition>"
	var summary := "%s %s" % [column_name, _operator.get_item_text(_operator.selected)]
	if get_operator_id() not in [WHERE_IS_NULL, WHERE_IS_NOT_NULL]:
		var converted := _value_field.get_value_result() if _value_field != null else { }
		summary += " %s" % (
				var_to_str(converted.value) if converted.get("valid", false) else "<invalid>"
		)
	return "NOT (%s)" % summary if _invert.button_pressed else summary


func _populate_connectors() -> void:
	_connector.clear()
	_connector.add_item("AND")
	_connector.set_item_metadata(
		_connector.item_count - 1,
		GDSQLLogicalExpression.LogicalOperator.AND,
	)
	_connector.add_item("OR")
	_connector.set_item_metadata(
		_connector.item_count - 1,
		GDSQLLogicalExpression.LogicalOperator.OR,
	)


func _populate_operators() -> void:
	_operator.clear()
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
		_operator.add_item(definition[0])
		_operator.set_item_metadata(_operator.item_count - 1, definition[1])


func _populate_columns(selected_column: StringName) -> void:
	_column.clear()
	for definition in _columns:
		_column.add_item(String(definition.name))
		var index := _column.item_count - 1
		_column.set_item_metadata(index, definition.name)
		if definition.name == selected_column:
			_column.select(index)
	_column.disabled = _column.item_count == 0
	if _column.item_count > 0 and _column.selected < 0:
		_column.select(0)


func _select_metadata(button: OptionButton, metadata: int) -> void:
	for index in range(button.item_count):
		if int(button.get_item_metadata(index)) == metadata:
			button.select(index)
			return


func _capture_value() -> Dictionary:
	if _value_field == null:
		return { }
	var converted := _value_field.get_value_result()
	return (
			{ "has_value": true, "value": converted.value }
			if converted.valid
			else { }
	)


func _rebuild_value(state: Dictionary = { }) -> void:
	for child in _value_host.get_children():
		_value_host.remove_child(child)
		child.queue_free()
	_value_field = null
	if get_operator_id() in [WHERE_IS_NULL, WHERE_IS_NOT_NULL]:
		_value_host.visible = false
		return
	var column_definition := _get_selected_column()
	if column_definition == null:
		_value_host.visible = false
		return
	_value_field = GDSQLEditorVariantValueField.new()
	_value_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_value_host.add_child(_value_field)
	_value_field.configure(
		column_definition.data_type,
		state.get("value") if state.get("has_value", false) else (
				_default_value(column_definition.data_type)
		),
		false,
		true,
	)
	_value_field.changed.connect(_on_value_changed)
	_value_host.visible = true


func _get_selected_column() -> GDSQLColumnDefinition:
	var selected_name := get_selected_column_name()
	for definition in _columns:
		if definition.name == selected_name:
			return definition
	return null


func _build_comparison(
		left: GDSQLQueryExpression,
		operator_id: int,
		value: Variant,
) -> GDSQLQueryExpression:
	match operator_id:
		GDSQLComparisonExpression.ComparisonOperator.EQUAL:
			return left.equals(value)
		GDSQLComparisonExpression.ComparisonOperator.NOT_EQUAL:
			return left.not_equals(value)
		GDSQLComparisonExpression.ComparisonOperator.GREATER_THAN:
			return left.greater_than(value)
		GDSQLComparisonExpression.ComparisonOperator.GREATER_THAN_OR_EQUAL:
			return left.greater_than_or_equal(value)
		GDSQLComparisonExpression.ComparisonOperator.LESS_THAN:
			return left.less_than(value)
		GDSQLComparisonExpression.ComparisonOperator.LESS_THAN_OR_EQUAL:
			return left.less_than_or_equal(value)
	return null


func _on_control_changed(_value: Variant) -> void:
	_emit_changed()


func _on_column_selected(_index: int) -> void:
	_rebuild_value()
	_emit_changed()


func _on_operator_selected(_index: int) -> void:
	_rebuild_value()
	_emit_changed()


func _on_value_changed() -> void:
	_emit_changed()


func _emit_changed() -> void:
	if not _rebuilding:
		changed.emit()


func _error(code: StringName, message: String) -> GDSQLOperationResult:
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
