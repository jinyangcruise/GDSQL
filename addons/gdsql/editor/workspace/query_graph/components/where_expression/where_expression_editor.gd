@tool
class_name GDSQLWhereExpressionEditor
extends VBoxContainer
## Reusable visual editor for a composed canonical WHERE predicate.
##
## Conditions are composed in visible order. Each connector wraps the previous
## expression and the next condition, so mixed AND/OR expressions are explicitly
## left-associative until nested expression groups are introduced.

signal changed
signal apply_requested
signal clear_requested

const CONDITION_SCENE := preload(
	"res://addons/gdsql/editor/workspace/query_graph/components/where_expression/where_condition_row.tscn"
)

@export var show_header_actions := false

var _columns: Array[GDSQLColumnDefinition] = []
var _rebuilding := false

@onready var _use_where: CheckButton = %UseWhere
@onready var _header_actions: HBoxContainer = %HeaderActions
@onready var _header_summary: Label = %HeaderSummary
@onready var _clear: Button = %Clear
@onready var _apply: Button = %Apply
@onready var _expression_body: VBoxContainer = %ExpressionBody
@onready var _conditions: VBoxContainer = %Conditions
@onready var _add_condition: Button = %AddCondition
@onready var _validation_status: Label = %ValidationStatus


func _ready() -> void:
	_use_where.toggled.connect(_on_where_toggled)
	_clear.pressed.connect(clear_requested.emit)
	_apply.pressed.connect(apply_requested.emit)
	_add_condition.pressed.connect(_on_add_condition)
	_header_actions.visible = show_header_actions
	_update_presentation()


func set_header_actions_state(
		apply_enabled: bool,
		clear_enabled: bool,
		summary: String,
) -> void:
	_header_actions.visible = show_header_actions
	_apply.disabled = not apply_enabled
	_clear.disabled = not clear_enabled
	_header_summary.text = summary


func configure(
		columns: Array[GDSQLColumnDefinition],
		preserve_state: bool = false,
) -> void:
	_rebuilding = true
	_columns = columns.duplicate()
	if not preserve_state:
		_clear_conditions()
		_use_where.button_pressed = false
	for row in _get_conditions():
		row.configure(_columns, preserve_state)
	if _conditions.get_child_count() == 0 and not _columns.is_empty():
		_create_condition()
	_use_where.disabled = _columns.is_empty()
	if _columns.is_empty():
		_use_where.button_pressed = false
	_rebuilding = false
	_update_condition_positions()
	_update_presentation()


func build_expression() -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if not _use_where.button_pressed:
		result.value = null
		return result
	var rows := _get_conditions()
	if rows.is_empty():
		return _error(
			&"GDSQL_QUERY_GRAPH_WHERE_CONDITION_REQUIRED",
			"Add at least one WHERE condition.",
		)
	var composed: GDSQLQueryExpression
	for index in range(rows.size()):
		var condition_result := rows[index].build_expression()
		if not condition_result.is_successful():
			result.diagnostics.merge(condition_result.diagnostics)
			return result
		var condition := condition_result.get_value() as GDSQLQueryExpression
		if index == 0:
			composed = condition
		elif rows[index].get_connector() == GDSQLLogicalExpression.LogicalOperator.OR:
			composed = GDSQLExpr.or_(composed, condition)
		else:
			composed = GDSQLExpr.and_(composed, condition)
	result.value = composed
	return result


func get_summary() -> String:
	if not _use_where.button_pressed:
		return ""
	var rows := _get_conditions()
	if rows.is_empty():
		return " WHERE <no conditions>"
	var summary := rows[0].get_summary()
	for index in range(1, rows.size()):
		var connector := (
				"OR"
				if rows[index].get_connector() == GDSQLLogicalExpression.LogicalOperator.OR
				else "AND"
		)
		summary = "(%s %s %s)" % [summary, connector, rows[index].get_summary()]
	return " WHERE %s" % summary


func is_enabled() -> bool:
	return _use_where.button_pressed


func get_condition_count() -> int:
	return _conditions.get_child_count()


func _create_condition() -> GDSQLWhereConditionRow:
	var row := CONDITION_SCENE.instantiate() as GDSQLWhereConditionRow
	_conditions.add_child(row)
	row.changed.connect(_on_condition_changed)
	row.remove_requested.connect(_on_remove_condition)
	row.move_requested.connect(_on_move_condition)
	row.configure(_columns)
	return row


func _clear_conditions() -> void:
	for child in _conditions.get_children():
		_conditions.remove_child(child)
		child.queue_free()


func _get_conditions() -> Array[GDSQLWhereConditionRow]:
	var rows: Array[GDSQLWhereConditionRow] = []
	for child in _conditions.get_children():
		if child is GDSQLWhereConditionRow:
			rows.append(child)
	return rows


func _update_condition_positions() -> void:
	var rows := _get_conditions()
	for index in range(rows.size()):
		rows[index].set_first(index == 0)
		rows[index].set_last(index == rows.size() - 1)


func _update_presentation() -> void:
	_expression_body.visible = _use_where.button_pressed and not _columns.is_empty()
	_validation_status.visible = false
	_validation_status.text = ""
	if not _use_where.button_pressed:
		return
	var result := build_expression()
	if not result.is_successful() and not result.diagnostics.entries.is_empty():
		_validation_status.text = result.diagnostics.entries[0].message
		_validation_status.visible = true


func _on_where_toggled(_enabled: bool) -> void:
	_update_presentation()
	_emit_changed()


func _on_add_condition() -> void:
	_create_condition()
	_update_condition_positions()
	_update_presentation()
	_emit_changed()


func _on_condition_changed() -> void:
	_update_presentation()
	_emit_changed()


func _on_remove_condition(row: GDSQLWhereConditionRow) -> void:
	if not is_instance_valid(row) or row.get_parent() != _conditions:
		return
	_conditions.remove_child(row)
	row.queue_free()
	_update_condition_positions()
	_update_presentation()
	_emit_changed()


func _on_move_condition(row: GDSQLWhereConditionRow, direction: int) -> void:
	if not is_instance_valid(row) or row.get_parent() != _conditions:
		return
	var index := row.get_index()
	var target := clampi(index + direction, 0, _conditions.get_child_count() - 1)
	if index == target:
		return
	_conditions.move_child(row, target)
	_update_condition_positions()
	_update_presentation()
	_emit_changed()


func _emit_changed() -> void:
	if not _rebuilding:
		changed.emit()


func _error(code: StringName, message: String) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
