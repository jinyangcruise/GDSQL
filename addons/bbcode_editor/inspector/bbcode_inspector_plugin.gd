@tool
extends EditorInspectorPlugin

const BBCodeEditorProperty = preload(
	"res://addons/bbcode_editor/inspector/bbcode_editor_property.gd"
)


func _can_handle(object: Object) -> bool:
	return object is RichTextLabel


func _parse_property(
	object: Object,
	type: Variant.Type,
	name: String,
	_hint_type: PropertyHint,
	_hint_string: String,
	_usage_flags: int,
	_wide: bool
) -> bool:
	if not _should_override(object, type, name):
		return false

	add_property_editor(name, BBCodeEditorProperty.new())
	return true


func _should_override(object: Object, type: Variant.Type, name: String) -> bool:
	return (
		object is RichTextLabel
		and (object as RichTextLabel).bbcode_enabled
		and name == "text"
		and type == TYPE_STRING
	)
