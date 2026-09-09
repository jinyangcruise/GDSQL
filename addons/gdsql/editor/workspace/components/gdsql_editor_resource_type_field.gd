@tool
class_name GDSQLEditorResourceTypeField
extends HBoxContainer
## Selects a Resource prototype and derives a concrete column type from it.
##
## The unrestricted picker supports native resources, globally named custom
## resources, and custom scripted resources without `class_name`.

signal constraint_changed(constraint: GDSQLResourceTypeConstraint)

var _configuring := false
var _picker: EditorResourcePicker
var _constraint: GDSQLResourceTypeConstraint
var _prototype: Resource
var _editable := true


func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	custom_minimum_size = Vector2(190, 46)
	_picker = EditorResourcePicker.new()
	_picker.base_type = "Resource"
	_picker.custom_minimum_size = Vector2(190, 46)
	_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_picker.resource_changed.connect(_on_resource_changed)
	_picker.resource_selected.connect(_on_resource_selected)
	add_child(_picker)
	_apply_configuration()


func configure(
		constraint: GDSQLResourceTypeConstraint = null,
		prototype: Resource = null,
		is_editable: bool = true,
) -> void:
	_configuring = true
	_constraint = constraint
	_prototype = prototype
	if _prototype == null and _constraint != null:
		_prototype = _constraint.instantiate_prototype()
	_editable = is_editable
	_apply_configuration()
	_configuring = false


func get_constraint() -> GDSQLResourceTypeConstraint:
	return GDSQLResourceTypeConstraint.from_resource(get_prototype())


func get_prototype() -> Resource:
	return _picker.get_edited_resource() if _picker != null else _prototype


func duplicate_prototype() -> Resource:
	var prototype := get_prototype()
	return prototype.duplicate(true) as Resource if prototype != null else null


func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return _editable and _resource_from_drop_data(data) != null


func _drop_data(_position: Vector2, data: Variant) -> void:
	if not _editable or _picker == null:
		return
	var resource := _resource_from_drop_data(data)
	if resource == null:
		return
	_picker.set_edited_resource(resource)
	_on_resource_changed(resource)


func _on_resource_changed(_resource: Resource) -> void:
	_prototype = _resource
	_constraint = GDSQLResourceTypeConstraint.from_resource(_resource)
	if not _configuring:
		constraint_changed.emit(_constraint)


func _on_resource_selected(resource: Resource, _inspect: bool) -> void:
	if resource != null:
		EditorInterface.edit_resource(resource)


func _apply_configuration() -> void:
	if _picker == null:
		return
	_picker.set_edited_resource(_prototype)
	_picker.editable = _editable


func _resource_from_drop_data(data: Variant) -> Resource:
	if not data is Dictionary:
		return null
	var drag_data := data as Dictionary
	match String(drag_data.get(&"type", "")):
		"resource":
			return drag_data.get(&"resource") as Resource
		"files":
			var files: PackedStringArray = drag_data.get(&"files", PackedStringArray())
			if files.size() == 1 and ResourceLoader.exists(files[0]):
				return ResourceLoader.load(files[0])
	return null
