@tool
extends PanelContainer
## Editable schema properties for one existing catalog column.
##
## The data type remains read-only because type replacement requires an
## explicit add, migrate, and drop operation.

signal changed

const VARIANT_FIELD := preload(
	"res://addons/gdsql/editor/workspace/components/gdsql_editor_variant_value_field.gd",
)

var marked_for_removal: bool:
	get:
		return %Remove.button_pressed

var _column: GDSQLColumnDefinition
var _is_primary_key := false
var _configuring := false
var _default_editor: Control


func _ready() -> void:
	_default_editor = VARIANT_FIELD.new()
	_default_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_get_default_host().add_child(_default_editor)
	_default_editor.connect("changed", _emit_changed)
	%Name.text_changed.connect(_emit_changed.unbind(1))
	%Nullable.toggled.connect(_on_nullable_toggled)
	%Unique.toggled.connect(_emit_changed.unbind(1))
	%AutoIncrement.toggled.connect(_emit_changed.unbind(1))
	%HasDefault.toggled.connect(_on_has_default_toggled)
	%Generation.item_selected.connect(_on_generation_selected)
	%Remove.toggled.connect(_emit_changed.unbind(1))


func configure(
		column: GDSQLColumnDefinition,
		is_primary_key: bool = false,
) -> void:
	_configuring = true
	_column = column
	_is_primary_key = is_primary_key
	%Name.text = String(column.name)
	%Type.text = type_string(column.data_type)
	%PrimaryKey.text = "Primary key" if is_primary_key else ""
	%Nullable.button_pressed = column.nullable
	%Nullable.disabled = is_primary_key
	%Unique.button_pressed = column.unique
	%Unique.disabled = is_primary_key
	%AutoIncrement.button_pressed = column.auto_increment
	%AutoIncrement.disabled = not is_primary_key
	%HasDefault.button_pressed = column.has_default()
	_default_editor.call(
		"configure",
		column.data_type,
		column.get_default_value() if column.has_default() else null,
		column.nullable,
		column.has_default(),
	)
	%Generation.clear()
	for generation_name in GDSQLColumnDefinition.Generation.keys():
		%Generation.add_item(String(generation_name))
	%Generation.select(column.generation)
	%Generation.disabled = column.data_type != TYPE_INT
	%HasDefault.disabled = (
		column.generation != GDSQLColumnDefinition.Generation.NONE
	)
	%Remove.button_pressed = false
	%Remove.disabled = is_primary_key
	%Remove.tooltip_text = (
		"The primary-key column cannot be removed directly."
		if is_primary_key
		else "Drop this column and its stored values when changes are applied."
	)
	_configuring = false


func get_requested_name() -> StringName:
	return StringName(%Name.text.strip_edges())


func is_valid_draft() -> bool:
	if get_requested_name() == &"":
		return false
	if %Generation.selected != GDSQLColumnDefinition.Generation.NONE \
			and (
				%HasDefault.button_pressed
				or %AutoIncrement.button_pressed
			):
		return false
	if %HasDefault.button_pressed:
		var parsed: Dictionary = _default_editor.call("get_value_result")
		return parsed.valid and _column.accepts_value(parsed.value)
	return true


func build_alterations() -> Array[GDSQLTableAlteration]:
	var alterations: Array[GDSQLTableAlteration] = []
	if _column == null:
		return alterations
	if marked_for_removal:
		alterations.append(GDSQLTableAlteration.drop_column(_column.name))
		return alterations
	var requested_name := get_requested_name()
	if %Nullable.button_pressed != _column.nullable:
		alterations.append(
			GDSQLTableAlteration.set_column_nullable(
				_column.name,
				%Nullable.button_pressed,
			),
		)
	if %Unique.button_pressed != _column.unique:
		alterations.append(
			GDSQLTableAlteration.set_column_unique(
				_column.name,
				%Unique.button_pressed,
			),
		)
	if %AutoIncrement.button_pressed != _column.auto_increment:
		alterations.append(
			GDSQLTableAlteration.set_column_auto_increment(
				_column.name,
				%AutoIncrement.button_pressed,
			),
		)
	if %HasDefault.button_pressed:
		var parsed: Dictionary = _default_editor.call("get_value_result")
		if bool(_default_editor.call("is_modified")) \
				or not _column.has_default() \
				or parsed.value != _column.get_default_value():
			alterations.append(
				GDSQLTableAlteration.set_column_default(
					_column.name,
					parsed.value,
				),
			)
	elif _column.has_default():
		alterations.append(
			GDSQLTableAlteration.clear_column_default(_column.name),
		)
	var generation: GDSQLColumnDefinition.Generation = %Generation.selected
	if generation != _column.generation:
		alterations.append(
			GDSQLTableAlteration.set_column_generation(
				_column.name,
				generation,
			),
		)
	if requested_name != _column.name:
		alterations.append(
			GDSQLTableAlteration.rename_column(_column.name, requested_name),
		)
	return alterations


func _on_has_default_toggled(enabled: bool) -> void:
	_default_editor.call("set_value_editable", enabled)
	_emit_changed()


func _on_generation_selected(generation: int) -> void:
	var generated := generation != GDSQLColumnDefinition.Generation.NONE
	%HasDefault.disabled = generated
	_default_editor.call(
		"set_value_editable",
		%HasDefault.button_pressed and not generated,
	)
	_emit_changed()


func _on_nullable_toggled(nullable: bool) -> void:
	var current: Dictionary = _default_editor.call("get_value_result")
	_default_editor.call(
		"configure",
		_column.data_type,
		current.value if current.valid else null,
		nullable,
		%HasDefault.button_pressed,
	)
	_emit_changed()


func _emit_changed() -> void:
	if not _configuring:
		changed.emit()


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
