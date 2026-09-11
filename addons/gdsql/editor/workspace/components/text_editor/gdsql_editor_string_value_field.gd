@tool
class_name GDSQLEditorStringValueField
extends HBoxContainer
## Compact String field that delegates multiline editing to a focused dialog.

signal text_changed(text: String)
signal value_applied(value: Variant)

var _editable := true
var _nullable := false
var _is_null := false
var _configuring := false

@onready var _line_edit: LineEdit = %LineEdit
@onready var _expand: Button = %Expand
@onready var _expanded_editor: GDSQLEditorExpandedTextEditor = %ExpandedTextEditor


func _ready() -> void:
	_line_edit.text_changed.connect(_on_text_changed)
	_expand.pressed.connect(_on_expand_pressed)
	_expanded_editor.value_applied.connect(_on_expanded_value_applied)


func configure(value: Variant, is_nullable: bool, is_editable: bool) -> void:
	_configuring = true
	_nullable = is_nullable
	_is_null = _nullable and value == null
	_line_edit.text = String(value) if value != null else ""
	set_value_editable(is_editable)
	_configuring = false


func set_value_editable(enabled: bool) -> void:
	_editable = enabled
	_line_edit.editable = enabled
	_expand.disabled = not _editable
	_expand.tooltip_text = (
		"Open expanded text editor"
		if enabled
		else "Open expanded text editor as read only"
	)


func set_null_state(enabled: bool) -> void:
	_is_null = _nullable and enabled


func set_text(value: String) -> void:
	_configuring = true
	_line_edit.text = value
	_configuring = false


func get_text() -> String:
	return _line_edit.text


func focus_editor() -> void:
	if _line_edit.editable:
		_line_edit.grab_focus()
		_line_edit.edit()


func _on_text_changed(text: String) -> void:
	if _configuring:
		return
	_is_null = false
	text_changed.emit(text)


func _on_expand_pressed() -> void:
	_expanded_editor.edit_value(
		null if _is_null else _line_edit.text,
		_nullable,
		_editable,
		"String Value",
	)


func _on_expanded_value_applied(value: Variant) -> void:
	_is_null = _nullable and value == null
	if value != null:
		set_text(String(value))
	value_applied.emit(value)
