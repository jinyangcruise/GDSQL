@tool
class_name GDSQLEditorVariantValueField
extends HBoxContainer
## Reusable editor control for one typed Variant value.

signal changed

const VARIANT_TYPES := preload(
	"res://addons/gdsql/editor/workspace/components/gdsql_editor_variant_types.gd"
)

var data_type: Variant.Type = TYPE_NIL
var nullable := true
var _editable := true
var _line_edit: LineEdit
var _resource_picker: EditorResourcePicker
var _use_null: CheckBox
var _observed_resource: Resource
var _modified := false
var _rebuilding := false


func configure(
		target_type: Variant.Type,
		value: Variant = null,
		is_nullable: bool = true,
		is_editable: bool = true,
) -> void:
	_rebuilding = true
	data_type = target_type
	nullable = is_nullable
	_editable = is_editable
	_rebuild(value)
	_modified = false
	_rebuilding = false


func is_modified() -> bool:
	return _modified


func set_value_editable(enabled: bool) -> void:
	_editable = enabled
	if _line_edit != null:
		_line_edit.editable = enabled and not _is_null()
	if _resource_picker != null:
		_resource_picker.editable = enabled and not _is_null()
	if _use_null != null:
		_use_null.disabled = not enabled


func get_value_result() -> Dictionary:
	if data_type == TYPE_OBJECT:
		var resource := _resource_value()
		if resource is Resource:
			return { "valid": true, "value": resource }
		if _is_null():
			return { "valid": nullable, "value": null }
		return { "valid": false, "value": null }
	if _is_null():
		return { "valid": nullable, "value": null }
	if _line_edit == null:
		return { "valid": false, "value": null }
	return _parse_text(_line_edit.text)


func _rebuild(value: Variant) -> void:
	_observe_resource(null)
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_line_edit = null
	_resource_picker = null
	_use_null = null
	if data_type == TYPE_OBJECT:
		_build_resource_picker(value)
	else:
		_build_line_edit(value)
	if nullable:
		_use_null = CheckBox.new()
		_use_null.text = "Null"
		_use_null.button_pressed = value == null
		_use_null.toggled.connect(_on_null_toggled)
		add_child(_use_null)
	set_value_editable(_editable)


func _build_resource_picker(value: Variant) -> void:
	_resource_picker = EditorResourcePicker.new()
	_resource_picker.custom_minimum_size = Vector2(170, 0)
	_resource_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_resource_picker.base_type = "Resource"
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
			"Enter a %s value using Godot Variant syntax."
			% VARIANT_TYPES.display_name(data_type)
	)
	_line_edit.text = _format_value(value) if value != null else ""
	_line_edit.text_changed.connect(_on_text_changed)
	add_child(_line_edit)


func _on_null_toggled(enabled: bool) -> void:
	if _line_edit != null:
		_line_edit.editable = _editable and not enabled
	if _resource_picker != null:
		_resource_picker.editable = _editable and not enabled
	_mark_modified()


func _on_resource_changed(_resource: Resource) -> void:
	_observe_resource(_resource)
	if _use_null != null and _resource_value() != null:
		_use_null.button_pressed = false
	_mark_modified()


func _on_resource_selected(resource: Resource, _inspect: bool) -> void:
	if resource != null:
		EditorInterface.edit_resource(resource)


func _on_text_changed(_text: String) -> void:
	_mark_modified()


func _on_observed_resource_changed() -> void:
	_mark_modified()


func _observe_resource(resource: Resource) -> void:
	if _observed_resource != null \
			and _observed_resource.changed.is_connected(
				_on_observed_resource_changed,
			):
		_observed_resource.changed.disconnect(_on_observed_resource_changed)
	_observed_resource = resource
	if _observed_resource != null \
			and not _observed_resource.changed.is_connected(
				_on_observed_resource_changed,
			):
		_observed_resource.changed.connect(_on_observed_resource_changed)


func _mark_modified() -> void:
	if _rebuilding:
		return
	_modified = true
	changed.emit()


func _resource_value() -> Resource:
	return (
			_resource_picker.get_edited_resource()
			if _resource_picker != null
			else null
	)


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
