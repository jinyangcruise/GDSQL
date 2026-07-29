@tool
extends PanelContainer
## Editable draft for one new table column.

signal changed
signal remove_requested(row: Control)

const VARIANT_TYPES := preload(
	"res://addons/gdsql/editor/workspace/components/gdsql_editor_variant_types.gd",
)
const VARIANT_FIELD := preload(
	"res://addons/gdsql/editor/workspace/components/gdsql_editor_variant_value_field.gd",
)

@onready var _name: LineEdit = $Margin/Fields/Name
@onready var _type: OptionButton = $Margin/Fields/Type
@onready var _nullable: CheckBox = $Margin/Fields/Nullable
@onready var _unique: CheckBox = $Margin/Fields/Unique
@onready var _auto_increment: CheckBox = $Margin/Fields/AutoIncrement
@onready var _has_default: CheckBox = %HasDefault
@onready var _generation: OptionButton = %Generation
var _default_editor: Control


func _ready() -> void:
	VARIANT_TYPES.populate(_type)
	VARIANT_TYPES.select_type(_type, TYPE_INT)
	_generation.select(GDSQLColumnDefinition.Generation.NONE)
	_default_editor = VARIANT_FIELD.new()
	_default_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_get_default_host().add_child(_default_editor)
	_default_editor.call(
		"configure",
		TYPE_INT,
		null,
		_nullable.button_pressed,
		false,
	)
	_name.text_changed.connect(changed.emit.unbind(1))
	_type.item_selected.connect(_on_type_selected)
	_nullable.toggled.connect(_on_nullable_toggled)
	_unique.toggled.connect(changed.emit.unbind(1))
	_auto_increment.toggled.connect(changed.emit.unbind(1))
	_has_default.toggled.connect(_on_has_default_toggled)
	_default_editor.connect("changed", changed.emit)
	_generation.item_selected.connect(_on_generation_selected)
	$Margin/Fields/Remove.pressed.connect(remove_requested.emit.bind(self))


func configure_primary_key() -> void:
	_name.text = "id"
	VARIANT_TYPES.select_type(_type, TYPE_INT)
	_nullable.button_pressed = false
	_unique.button_pressed = true
	_auto_increment.button_pressed = true
	_generation.disabled = false


func get_column_name() -> StringName:
	return StringName(_name.text.strip_edges())


func build_definition() -> GDSQLColumnDefinition:
	var definition := GDSQLColumnDefinition.new(
		get_column_name(),
		_selected_type(),
		_nullable.button_pressed,
		_unique.button_pressed,
		_auto_increment.button_pressed,
	)
	definition.generation = _generation.selected
	if _has_default.button_pressed:
		var default_result: Dictionary = _default_editor.call("get_value_result")
		definition.set_default(default_result.value)
	return definition


func is_valid_draft() -> bool:
	return get_validation_error().is_empty()


func get_validation_error() -> String:
	if get_column_name() == &"":
		return "A column name is required."
	if not String(get_column_name()).is_valid_identifier():
		return "Column '%s' must be a valid identifier." % get_column_name()
	if _type.selected < 0:
		return "Column '%s' requires a data type." % get_column_name()
	if _auto_increment.button_pressed and _selected_type() != TYPE_INT:
		return "Auto-increment column '%s' must use TYPE_INT." % get_column_name()
	if _generation.selected < GDSQLColumnDefinition.Generation.NONE:
		return "Column '%s' requires a generation policy." % get_column_name()
	if _generation.selected != GDSQLColumnDefinition.Generation.NONE:
		if _selected_type() != TYPE_INT:
			return "Generated column '%s' must use TYPE_INT." % get_column_name()
		if _auto_increment.button_pressed:
			return "Column '%s' cannot be generated and auto-incremented." \
					% get_column_name()
		if _has_default.button_pressed:
			return "Generated column '%s' cannot declare a static default." \
					% get_column_name()
	if _has_default.button_pressed:
		var parsed: Dictionary = _default_editor.call("get_value_result")
		if not parsed.valid:
			return "Default for column '%s' must be a valid %s value." % [
				get_column_name(),
				VARIANT_TYPES.display_name(_selected_type()),
			]
		var definition := GDSQLColumnDefinition.new(
			get_column_name(),
			_selected_type(),
			_nullable.button_pressed,
		)
		if not definition.accepts_value(parsed.value):
			return "Default for column '%s' does not match its type." \
					% get_column_name()
	return ""


func _on_has_default_toggled(enabled: bool) -> void:
	_default_editor.call("set_value_editable", enabled)
	changed.emit()


func _on_generation_selected(generation: int) -> void:
	var generated := generation != GDSQLColumnDefinition.Generation.NONE
	_has_default.disabled = generated
	_default_editor.call(
		"set_value_editable",
		_has_default.button_pressed and not generated,
	)
	changed.emit()


func _on_type_selected(_type_index: int) -> void:
	var supports_generation := _selected_type() == TYPE_INT
	_generation.disabled = not supports_generation
	_default_editor.call(
		"configure",
		_selected_type(),
		null,
		_nullable.button_pressed,
		_has_default.button_pressed,
	)
	if not supports_generation and _generation.selected \
			!= GDSQLColumnDefinition.Generation.NONE:
		_generation.select(GDSQLColumnDefinition.Generation.NONE)
		_on_generation_selected(GDSQLColumnDefinition.Generation.NONE)
	else:
		changed.emit()


func _on_nullable_toggled(nullable: bool) -> void:
	var current: Dictionary = _default_editor.call("get_value_result")
	_default_editor.call(
		"configure",
		_selected_type(),
		current.value if current.valid else null,
		nullable,
		_has_default.button_pressed,
	)
	changed.emit()


func _selected_type() -> Variant.Type:
	return VARIANT_TYPES.selected_type(_type)


func _get_default_host() -> Control:
	var host := get_node_or_null("%DefaultHost") as Control
	if host != null:
		return host
	var stale_field := get_node_or_null("Margin/Fields/DefaultValue") as Control
	if stale_field != null:
		stale_field.hide()
	host = HBoxContainer.new()
	host.name = "DefaultHost"
	host.custom_minimum_size = Vector2(220, 0)
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	$Margin/Fields.add_child(host)
	return host
