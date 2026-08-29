@tool
class_name GDSQLEditorExpandedTextEditor
extends Node
## Opens the optional BBCode editor plugin or the local plain-text fallback.

signal value_applied(value: Variant)

const BBCODE_EDITOR_SCENE_PATH := (
	"res://addons/bbcode_editor/ui/bbcode_editor_dialog.tscn"
)
const FALLBACK_DIALOG_SCENE := preload(
	"res://addons/gdsql/editor/workspace/components/text_editor/gdsql_editor_text_value_dialog.tscn"
)

var _fallback_dialog: GDSQLEditorTextValueDialog


func edit_value(
	value: Variant,
	is_nullable: bool,
	is_editable: bool,
	value_label: String = "Text",
) -> void:
	if is_editable and _open_bbcode_editor(String(value) if value != null else "", value_label):
		return
	_open_fallback(value, is_nullable, is_editable, value_label)


func _open_bbcode_editor(value: String, value_label: String) -> bool:
	if not ResourceLoader.exists(BBCODE_EDITOR_SCENE_PATH, "PackedScene"):
		return false
	var scene := load(BBCODE_EDITOR_SCENE_PATH) as PackedScene
	if scene == null:
		return false
	var dialog := scene.instantiate()
	if dialog == null \
			or not dialog.has_method(&"setup") \
			or not dialog.has_method(&"open_editor") \
			or not dialog.has_signal(&"text_submitted"):
		if dialog != null:
			dialog.queue_free()
		return false
	var parent := _dialog_parent()
	if parent == null:
		dialog.queue_free()
		return false
	dialog.call(&"setup", value, "Edit %s" % value_label)
	dialog.connect(&"text_submitted", _on_bbcode_text_submitted, CONNECT_ONE_SHOT)
	parent.add_child(dialog)
	dialog.call(&"open_editor")
	return true


func _open_fallback(
	value: Variant,
	is_nullable: bool,
	is_editable: bool,
	value_label: String,
) -> void:
	if _fallback_dialog == null:
		_fallback_dialog = FALLBACK_DIALOG_SCENE.instantiate() \
				as GDSQLEditorTextValueDialog
		add_child(_fallback_dialog)
		_fallback_dialog.value_applied.connect(value_applied.emit)
	_fallback_dialog.edit_value(value, is_nullable, is_editable, value_label)


func _dialog_parent() -> Node:
	if Engine.is_editor_hint():
		var base_control := EditorInterface.get_base_control()
		if base_control != null:
			return base_control
	return get_tree().root if get_tree() != null else null


func _on_bbcode_text_submitted(value: String) -> void:
	value_applied.emit(value)
