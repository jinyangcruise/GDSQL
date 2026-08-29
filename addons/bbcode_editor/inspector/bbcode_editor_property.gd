@tool
extends EditorProperty

const DialogScene = preload("res://addons/bbcode_editor/ui/bbcode_editor_dialog.tscn")
const InspectorFieldScene = preload("res://addons/bbcode_editor/ui/inspector_text_field.tscn")

var _field: HBoxContainer
var _text_edit: TextEdit
var _expand_button: Button
var _dialog: BBCodeEditorDialog
var _updating := false


func _init() -> void:
	_field = InspectorFieldScene.instantiate()
	## Why the heck godot had this component as min 126??? I had to overwrite here to fit
	_field.custom_minimum_size = Vector2(0, 126)
	_text_edit = _field.get_node("Text")
	_expand_button = _field.get_node("Expand")
	_text_edit.text_changed.connect(_on_field_text_changed)
	_text_edit.focus_exited.connect(_on_field_focus_exited)
	_expand_button.pressed.connect(_open_editor)
	add_child(_field)
	set_bottom_editor(_field)
	_update_expand_icon.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and is_instance_valid(_expand_button):
		_update_expand_icon()


func _update_property() -> void:
	var value := str(get_edited_object().get(get_edited_property()))
	if _text_edit.text == value:
		return
	_updating = true
	_text_edit.text = value
	_updating = false


func _update_expand_icon() -> void:
	if not is_instance_valid(_expand_button):
		return
	var editor_theme := EditorInterface.get_editor_theme()
	if editor_theme.has_icon(&"DistractionFree", &"EditorIcons"):
		_expand_button.icon = editor_theme.get_icon(&"DistractionFree", &"EditorIcons")
		_expand_button.text = ""
	else:
		_expand_button.text = "↗"


func _on_field_text_changed() -> void:
	if _updating:
		return
	emit_changed(get_edited_property(), _text_edit.text, "", true)


func _on_field_focus_exited() -> void:
	if _updating:
		return
	emit_changed(get_edited_property(), _text_edit.text)


func _open_editor() -> void:
	if is_instance_valid(_dialog):
		_dialog.open_editor()
		return

	_dialog = DialogScene.instantiate()
	_dialog.setup(str(get_edited_object().get(get_edited_property())))
	_dialog.text_submitted.connect(_commit_dialog_text)
	_dialog.tree_exited.connect(_clear_dialog_reference)
	EditorInterface.get_base_control().add_child(_dialog)
	_dialog.open_editor()


func _commit_dialog_text(value: String) -> void:
	emit_changed(get_edited_property(), value)


func _clear_dialog_reference() -> void:
	_dialog = null
