@tool
class_name GDSQLEditorActionButton
extends Button
## Button presentation for an action resolved through GDSQLEditorActionHub.

var action_id: StringName
var _hub: GDSQLEditorActionHub


func configure(
		hub: GDSQLEditorActionHub,
		definition: GDSQLEditorActionDefinition,
) -> void:
	if _hub != null and _hub.actions_changed.is_connected(_refresh_state):
		_hub.actions_changed.disconnect(_refresh_state)
	_hub = hub
	action_id = definition.id
	text = tr(definition.label)
	tooltip_text = tr(definition.tooltip)
	flat = true
	if Engine.is_editor_hint() \
			and definition.icon_name != &"" \
			and has_theme_icon(definition.icon_name, &"EditorIcons"):
		icon = get_theme_icon(definition.icon_name, &"EditorIcons")
	if not pressed.is_connected(_invoke):
		pressed.connect(_invoke)
	_refresh_state()
	if not _hub.actions_changed.is_connected(_refresh_state):
		_hub.actions_changed.connect(_refresh_state)


func configure_action(
		hub: GDSQLEditorActionHub,
		requested_action_id: StringName,
) -> void:
	var definition := hub.get_action(requested_action_id) if hub != null else null
	if definition == null:
		return
	configure(hub, definition)


func _exit_tree() -> void:
	if _hub != null and _hub.actions_changed.is_connected(_refresh_state):
		_hub.actions_changed.disconnect(_refresh_state)


func _invoke() -> void:
	if _hub != null:
		_hub.invoke(action_id)


func _refresh_state() -> void:
	if _hub == null:
		return
	visible = _hub.is_action_visible(action_id)
	disabled = not _hub.is_action_enabled(action_id)
