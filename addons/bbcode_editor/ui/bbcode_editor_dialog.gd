@tool
class_name BBCodeEditorDialog
extends ConfirmationDialog

signal text_submitted(value: String)

const BBCodeActions = preload("res://addons/bbcode_editor/data/bbcode_actions.gd")
const ICON_DIRECTORY := "res://addons/bbcode_editor/icons/"

@export_multiline var editor_text := ""

@onready var _toolbar: HFlowContainer = %Toolbar
@onready var _editor: TextEdit = %Source
@onready var _preview: RichTextLabel = %Preview
@onready var _status: Label = %Status
@onready var _unsaved_dialog: ConfirmationDialog = %UnsavedChanges

var _base_title := "Edit Text"
var _saved_text := ""
var _closing := false
var _icons: Dictionary = {}


func _ready() -> void:
	if _is_scene_editor_preview():
		return
	_base_title = title
	dialog_close_on_escape = false
	_load_icons()
	_style_toolbar()
	_connect_format_buttons()
	_build_action_menus()
	_configure_unsaved_dialog()
	confirmed.connect(_save_and_close)
	canceled.connect(_request_close)
	close_requested.connect(_request_close)
	_editor.text_changed.connect(_update_preview)
	_editor.text = editor_text
	_saved_text = editor_text
	get_ok_button().tooltip_text = "Apply changes (Ctrl+S)"
	get_cancel_button().tooltip_text = "Close editor (Esc)"
	_update_preview()


func _is_scene_editor_preview() -> bool:
	return Engine.is_editor_hint() and EditorInterface.get_edited_scene_root() == self


func _input(event: InputEvent) -> void:
	if event is InputEventKey and _handle_editor_shortcut(event as InputEventKey):
		get_viewport().set_input_as_handled()


func _handle_editor_shortcut(event: InputEventKey) -> bool:
	if not event.pressed or event.echo or _closing:
		return false
	var command_pressed := event.ctrl_pressed or event.meta_pressed
	if command_pressed and event.keycode == KEY_S:
		_save_and_close()
		return true
	if event.keycode == KEY_ESCAPE and not _unsaved_dialog.visible:
		_request_close()
		return true
	return false


func setup(value: String, dialog_title := "Edit Text") -> void:
	editor_text = value
	_base_title = dialog_title
	title = dialog_title
	if is_node_ready():
		_editor.text = value
		_saved_text = value
		_update_preview()


func open_editor() -> void:
	popup_centered(Vector2i(1100, 700))
	_editor.grab_focus.call_deferred()


func get_editor_text() -> String:
	return _editor.text if is_node_ready() else editor_text


func has_unsaved_changes() -> bool:
	return is_node_ready() and _editor.text != _saved_text


func _connect_format_buttons() -> void:
	%Bold.pressed.connect(_insert_markup.bind("[b]", "[/b]", "bold text"))
	%Italic.pressed.connect(_insert_markup.bind("[i]", "[/i]", "italic text"))
	%Underline.pressed.connect(_insert_markup.bind("[u]", "[/u]", "underlined text"))
	%Strikethrough.pressed.connect(_insert_markup.bind("[s]", "[/s]", "struck text"))
	%Code.pressed.connect(_insert_markup.bind("[code]", "[/code]", "code"))


func _load_icons() -> void:
	for icon_name: String in BBCodeActions.ICONS:
		var path: String = ICON_DIRECTORY + BBCodeActions.ICONS[icon_name]
		_icons[icon_name] = load(path) as Texture2D


func _style_toolbar() -> void:
	var button_icons := {
		"Italic": "italic",
		"Underline": "underline",
		"Strikethrough": "strikethrough",
	}
	for button_name: String in button_icons:
		var button := _toolbar.get_node(button_name) as Button
		button.icon = _get_icon(button_icons[button_name])
		button.text = ""

	var menu_icons := {
		"Paragraph": ["paragraph", "Paragraph and alignment"],
		"Color": ["text_color", "Text and highlight colors"],
		"Insert": ["link", "Insert link, hint, image, or character"],
		"ListsAndTable": ["unordered_list", "Lists and tables"],
		"Typography": ["font", "Typography and headings"],
		"Special": ["more", "Special characters and direction controls"],
	}
	for menu_name: String in menu_icons:
		var menu := _toolbar.get_node(menu_name) as MenuButton
		menu.icon = _get_icon(menu_icons[menu_name][0])
		menu.tooltip_text = menu_icons[menu_name][1]
		menu.text = ""

	for child in _toolbar.get_children():
		if child is Button:
			child.flat = true
			child.add_theme_constant_override("icon_max_width", 20)
			child.custom_minimum_size = Vector2(30, 30)

	var panel := _toolbar.get_parent() as PanelContainer
	if panel != null:
		var background := StyleBoxFlat.new()
		background.bg_color = Color("292d35")
		background.corner_radius_top_left = 8
		background.corner_radius_top_right = 8
		background.corner_radius_bottom_left = 8
		background.corner_radius_bottom_right = 8
		background.content_margin_left = 4
		background.content_margin_top = 3
		background.content_margin_right = 4
		background.content_margin_bottom = 3
		panel.add_theme_stylebox_override("panel", background)


func _build_action_menus() -> void:
	for menu_name: String in BBCodeActions.MENUS:
		var menu := _toolbar.get_node(menu_name) as MenuButton
		var popup := menu.get_popup()
		var handler := _run_menu_action.bind(menu_name)
		if popup.id_pressed.is_connected(handler):
			popup.id_pressed.disconnect(handler)
		popup.clear()
		var actions: Array = BBCodeActions.MENUS[menu_name]
		for index in actions.size():
			var icon_name: String = actions[index][2] if actions[index].size() > 2 else "more"
			var icon := _get_icon(icon_name)
			if icon != null:
				popup.add_icon_item(icon, actions[index][0], index)
			else:
				popup.add_item(actions[index][0], index)
		popup.id_pressed.connect(handler)


func _configure_unsaved_dialog() -> void:
	_unsaved_dialog.add_button("Discard", true, "discard")
	_unsaved_dialog.confirmed.connect(_save_and_close)
	_unsaved_dialog.custom_action.connect(_on_unsaved_custom_action)
	_unsaved_dialog.canceled.connect(_resume_editing)
	_unsaved_dialog.close_requested.connect(_resume_editing)


func _run_menu_action(id: int, menu_name: String) -> void:
	var actions: Array = BBCodeActions.MENUS[menu_name]
	var action_name: String = actions[id][1]
	var markup: Array = BBCodeActions.INSERT_ACTIONS[action_name]
	_insert_markup(markup[0], markup[1], markup[2])


func _get_icon(icon_name: String) -> Texture2D:
	return _icons.get(icon_name) as Texture2D


func _insert_markup(opening: String, closing: String, placeholder: String) -> void:
	var selected := _editor.get_selected_text()
	var content := selected if not selected.is_empty() else placeholder
	var replacement := opening + content + closing
	var insertion_line := (
		_editor.get_selection_from_line() if _editor.has_selection() else _editor.get_caret_line()
	)
	var insertion_column := (
		_editor.get_selection_from_column()
		if _editor.has_selection()
		else _editor.get_caret_column()
	)
	_editor.begin_complex_operation()
	_editor.insert_text_at_caret(replacement)
	if not content.is_empty():
		var content_start := _advance_text_position(insertion_line, insertion_column, opening)
		var content_end := _advance_text_position(content_start.y, content_start.x, content)
		_editor.select(content_start.y, content_start.x, content_end.y, content_end.x)
	_editor.end_complex_operation()
	_update_preview()
	_editor.grab_focus()


func _advance_text_position(line: int, column: int, value: String) -> Vector2i:
	var lines := value.split("\n", true)
	if lines.size() == 1:
		return Vector2i(column + value.length(), line)
	return Vector2i(lines[-1].length(), line + lines.size() - 1)


func _update_preview() -> void:
	_preview.text = _editor.text
	var dirty_suffix := " · unsaved" if has_unsaved_changes() else ""
	_status.text = "%d characters · %d line%s%s" % [
		_editor.text.length(),
		_editor.get_line_count(),
		"" if _editor.get_line_count() == 1 else "s",
		dirty_suffix,
	]
	title = _base_title + (" *" if has_unsaved_changes() else "")


func _request_close() -> void:
	if _closing:
		return
	if not has_unsaved_changes():
		_discard_and_close()
		return
	_show_unsaved_prompt.call_deferred()


func _show_unsaved_prompt() -> void:
	if _closing or not is_instance_valid(_unsaved_dialog) or _unsaved_dialog.visible:
		return
	show()
	_unsaved_dialog.popup_centered(Vector2i(430, 160))


func _resume_editing() -> void:
	if _closing:
		return
	_unsaved_dialog.hide()
	open_editor.call_deferred()


func _on_unsaved_custom_action(action: StringName) -> void:
	if action == &"discard":
		_discard_and_close()


func _save_and_close() -> void:
	if _closing:
		return
	_closing = true
	_saved_text = _editor.text
	editor_text = _editor.text
	text_submitted.emit(editor_text)
	queue_free()


func _discard_and_close() -> void:
	if _closing:
		return
	_closing = true
	queue_free()
