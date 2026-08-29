@tool
extends EditorPlugin

const BBCodeInspectorPlugin = preload(
	"res://addons/bbcode_editor/inspector/bbcode_inspector_plugin.gd"
)
const DialogScene = preload("res://addons/bbcode_editor/ui/bbcode_editor_dialog.tscn")
const COMMAND_KEY := "bbcode_editor/open_playground"

var _inspector_plugin: EditorInspectorPlugin
var _standalone_dialog: BBCodeEditorDialog
var _standalone_text := ""


func _enter_tree() -> void:
	_inspector_plugin = BBCodeInspectorPlugin.new()
	add_inspector_plugin(_inspector_plugin)
	EditorInterface.get_inspector().property_edited.connect(_on_inspector_property_edited)
	EditorInterface.get_command_palette().add_command(
		"Open BBCode Editor",
		COMMAND_KEY,
		_open_standalone_editor,
	)


func _exit_tree() -> void:
	EditorInterface.get_command_palette().remove_command(COMMAND_KEY)
	var inspector := EditorInterface.get_inspector()
	if inspector.property_edited.is_connected(_on_inspector_property_edited):
		inspector.property_edited.disconnect(_on_inspector_property_edited)
	if is_instance_valid(_standalone_dialog):
		_standalone_dialog.queue_free()
		_standalone_dialog = null
	if _inspector_plugin != null:
		remove_inspector_plugin(_inspector_plugin)
		_inspector_plugin = null


func _open_standalone_editor() -> void:
	if is_instance_valid(_standalone_dialog):
		_standalone_dialog.open_editor()
		return

	_standalone_dialog = DialogScene.instantiate()
	_standalone_dialog.setup(_standalone_text, "BBCode Playground")
	_standalone_dialog.text_submitted.connect(_save_standalone_text)
	_standalone_dialog.tree_exited.connect(_clear_standalone_dialog_reference)
	EditorInterface.get_base_control().add_child(_standalone_dialog)
	_standalone_dialog.open_editor()


func _save_standalone_text(value: String) -> void:
	_standalone_text = value


func _clear_standalone_dialog_reference() -> void:
	_standalone_dialog = null


func _on_inspector_property_edited(property: String) -> void:
	if property != "bbcode_enabled":
		return
	var edited_object := EditorInterface.get_inspector().get_edited_object()
	if edited_object is RichTextLabel:
		edited_object.notify_property_list_changed.call_deferred()
