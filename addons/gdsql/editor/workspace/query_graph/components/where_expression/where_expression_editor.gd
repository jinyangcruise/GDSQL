@tool
class_name GDSQLWhereExpressionEditor
extends VBoxContainer
## Reusable visual editor for a composed canonical WHERE predicate.
##
## Conditions are left-associative inside an explicit group. Nested groups
## produce nested canonical logical expressions and therefore visible precedence.

signal changed
signal apply_requested
signal clear_requested

const GROUP_SCENE := preload(
	"res://addons/gdsql/editor/workspace/query_graph/components/where_expression/where_expression_group.tscn"
)

@export var show_header_actions := false

var _fields: Array[GDSQLEditorWhereField] = []
var _rebuilding := false
var _field_catalog := GDSQLEditorWhereFieldCatalog.new()

@onready var _use_where: CheckButton = %UseWhere
@onready var _header_actions: HBoxContainer = %HeaderActions
@onready var _header_summary: Label = %HeaderSummary
@onready var _clear: Button = %Clear
@onready var _apply: Button = %Apply
@onready var _expression_body: VBoxContainer = %ExpressionBody
@onready var _root_group: GDSQLWhereExpressionGroup = %RootGroup
@onready var _validation_status: Label = %ValidationStatus


func _ready() -> void:
	_use_where.toggled.connect(_on_where_toggled)
	_clear.pressed.connect(clear_requested.emit)
	_apply.pressed.connect(apply_requested.emit)
	_root_group.changed.connect(_on_group_changed)
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
	_fields = _field_catalog.build(columns)
	if not preserve_state:
		_use_where.button_pressed = false
	_root_group.configure(_fields, GROUP_SCENE, preserve_state, true)
	_use_where.disabled = _fields.is_empty()
	if _fields.is_empty():
		_use_where.button_pressed = false
	_rebuilding = false
	_update_presentation()


func build_expression() -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if not _use_where.button_pressed:
		result.value = null
		return result
	if _root_group.get_condition_count() == 0:
		return _error(
			&"GDSQL_QUERY_GRAPH_WHERE_CONDITION_REQUIRED",
			"Add at least one WHERE condition.",
		)
	return _root_group.build_expression()


func get_summary() -> String:
	if not _use_where.button_pressed:
		return ""
	if _root_group.get_condition_count() == 0:
		return " WHERE <no conditions>"
	return " WHERE %s" % _root_group.get_summary()


func is_enabled() -> bool:
	return _use_where.button_pressed


func get_condition_count() -> int:
	return _root_group.get_condition_count()


func _update_presentation() -> void:
	_expression_body.visible = _use_where.button_pressed and not _fields.is_empty()
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


func _on_group_changed() -> void:
	_update_presentation()
	_emit_changed()


func _emit_changed() -> void:
	if not _rebuilding:
		changed.emit()


func _error(code: StringName, message: String) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
