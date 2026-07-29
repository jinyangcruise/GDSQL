@tool
class_name GDSQLLogEntry
extends PanelContainer
## Presentation-only row used by the bounded log feed.

signal context_requested(entry_id: int, screen_position: Vector2i)

var entry_id: int
var time_text: String
var status_text: String
var action_text: String
var message_text: String
var tick: int

@onready var _row: PanelContainer = $Content/Row
@onready var _time: Label = $Content/Row/Margin/Fields/Time
@onready var _status_panel: PanelContainer = $Content/Row/Margin/Fields/Status
@onready var _status: Label = $Content/Row/Margin/Fields/Status/StatusMargin/Value
@onready var _action: Label = $Content/Row/Margin/Fields/Action
@onready var _message: Label = $Content/Row/Margin/Fields/Message


func _ready() -> void:
	_row.gui_input.connect(_on_row_gui_input)


func configure(
	p_entry_id: int,
	p_time_text: String,
	p_status_text: String,
	p_action_text: String,
	p_message_text: String,
) -> void:
	if not is_node_ready():
		await ready
	entry_id = p_entry_id
	time_text = p_time_text
	status_text = p_status_text
	action_text = p_action_text
	message_text = p_message_text
	# [TODO] Add optional tick option
	tick = Time.get_ticks_msec()
	_time.text = str(time_text, str("/", tick) if true else "")
	_status.text = status_text
	_action.text = action_text
	_message.text = message_text
	_apply_status_style(status_text)
	tooltip_text = "#%d · %s · %s\n%s" % [entry_id, action_text, status_text, message_text]


func _on_row_gui_input(event: InputEvent) -> void:
	var mouse_event := event as InputEventMouseButton
	if mouse_event == null \
			or mouse_event.button_index != MOUSE_BUTTON_RIGHT \
			or not mouse_event.pressed:
		return
	context_requested.emit(entry_id, DisplayServer.mouse_get_position())
	accept_event()


func _apply_status_style(p_status_text: String) -> void:
	var color := Color(0.25, 0.25, 0.25, 0.8)
	match p_status_text:
		"OK":
			color = Color(0.08, 0.38, 0.19, 0.9)
		"Info":
			color = Color(0.08, 0.25, 0.48, 0.9)
		"Warning":
			color = Color(0.55, 0.32, 0.04, 0.9)
		"Error":
			color = Color.DARK_RED
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	_status_panel.add_theme_stylebox_override("panel", style)
