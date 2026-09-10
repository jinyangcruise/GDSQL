@tool
class_name GDSQLEditorVariantValueField
extends VBoxContainer
## Reusable editor control for one typed Variant value.

signal changed

const VARIANT_TYPES := preload(
	"res://addons/gdsql/editor/workspace/components/gdsql_editor_variant_types.gd"
)
const STRING_FIELD_SCENE := preload(
	"res://addons/gdsql/editor/workspace/components/text_editor/gdsql_editor_string_value_field.tscn"
)

var data_type: Variant.Type = TYPE_NIL
var nullable := true
var resource_type: GDSQLResourceTypeConstraint
var _editable := true
var _line_edit: LineEdit
var _string_field: GDSQLEditorStringValueField
var _resource_picker: EditorResourcePicker
var _use_null: CheckBox
var _observed_resource: Resource
var _observed_resource_fingerprint := 0
var _editor_inspector: EditorInspector
var _modified := false
var _rebuilding := false


func _ready() -> void:
	_connect_editor_inspector()


func _exit_tree() -> void:
	_observe_resource(null)
	_disconnect_editor_inspector()


func configure(
		target_type: Variant.Type,
		value: Variant = null,
		is_nullable: bool = true,
		is_editable: bool = true,
		target_resource_type: GDSQLResourceTypeConstraint = null,
) -> void:
	_rebuilding = true
	data_type = target_type
	nullable = is_nullable
	resource_type = target_resource_type
	_editable = is_editable
	_rebuild(value)
	_modified = false
	_rebuilding = false


func is_modified() -> bool:
	return _modified


func focus_value_editor() -> void:
	if _string_field != null:
		_string_field.focus_editor()
		return
	if _line_edit != null and _line_edit.editable:
		_line_edit.grab_focus()
		_line_edit.edit()


func set_value_editable(enabled: bool) -> void:
	_editable = enabled
	if _line_edit != null:
		_line_edit.editable = enabled
	if _string_field != null:
		_string_field.set_value_editable(enabled)
	if _resource_picker != null:
		_resource_picker.editable = (enabled and resource_type != null and resource_type.is_valid())
	if _use_null != null:
		_use_null.disabled = not enabled


func get_value_result() -> Dictionary:
	if data_type == TYPE_OBJECT:
		var resource := _resource_value()
		if resource_type != null and resource_type.accepts_value(resource):
			return { "valid": true, "value": resource }
		if _is_null():
			return { "valid": nullable, "value": null }
		return { "valid": false, "value": null }
	if _is_null():
		return { "valid": nullable, "value": null }
	if data_type == TYPE_STRING and _string_field != null:
		return { "valid": true, "value": _string_field.get_text() }
	if _line_edit == null:
		return { "valid": false, "value": null }
	return _parse_text(_line_edit.text)


func _rebuild(value: Variant) -> void:
	_observe_resource(null)
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_line_edit = null
	_string_field = null
	_resource_picker = null
	_use_null = null
	if data_type == TYPE_OBJECT:
		custom_minimum_size = Vector2(220, 46)
		_build_resource_picker(value)
	elif data_type == TYPE_STRING:
		custom_minimum_size = Vector2(220, 34)
		_build_string_field(value)
	else:
		custom_minimum_size = Vector2(180, 34)
		_build_line_edit(value)
	if nullable:
		_use_null = CheckBox.new()
		_use_null.text = "Null"
		_use_null.button_pressed = value == null
		_use_null.toggled.connect(_on_null_toggled)
		add_child(_use_null)
	if _string_field != null:
		_string_field.set_null_state(value == null)
	set_value_editable(_editable)


func _build_resource_picker(value: Variant) -> void:
	_resource_picker = EditorResourcePicker.new()
	_resource_picker.custom_minimum_size = Vector2(170, 46)
	_resource_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_resource_picker.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_resource_picker.base_type = (
			resource_type.picker_base_type()
			if resource_type != null and resource_type.is_valid()
			else "Resource"
	)
	_resource_picker.resource_changed.connect(_on_resource_changed)
	_resource_picker.resource_selected.connect(_on_resource_selected)
	if value is Resource:
		_resource_picker.set_edited_resource(value)
		_observe_resource(value)
	add_child(_resource_picker)


func _build_line_edit(value: Variant) -> void:
	_line_edit = LineEdit.new()
	_line_edit.custom_minimum_size = Vector2(150, 0)
	_line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_line_edit.placeholder_text = _example_text()
	_line_edit.tooltip_text = (
			"Enter a %s value using Godot Variant syntax." % VARIANT_TYPES.display_name(data_type)
	)
	_line_edit.text = _format_value(value) if value != null else ""
	_line_edit.text_changed.connect(_on_text_changed)
	_line_edit.focus_entered.connect(_on_line_edit_focus_entered)
	add_child(_line_edit)


func _build_string_field(value: Variant) -> void:
	_string_field = STRING_FIELD_SCENE.instantiate() \
			as GDSQLEditorStringValueField
	_string_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_string_field)
	_string_field.configure(value, nullable, _editable)
	_string_field.text_changed.connect(_on_string_text_changed)
	_string_field.value_applied.connect(_on_string_value_applied)


func _on_null_toggled(enabled: bool) -> void:
	if _string_field != null:
		_string_field.set_null_state(enabled)
	_mark_modified()


func _on_resource_changed(_resource: Resource) -> void:
	_observe_resource(_resource)
	if _use_null != null and _resource_value() != null:
		_use_null.set_pressed_no_signal(false)
	_mark_modified()


func _on_resource_selected(resource: Resource, _inspect: bool) -> void:
	if resource != null:
		EditorInterface.edit_resource(resource)


func _on_text_changed(_text: String) -> void:
	if _use_null != null and _use_null.button_pressed:
		_use_null.set_pressed_no_signal(false)
	_mark_modified()


func _on_string_text_changed(_text: String) -> void:
	if _use_null != null and _use_null.button_pressed:
		_use_null.set_pressed_no_signal(false)
	_string_field.set_null_state(false)
	_mark_modified()


func _on_string_value_applied(value: Variant) -> void:
	var is_null := nullable and value == null
	if _use_null != null:
		_use_null.set_pressed_no_signal(is_null)
	_string_field.set_null_state(is_null)
	if value != null:
		_string_field.set_text(String(value))
	_mark_modified()


func _on_line_edit_focus_entered() -> void:
	if _line_edit != null and _line_edit.editable:
		_line_edit.edit()


func _on_observed_resource_changed() -> void:
	_mark_resource_modified_if_changed()


func _observe_resource(resource: Resource) -> void:
	if _observed_resource != null \
			and _observed_resource.changed.is_connected(_on_observed_resource_changed):
		_observed_resource.changed.disconnect(_on_observed_resource_changed)
	_observed_resource = resource
	_observed_resource_fingerprint = (
			hash(var_to_bytes_with_objects(resource)) if resource != null else 0
	)
	if _observed_resource != null \
			and not _observed_resource.changed.is_connected(_on_observed_resource_changed):
		_observed_resource.changed.connect(_on_observed_resource_changed)


func _mark_resource_modified_if_changed() -> void:
	if _observed_resource == null:
		return
	if hash(var_to_bytes_with_objects(_observed_resource)) != _observed_resource_fingerprint:
		_mark_modified()


func _connect_editor_inspector() -> void:
	if not Engine.is_editor_hint():
		return
	_editor_inspector = EditorInterface.get_inspector()
	if _editor_inspector != null \
			and not _editor_inspector.property_edited.is_connected(_on_inspector_property_edited):
		_editor_inspector.property_edited.connect(_on_inspector_property_edited)


func _disconnect_editor_inspector() -> void:
	if _editor_inspector != null \
			and _editor_inspector.property_edited.is_connected(_on_inspector_property_edited):
		_editor_inspector.property_edited.disconnect(_on_inspector_property_edited)
	_editor_inspector = null


func _on_inspector_property_edited(_property: String) -> void:
	if _editor_inspector != null \
			and _editor_inspector.get_edited_object() == _observed_resource:
		_mark_resource_modified_if_changed()


func _mark_modified() -> void:
	if _rebuilding:
		return
	_modified = true
	changed.emit()


func _resource_value() -> Resource:
	return (_resource_picker.get_edited_resource()
			if _resource_picker != null
			else null)


func _is_null() -> bool:
	return _use_null != null and _use_null.button_pressed


func _parse_text(text: String) -> Dictionary:
	match data_type:
		TYPE_STRING:
			return { "valid": true, "value": text }
		TYPE_STRING_NAME:
			return { "valid": true, "value": StringName(text) }
		TYPE_NODE_PATH:
			return { "valid": true, "value": NodePath(text) }
		TYPE_INT:
			if text.is_valid_int():
				return { "valid": true, "value": text.to_int() }
		TYPE_FLOAT:
			if text.is_valid_float():
				return { "valid": true, "value": text.to_float() }
		TYPE_BOOL:
			var normalized := text.strip_edges().to_lower()
			if normalized in ["true", "1"]:
				return { "valid": true, "value": true }
			if normalized in ["false", "0"]:
				return { "valid": true, "value": false }
		_:
			var value: Variant = str_to_var(text)
			if typeof(value) == data_type:
				return { "valid": true, "value": value }
	return { "valid": false, "value": null }


func _format_value(value: Variant) -> String:
	if value is String or value is StringName or value is NodePath:
		return String(value)
	return var_to_str(value)


func _example_text() -> String:
	match data_type:
		TYPE_BOOL:
			return "true"
		TYPE_INT:
			return "0"
		TYPE_FLOAT:
			return "0.0"
		TYPE_VECTOR2:
			return "Vector2(0, 0)"
		TYPE_VECTOR3:
			return "Vector3(0, 0, 0)"
		TYPE_COLOR:
			return "Color(1, 1, 1, 1)"
		TYPE_PACKED_VECTOR2_ARRAY:
			return "PackedVector2Array([Vector2(0, 0)])"
		TYPE_PACKED_VECTOR3_ARRAY:
			return "PackedVector3Array([Vector3(0, 0, 0)])"
	return VARIANT_TYPES.display_name(data_type)
