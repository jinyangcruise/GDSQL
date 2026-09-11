@tool
class_name GDSQLQueryGraphNodeHeader
extends HBoxContainer
## Reusable controls appended to Godot's native GraphNode titlebar.

signal close_requested
signal fit_requested

@onready var _actions: HBoxContainer = %HeaderActions
@onready var _close: Button = %CloseNode
@onready var _expand_node: Button = %ExpandNode


func _ready() -> void:
	_close.pressed.connect(close_requested.emit)
	_expand_node.pressed.connect(fit_requested.emit)


func get_actions_host() -> HBoxContainer:
	return _actions


func add_action_control(control: Control) -> void:
	if control == null or control == _close:
		return
	_actions.add_child(control)


func set_close_visible(visible: bool) -> void:
	_close.visible = visible


func set_close_enabled(enabled: bool) -> void:
	_close.disabled = not enabled
