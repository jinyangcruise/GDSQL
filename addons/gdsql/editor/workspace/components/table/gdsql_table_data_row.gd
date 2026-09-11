@tool
extends PanelContainer
## Reusable typed row-value editor. Its parent owns mutation actions.

signal dirty_changed(row: Control, dirty: bool)

const VARIANT_TYPES := preload(
	"res://addons/gdsql/editor/workspace/components/gdsql_editor_variant_types.gd"
)
const VARIANT_FIELD := preload(
	"res://addons/gdsql/editor/workspace/components/gdsql_editor_variant_value_field.gd"
)

var _table: GDSQLTableDefinition
var _source: GDSQLRowRecord
var _fields: Dictionary[StringName, Control] = { }
var _original_primary_key: Variant
var _allow_mutation := true
var _dirty := false

@onready var _values: HBoxContainer = %Values
@onready var _status: Label = %Status


func configure(
	table: GDSQLTableDefinition,
	source: GDSQLRowRecord = null,
	allow_mutation: bool = true,
) -> void:
	_table = table
	_source = source
	_allow_mutation = allow_mutation
	_original_primary_key = (source.get_value(table.primary_key)
		if source != null
		else null)
	_fields.clear()
	for child in _values.get_children():
		_values.remove_child(child)
		child.queue_free()
	for column in table.columns:
		var field_group := VBoxContainer.new()
		field_group.custom_minimum_size = Vector2(120, 0)
		field_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var field := VARIANT_FIELD.new() as Control
		field.custom_minimum_size = Vector2(140, 0)

		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		field.call(
			"configure",
			column.data_type,
			_initial_value(column, source),
			column.nullable,
			_allow_mutation \
					and not _is_generated(column) \
					and not (source == null and column.auto_increment) \
					and not (source != null and column.name == table.primary_key),
			column.resource_type,
		)
		field.connect("changed", _mark_dirty)
		field_group.add_child(field)
		_values.add_child(field_group)
		_fields[column.name] = field
	_status.text = ""
	_set_dirty(source == null and _allow_mutation)


func is_dirty() -> bool:
	return _dirty


func get_values_result() -> Dictionary:
	if not _allow_mutation:
		return { "valid": false, "message": "This query result is read only.", "values": { } }
	var values: Dictionary = { }
	for column in _table.columns:
		if _is_generated(column) \
				or (_source == null and column.auto_increment):
			continue
		var field: Control = _fields.get(column.name)
		var converted: Dictionary = field.call("get_value_result")
		if not converted.valid:
			return {
				"valid": false,
				"message": "%s: Expected %s."
				% [column.name, VARIANT_TYPES.display_name(column.data_type)],
				"values": { },
			}
		values[column.name] = converted.value
	return { "valid": true, "message": "", "values": values }


func get_original_primary_key() -> Variant:
	return _original_primary_key


func can_mutate() -> bool:
	return _allow_mutation


func set_status(message: String) -> void:
	_status.text = message


func _initial_value(column: GDSQLColumnDefinition, source: GDSQLRowRecord) -> Variant:
	if source != null:
		return source.get_value(column.name)
	if column.has_default():
		return column.get_default_value()
	return null


func _is_generated(column: GDSQLColumnDefinition) -> bool:
	return column.generation != GDSQLColumnDefinition.Generation.NONE


func _mark_dirty() -> void:
	_set_dirty(true)


func _set_dirty(dirty: bool) -> void:
	_dirty = dirty
	dirty_changed.emit(self, dirty)
