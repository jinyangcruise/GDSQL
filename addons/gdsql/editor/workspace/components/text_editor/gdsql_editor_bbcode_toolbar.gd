@tool
extends HBoxContainer
## Emits the small BBCode authoring actions supported by the text dialog.

signal wrap_requested(open_tag: String, close_tag: String, placeholder: String)
signal insert_requested(text: String)

@onready var _bold: Button = %Bold
@onready var _italic: Button = %Italic
@onready var _underline: Button = %Underline
@onready var _strikethrough: Button = %Strikethrough
@onready var _code: Button = %Code
@onready var _paragraph: Button = %Paragraph
@onready var _break: Button = %Break


func _ready() -> void:
	_bold.pressed.connect(_emit_wrap.bind("[b]", "[/b]", "text"))
	_italic.pressed.connect(_emit_wrap.bind("[i]", "[/i]", "text"))
	_underline.pressed.connect(_emit_wrap.bind("[u]", "[/u]", "text"))
	_strikethrough.pressed.connect(_emit_wrap.bind("[s]", "[/s]", "text"))
	_code.pressed.connect(_emit_wrap.bind("[code]", "[/code]", "code"))
	_paragraph.pressed.connect(_emit_wrap.bind("[p]", "[/p]", "paragraph"))
	_break.pressed.connect(_emit_insert.bind("[br]"))


func set_editable(enabled: bool) -> void:
	for child in get_children():
		if child is Button:
			(child as Button).disabled = not enabled


func _emit_wrap(open_tag: String, close_tag: String, placeholder: String) -> void:
	wrap_requested.emit(open_tag, close_tag, placeholder)


func _emit_insert(text: String) -> void:
	insert_requested.emit(text)
