@tool
extends PanelContainer
## Editable presentation row that emits typed row mutation intents.

signal save_requested(
		original_primary_key: Variant,
		values: Dictionary,
)
signal delete_requested(primary_key: Variant)
signal discard_requested(row: Control)

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

@onready var _values: HBoxContainer = %Values
@onready var _status: Label = %Status
@onready var _save: Button = %Save
@onready var _delete: Button = %Delete


func _ready() -> void:
	_save.pressed.connect(_emit_save)
	_delete.pressed.connect(_emit_delete)
	%DeleteConfirmation.confirmed.connect(_confirm_delete)


func configure(
		table: GDSQLTableDefinition,
		source: GDSQLRowRecord = null,
) -> void:
	_table = table
	_source = source
	_original_primary_key = (
			source.get_value(table.primary_key)
			if source != null
			else null
	)
	_fields.clear()
	for child in _values.get_children():
		_values.remove_child(child)
		child.queue_free()
	for column in table.columns:
		var field_group := VBoxContainer.new()
		field_group.custom_minimum_size = Vector2(120, 0)
		field_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var field_label := Label.new()
		field_label.text = "%s (%s)" % [
			column.name,
			type_string(column.data_type),
		]
		field_group.add_child(field_label)
		var field := VARIANT_FIELD.new() as Control
		field.custom_minimum_size = Vector2(190, 0)
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		field.call(
			"configure",
			column.data_type,
			_initial_value(column, source),
			column.nullable,
			not _is_generated(column) \
					and not (source == null and column.auto_increment) \
					and not (
							source != null
							and column.name == table.primary_key
					),
		)
		field_group.add_child(field)
		_values.add_child(field_group)
		_fields[column.name] = field
	_delete.text = "Delete" if source != null else "Discard"
	_status.text = ""


func _emit_save() -> void:
	var conversion := _build_values()
	if not conversion.valid:
		_status.text = conversion.message
		return
	_status.text = ""
	save_requested.emit(_original_primary_key, conversion.values)


func _emit_delete() -> void:
	if _source == null:
		discard_requested.emit(self)
		return
	%DeleteConfirmation.dialog_text = (
			"Delete the row whose primary key is %s?"
			% _value_text(_original_primary_key)
	)
	%DeleteConfirmation.popup_centered(Vector2i(420, 160))


func _confirm_delete() -> void:
	delete_requested.emit(_original_primary_key)


func _build_values() -> Dictionary:
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
				"message": "%s: Expected %s." % [
					column.name,
					VARIANT_TYPES.display_name(column.data_type),
				],
				"values": { },
			}
		values[column.name] = converted.value
	return { "valid": true, "message": "", "values": values }


func _initial_value(
		column: GDSQLColumnDefinition,
		source: GDSQLRowRecord,
) -> Variant:
	if source != null:
		return source.get_value(column.name)
	if column.has_default():
		return column.get_default_value()
	return null


func _value_text(value: Variant) -> String:
	if value == null:
		return "null"
	if value is Resource:
		return value.resource_path
	if value is String or value is StringName:
		return String(value)
	return var_to_str(value)


func _is_generated(column: GDSQLColumnDefinition) -> bool:
	return column.generation != GDSQLColumnDefinition.Generation.NONE
