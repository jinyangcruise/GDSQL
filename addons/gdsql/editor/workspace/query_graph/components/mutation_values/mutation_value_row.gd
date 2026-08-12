@tool
class_name GDSQLMutationValueRow
extends HBoxContainer
## One opt-in typed column value used by INSERT and UPDATE nodes.

signal changed

var _column: GDSQLColumnDefinition

@onready var _include: CheckBox = %Include
@onready var _column_name: Label = %ColumnName
@onready var _value: GDSQLEditorVariantValueField = %Value


func _ready() -> void:
	_include.toggled.connect(_on_include_toggled)
	_value.changed.connect(changed.emit)


func configure(
		column: GDSQLColumnDefinition,
		included: bool,
		assignable: bool = true,
) -> void:
	_column = column
	_column_name.text = "%s\n%s" % [column.name, type_string(column.data_type)]
	_column_name.tooltip_text = _column_tooltip(column, assignable)
	var available := (
			assignable
			and column.generation == GDSQLColumnDefinition.Generation.NONE
			and not column.auto_increment
	)
	_include.disabled = not available
	_include.button_pressed = included and available
	_value.configure(
		column.data_type,
		_initial_value(column),
		column.nullable,
		_include.button_pressed,
	)


func is_included() -> bool:
	return _include.button_pressed and not _include.disabled


func get_column_name() -> StringName:
	return _column.name if _column != null else &""


func get_value_result() -> Dictionary:
	return _value.get_value_result()


func _on_include_toggled(enabled: bool) -> void:
	_value.set_value_editable(enabled)
	changed.emit()


func _initial_value(column: GDSQLColumnDefinition) -> Variant:
	if column.has_default():
		return column.get_default_value()
	if column.nullable or column.data_type == TYPE_OBJECT:
		return null
	match column.data_type:
		TYPE_STRING:
			return ""
		TYPE_STRING_NAME:
			return &""
		TYPE_NODE_PATH:
			return NodePath()
		TYPE_BOOL:
			return false
		TYPE_INT:
			return 0
		TYPE_FLOAT:
			return 0.0
	return null


func _column_tooltip(column: GDSQLColumnDefinition, assignable: bool) -> String:
	if not assignable:
		return "Primary keys cannot be changed by UPDATE."
	if column.generation != GDSQLColumnDefinition.Generation.NONE:
		return "Generated columns are assigned by the runtime."
	if column.auto_increment:
		return "Auto-increment columns are assigned by the runtime."
	return "Include this column in the mutation."
