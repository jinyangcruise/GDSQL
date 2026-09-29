@tool
class_name GDSQLWhereExpressionGroup
extends PanelContainer
## One explicit precedence group in the shared typed WHERE editor.

signal changed
signal remove_requested(group: GDSQLWhereExpressionGroup)
signal move_requested(group: GDSQLWhereExpressionGroup, direction: int)

const MAX_NESTING_DEPTH := 4
const CONDITION_SCENE := preload(
	"res://addons/gdsql/editor/workspace/query_graph/components/where_expression/where_condition_row.tscn"
)

var _fields: Array[GDSQLEditorWhereField] = []
var _group_scene: PackedScene
var _is_root := false
var _depth := 0
var _rebuilding := false

@onready var _first_marker: Label = %FirstMarker
@onready var _connector: OptionButton = %Connector
@onready var _invert: CheckButton = %Invert
@onready var _collapse: Button = %Collapse
@onready var _summary: Label = %Summary
@onready var _body: VBoxContainer = %Body
@onready var _items: VBoxContainer = %Items
@onready var _add_condition: Button = %AddCondition
@onready var _add_group: Button = %AddGroup
@onready var _move_up: Button = %MoveUp
@onready var _move_down: Button = %MoveDown
@onready var _remove: Button = %Remove


func _ready() -> void:
	_populate_connectors()
	_connector.item_selected.connect(_on_control_changed)
	_invert.toggled.connect(_on_control_changed)
	_collapse.pressed.connect(_toggle_collapsed)
	_add_condition.pressed.connect(_on_add_condition)
	_add_group.pressed.connect(_on_add_group)
	_move_up.pressed.connect(move_requested.emit.bind(self, -1))
	_move_down.pressed.connect(move_requested.emit.bind(self, 1))
	_remove.pressed.connect(remove_requested.emit.bind(self))
	for item in _get_items():
		_connect_item(item)


func configure(
		fields: Array[GDSQLEditorWhereField],
		group_scene: PackedScene,
		preserve_state: bool = false,
		is_root: bool = false,
		depth: int = 0,
) -> void:
	_rebuilding = true
	_fields = fields.duplicate()
	_group_scene = group_scene
	_is_root = is_root
	_depth = depth
	if not preserve_state:
		_clear_items()
		_invert.set_pressed_no_signal(false)
		_select_connector(GDSQLLogicalExpression.LogicalOperator.AND)
		_set_collapsed(false)
	for item in _get_items():
		if item is GDSQLWhereConditionRow:
			item.configure(_fields, preserve_state)
		elif item is GDSQLWhereExpressionGroup:
			item.configure(_fields, _group_scene, preserve_state, false, _depth + 1)
	if _items.get_child_count() == 0 and not _fields.is_empty():
		_create_condition()
	_configure_header()
	_update_item_positions()
	_update_summary()
	_rebuilding = false


func build_expression() -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	var items := _get_items()
	if items.is_empty():
		return _error(
			&"GDSQL_QUERY_GRAPH_WHERE_GROUP_EMPTY",
			"Add a condition or nested group to this WHERE group.",
		)
	var composed: GDSQLQueryExpression
	for index in range(items.size()):
		var item_result := items[index].call("build_expression") as GDSQLOperationResult
		if item_result == null or not item_result.is_successful():
			if item_result != null:
				result.diagnostics.merge(item_result.diagnostics)
			return result
		var expression := item_result.get_value() as GDSQLQueryExpression
		if index == 0:
			composed = expression
		elif items[index].call("get_connector") \
				== GDSQLLogicalExpression.LogicalOperator.OR:
			composed = GDSQLExpr.or_(composed, expression)
		else:
			composed = GDSQLExpr.and_(composed, expression)
	result.value = GDSQLExpr.not_(composed) if _invert.button_pressed else composed
	return result


func get_summary() -> String:
	var items := _get_items()
	if items.is_empty():
		return "(<empty group>)"
	var text := String(items[0].call("get_summary"))
	for index in range(1, items.size()):
		var connector := (
			"OR"
			if items[index].call("get_connector") \
					== GDSQLLogicalExpression.LogicalOperator.OR
			else "AND"
		)
		text = "%s %s %s" % [text, connector, items[index].call("get_summary")]
	text = "(%s)" % text
	return "NOT %s" % text if _invert.button_pressed else text


func get_connector() -> GDSQLLogicalExpression.LogicalOperator:
	if _connector.selected < 0:
		return GDSQLLogicalExpression.LogicalOperator.AND
	return int(_connector.get_item_metadata(_connector.selected)) \
			as GDSQLLogicalExpression.LogicalOperator


func get_condition_count() -> int:
	var count := 0
	for item in _get_items():
		if item is GDSQLWhereConditionRow:
			count += 1
		elif item is GDSQLWhereExpressionGroup:
			count += item.get_condition_count()
	return count


func set_first(is_first: bool) -> void:
	_first_marker.visible = is_first or _is_root
	_connector.visible = not is_first and not _is_root
	_move_up.disabled = is_first


func set_last(is_last: bool) -> void:
	_move_down.disabled = is_last


func _create_condition() -> GDSQLWhereConditionRow:
	var row := CONDITION_SCENE.instantiate() as GDSQLWhereConditionRow
	_items.add_child(row)
	_connect_item(row)
	row.configure(_fields)
	return row


func _create_group() -> GDSQLWhereExpressionGroup:
	if _group_scene == null or _depth >= MAX_NESTING_DEPTH:
		return null
	var group := _group_scene.instantiate() as GDSQLWhereExpressionGroup
	_items.add_child(group)
	_connect_item(group)
	group.configure(_fields, _group_scene, false, false, _depth + 1)
	return group


func _connect_item(item: Control) -> void:
	if item is GDSQLWhereConditionRow:
		item.changed.connect(_on_item_changed)
		item.remove_requested.connect(_on_remove_item)
		item.move_requested.connect(_on_move_item)
	elif item is GDSQLWhereExpressionGroup:
		item.changed.connect(_on_item_changed)
		item.remove_requested.connect(_on_remove_item)
		item.move_requested.connect(_on_move_item)


func _get_items() -> Array[Control]:
	var result: Array[Control] = []
	for child in _items.get_children():
		if child is GDSQLWhereConditionRow or child is GDSQLWhereExpressionGroup:
			result.append(child)
	return result


func _clear_items() -> void:
	for item in _get_items():
		_items.remove_child(item)
		item.queue_free()


func _configure_header() -> void:
	_first_marker.text = "ROOT" if _is_root else "IF"
	_move_up.visible = not _is_root
	_move_down.visible = not _is_root
	_remove.visible = not _is_root
	_add_group.disabled = _depth >= MAX_NESTING_DEPTH
	_add_group.tooltip_text = (
		"Maximum WHERE nesting depth reached."
		if _add_group.disabled else "Add a nested precedence group"
	)
	set_first(_is_root)
	set_last(_is_root)


func _update_item_positions() -> void:
	var items := _get_items()
	for index in range(items.size()):
		items[index].call("set_first", index == 0)
		items[index].call("set_last", index == items.size() - 1)


func _update_summary() -> void:
	_summary.text = get_summary()
	_summary.tooltip_text = _summary.text


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


func _select_connector(operator: GDSQLLogicalExpression.LogicalOperator) -> void:
	for index in range(_connector.item_count):
		if int(_connector.get_item_metadata(index)) == operator:
			_connector.select(index)
			return


func _set_collapsed(collapsed: bool) -> void:
	_body.visible = not collapsed
	_summary.visible = collapsed
	_collapse.text = "▶" if collapsed else "▼"
	_collapse.tooltip_text = "Expand group" if collapsed else "Collapse group"


func _toggle_collapsed() -> void:
	_set_collapsed(_body.visible)
	_update_summary()


func _on_add_condition() -> void:
	_create_condition()
	_update_item_positions()
	_on_item_changed()


func _on_add_group() -> void:
	if _create_group() == null:
		return
	_update_item_positions()
	_on_item_changed()


func _on_control_changed(_value: Variant) -> void:
	_on_item_changed()


func _on_item_changed() -> void:
	_update_summary()
	if not _rebuilding:
		changed.emit()


func _on_remove_item(item: Control) -> void:
	if not is_instance_valid(item) or item.get_parent() != _items:
		return
	_items.remove_child(item)
	item.queue_free()
	_update_item_positions()
	_on_item_changed()


func _on_move_item(item: Control, direction: int) -> void:
	if not is_instance_valid(item) or item.get_parent() != _items:
		return
	var index := item.get_index()
	var target := clampi(index + direction, 0, _items.get_child_count() - 1)
	if index == target:
		return
	_items.move_child(item, target)
	_update_item_positions()
	_on_item_changed()


func _error(code: StringName, message: String) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
