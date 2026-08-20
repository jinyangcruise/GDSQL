@tool
class_name GDSQLEditorTextValueDialog
extends ConfirmationDialog
## Multiline String editor with an optional BBCode preview.

signal value_applied(value: Variant)

var _editable := true
var _nullable := false
var _configuring := false

@onready var _description: Label = %Description
@onready var _use_null: CheckBox = %UseNull
@onready var _toolbar: Control = %BBCodeToolbar
@onready var _text_input: TextEdit = %TextInput
@onready var _preview_state: Label = %PreviewState
@onready var _preview: RichTextLabel = %Preview
@onready var _preview_debounce: Timer = %PreviewDebounce


func _ready() -> void:
	confirmed.connect(_on_confirmed)
	_use_null.toggled.connect(_on_null_toggled)
	_text_input.text_changed.connect(_on_text_changed)
	_toolbar.connect("wrap_requested", _on_wrap_requested)
	_toolbar.connect("insert_requested", _on_insert_requested)
	_preview_debounce.timeout.connect(_update_preview)


func edit_value(
		value: Variant,
		is_nullable: bool,
		is_editable: bool,
		value_label: String = "Text",
) -> void:
	_configuring = true
	_editable = is_editable
	_nullable = is_nullable
	title = "Edit %s" % value_label
	_description.text = (
		"Edit the stored String directly. The preview interprets it as Godot BBCode."
	)
	_text_input.text = String(value) if value != null else ""
	_text_input.clear_undo_history()
	_text_input.editable = _editable
	_toolbar.call("set_editable", _editable)
	_use_null.visible = _nullable
	_use_null.disabled = not _editable
	_use_null.button_pressed = _nullable and value == null
	get_ok_button().text = "Apply" if _editable else "Close"
	get_cancel_button().visible = _editable
	_configuring = false
	_update_preview()
	popup_centered(Vector2i(920, 620))
	if _editable:
		_text_input.call_deferred("grab_focus")


func _on_confirmed() -> void:
	if not _editable:
		return
	value_applied.emit(
		null if _nullable and _use_null.button_pressed else _text_input.text,
	)


func _on_null_toggled(_enabled: bool) -> void:
	if _configuring:
		return
	_queue_preview()


func _on_text_changed() -> void:
	if _configuring:
		return
	if _nullable and _use_null.button_pressed:
		_use_null.set_pressed_no_signal(false)
	_queue_preview()


func _on_wrap_requested(
		open_tag: String,
		close_tag: String,
		placeholder: String,
) -> void:
	if not _editable:
		return
	var selected := _text_input.get_selected_text()
	if not selected.is_empty():
		_text_input.insert_text_at_caret(open_tag + selected + close_tag)
		return
	var line := _text_input.get_caret_line()
	var column := _text_input.get_caret_column()
	_text_input.insert_text_at_caret(open_tag + placeholder + close_tag)
	_text_input.select(
		line,
		column + open_tag.length(),
		line,
		column + open_tag.length() + placeholder.length(),
	)
	_text_input.grab_focus()


func _on_insert_requested(text: String) -> void:
	if not _editable:
		return
	_text_input.deselect()
	_text_input.insert_text_at_caret(text)
	_text_input.grab_focus()


func _queue_preview() -> void:
	_preview_debounce.start()


func _update_preview() -> void:
	var is_null := _nullable and _use_null.button_pressed
	_preview_state.visible = is_null
	_preview.visible = not is_null
	_preview.text = "" if is_null else _text_input.text
