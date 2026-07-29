@tool
class_name GDSQLEditorActionStrip
extends HBoxContainer
## Reusable toolbar that presents a selected set of editor actions.

var _hub: GDSQLEditorActionHub
var _action_ids: Array[StringName] = []


func configure(
		hub: GDSQLEditorActionHub,
		action_ids: Array[StringName],
) -> void:
	_hub = hub
	_action_ids = action_ids.duplicate()
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	if _hub == null:
		return
	for action_id in _action_ids:
		var definition := _hub.get_action(action_id)
		if definition == null:
			continue
		var button := GDSQLEditorActionButton.new()
		add_child(button)
		button.configure(_hub, definition)
