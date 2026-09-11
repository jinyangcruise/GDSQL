@tool
class_name GDSQLEditorTextValueDialog
extends ConfirmationDialog
## Dependency-free multiline String editor used as a fallback.

signal value_applied(value: Variant)

var _editable := true
var _nullable := false
var _configuring := false

@onready var _description: Label = %Description
@onready var _use_null: CheckBox = %UseNull
@onready var _text_input: TextEdit = %TextInput


func _ready() -> void:
	confirmed.connect(_on_confirmed)
	_use_null.toggled.connect(_on_null_toggled)
	_text_input.text_changed.connect(_on_text_changed)


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
	_description.text = "Edit the stored String in a multiline field."
	_text_input.text = String(value) if value != null else ""
	_text_input.clear_undo_history()
	_text_input.editable = _editable
	_use_null.visible = _nullable
	_use_null.disabled = not _editable
	_use_null.button_pressed = _nullable and value == null
	get_ok_button().text = "Apply" if _editable else "Close"
	get_cancel_button().visible = _editable
	_configuring = false
	_text_input.editable = _editable and not (_nullable and _use_null.button_pressed)
	popup_centered(Vector2i(720, 460))
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
	_text_input.editable = _editable and not _use_null.button_pressed


func _on_text_changed() -> void:
	if _configuring:
		return
	if _nullable and _use_null.button_pressed:
		_use_null.set_pressed_no_signal(false)
