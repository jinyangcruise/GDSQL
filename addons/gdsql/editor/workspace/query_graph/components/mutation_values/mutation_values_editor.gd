@tool
class_name GDSQLMutationValuesEditor
extends Tree
## Native two-column Tree for one INSERT row or UPDATE assignments.

signal changed

enum Mode {
	INSERT,
	UPDATE,
}

const VALUE_COLUMN := 1
const TEXT_EDITOR_BUTTON_ID := 1
const SET_NULL_BUTTON_ID := 2
const EXPANDED_TEXT_EDITOR_SCRIPT := preload(
	"res://addons/gdsql/editor/workspace/components/text_editor/gdsql_editor_expanded_text_editor.gd"
)
const EDIT_ICON := preload("res://addons/gdsql/editor/workspace/icons/pencil.svg")
const NULL_ICON := preload("res://addons/gdsql/editor/workspace/icons/eraser.svg")

@export var mode := Mode.INSERT
@export var invalid_cell_color := Color(0.95, 0.25, 0.25, 0.28)

var _states: Dictionary = { }
var _rendering := false
var _expanded_text_editor: GDSQLEditorExpandedTextEditor
var _expanded_text_item: TreeItem


func _ready() -> void:
	columns = 2
	set_column_title(0, "Column / usage")
	set_column_title(VALUE_COLUMN, "Value")
	set_column_custom_minimum_width(0, 210)
	set_column_expand(0, false)
	set_column_expand(VALUE_COLUMN, true)
	item_edited.connect(_on_item_edited)
	button_clicked.connect(_on_button_clicked)
	_expanded_text_editor = EXPANDED_TEXT_EDITOR_SCRIPT.new() \
			as GDSQLEditorExpandedTextEditor
	add_child(_expanded_text_editor)
	_expanded_text_editor.value_applied.connect(_on_text_value_applied)


func configure(
		columns_to_edit: Array[GDSQLColumnDefinition],
		excluded_columns: Array[StringName] = [],
) -> void:
	_rendering = true
	clear()
	_states.clear()
	_expanded_text_item = null
	var root := create_item()
	for column in columns_to_edit:
		var assignable := (
				column.name not in excluded_columns
				and column.generation == GDSQLColumnDefinition.Generation.NONE
				and not column.auto_increment
		)
		var item := create_item(root)
		var state := {
			"column": column,
			"assignable": assignable,
			"included": mode == Mode.INSERT and assignable,
			"value": _initial_value(column),
			"valid": true,
			"raw_text": null,
		}
		_states[item] = state
		item.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
		item.set_text(0, "%s" % [column.name])
		item.set_tooltip_text(0, _column_tooltip(column, assignable))
		item.set_checked(0, bool(state.included))
		item.set_editable(0, assignable)
		_render_value_cell(item)
	_rendering = false
	changed.emit()


func build_values() -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	var values: Dictionary = { }
	for item: TreeItem in _ordered_items():
		var state: Dictionary = _states[item]
		if not bool(state.included):
			continue
		var column := state.column as GDSQLColumnDefinition
		if not bool(state.valid) or not column.accepts_value(state.value):
			state.valid = false
			_states[item] = state
			_render_value_cell(item)
			result.add_diagnostic(
				GDSQLQueryDiagnostic.new(
					&"GDSQL_QUERY_GRAPH_MUTATION_VALUE_INVALID",
					"Column '%s' does not contain a valid typed value." % column.name,
				),
			)
			return result
		values[column.name] = state.value
	if values.is_empty():
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_QUERY_GRAPH_MUTATION_VALUE_REQUIRED",
				"Select at least one column value.",
			),
		)
		return result
	result.value = values
	return result


func get_included_count() -> int:
	var count := 0
	for state: Dictionary in _states.values():
		if bool(state.included):
			count += 1
	return count


func _on_item_edited() -> void:
	if _rendering:
		return
	var item := get_edited()
	if item == null or not _states.has(item):
		return
	var state: Dictionary = _states[item]
	var edited_column := get_edited_column()
	if edited_column == 0:
		state.included = item.is_checked(0) and bool(state.assignable)
		_states[item] = state
		_render_value_cell(item)
		changed.emit()
		return
	if edited_column != VALUE_COLUMN or not bool(state.included):
		return
	var column := state.column as GDSQLColumnDefinition
	if column.data_type == TYPE_OBJECT:
		_open_resource(item)
		return
	var parsed := _parse_value(item.get_text(VALUE_COLUMN), column)
	state.valid = bool(parsed.valid)
	if state.valid:
		state.value = parsed.value
		state.raw_text = null
	else:
		state.raw_text = item.get_text(VALUE_COLUMN)
	_states[item] = state
	_render_value_cell(item)
	changed.emit()


func _on_button_clicked(
		item: TreeItem,
		column_index: int,
		button_id: int,
		_mouse_button_index: int,
) -> void:
	if item == null or column_index != VALUE_COLUMN or not _states.has(item):
		return
	var state: Dictionary = _states[item]
	if not bool(state.included):
		return
	var column := state.column as GDSQLColumnDefinition
	match button_id:
		TEXT_EDITOR_BUTTON_ID:
			if column.data_type == TYPE_STRING:
				_expanded_text_item = item
				_expanded_text_editor.edit_value(
					state.value,
					column.nullable,
					true,
					String(column.name),
				)
		SET_NULL_BUTTON_ID:
			if column.nullable:
				state.value = null
				state.valid = true
				state.raw_text = null
				_states[item] = state
				_render_value_cell(item)
				changed.emit()


func _on_text_value_applied(value: Variant) -> void:
	if _expanded_text_item == null or not _states.has(_expanded_text_item):
		return
	var state: Dictionary = _states[_expanded_text_item]
	state.value = value
	state.valid = true
	state.raw_text = null
	_states[_expanded_text_item] = state
	_render_value_cell(_expanded_text_item)
	changed.emit()


func _open_resource(item: TreeItem) -> void:
	var state: Dictionary = _states[item]
	var column := state.column as GDSQLColumnDefinition
	var value: Variant = state.value
	var resource: Resource = value if value is Resource else null
	if resource == null and column.resource_type != null:
		resource = column.resource_type.instantiate_prototype()
	if resource == null:
		state.valid = false
		_states[item] = state
		_render_value_cell(item)
		changed.emit()
		return
	state.value = resource
	state.valid = true
	state.raw_text = null
	_states[item] = state
	_render_value_cell(item)
	if Engine.is_editor_hint():
		EditorInterface.edit_resource(resource)
	changed.emit()


func _render_value_cell(item: TreeItem) -> void:
	var state: Dictionary = _states[item]
	var column := state.column as GDSQLColumnDefinition
	var included := bool(state.included)
	var value: Variant = state.value
	item.clear_buttons()
	item.clear_custom_bg_color(VALUE_COLUMN)
	item.set_icon(VALUE_COLUMN, _resource_icon(value))
	item.set_icon_max_width(VALUE_COLUMN, 24)
	if column.data_type == TYPE_OBJECT:
		item.set_cell_mode(VALUE_COLUMN, TreeItem.CELL_MODE_CUSTOM)
		item.set_custom_as_button(VALUE_COLUMN, true)
	else:
		item.set_cell_mode(VALUE_COLUMN, TreeItem.CELL_MODE_STRING)
		item.set_custom_as_button(VALUE_COLUMN, false)
	var raw_text: Variant = state.get("raw_text")
	item.set_text(VALUE_COLUMN, String(raw_text) if raw_text is String else _value_text(value))
	item.set_tooltip_text(VALUE_COLUMN, _value_tooltip(value, column))
	item.set_editable(VALUE_COLUMN, included)
	if column.data_type == TYPE_STRING:
		item.add_button(
			VALUE_COLUMN,
			EDIT_ICON,
			TEXT_EDITOR_BUTTON_ID,
			not included,
			"Open expanded text editor",
		)
	if column.nullable and value != null:
		item.add_button(
			VALUE_COLUMN,
			NULL_ICON,
			SET_NULL_BUTTON_ID,
			not included,
			"Set this value to NULL",
		)
	if included and not bool(state.valid):
		item.set_custom_bg_color(VALUE_COLUMN, invalid_cell_color)


func _ordered_items() -> Array[TreeItem]:
	var items: Array[TreeItem] = []
	var root := get_root()
	var item := root.get_first_child() if root != null else null
	while item != null:
		items.append(item)
		item = item.get_next()
	return items


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


func _parse_value(text: String, column: GDSQLColumnDefinition) -> Dictionary:
	var normalized := text.strip_edges()
	if normalized == "null" and column.nullable \
			and column.data_type not in [TYPE_STRING, TYPE_STRING_NAME, TYPE_NODE_PATH]:
		return { "valid": true, "value": null }
	var value: Variant
	match column.data_type:
		TYPE_STRING:
			value = text
		TYPE_STRING_NAME:
			value = StringName(text)
		TYPE_NODE_PATH:
			value = NodePath(text)
		TYPE_INT:
			if not text.is_valid_int():
				return { "valid": false, "value": null }
			value = text.to_int()
		TYPE_FLOAT:
			if not text.is_valid_float():
				return { "valid": false, "value": null }
			value = text.to_float()
		TYPE_BOOL:
			if normalized.to_lower() in ["true", "1"]:
				value = true
			elif normalized.to_lower() in ["false", "0"]:
				value = false
			else:
				return { "valid": false, "value": null }
		_:
			value = str_to_var(text)
			if typeof(value) != column.data_type:
				return { "valid": false, "value": null }
	return { "valid": true, "value": value }


func _value_text(value: Variant) -> String:
	if value == null:
		return "null"
	if value is Resource:
		var resource := value as Resource
		var script := resource.get_script() as Script
		if script != null:
			var global_name := script.get_global_name()
			return (
					String(global_name)
					if global_name != &""
					else script \
							.resource_path \
							.get_file() \
							.get_basename()
			)
		return resource.get_class()
	if value is String or value is StringName or value is NodePath:
		return String(value)
	return var_to_str(value)


func _value_tooltip(value: Variant, column: GDSQLColumnDefinition) -> String:
	if value is Resource:
		return "%s · Click to edit in the Inspector" % _value_text(value)
	return "%s value for %s" % [column.display_type_name(), column.name]


func _resource_icon(value: Variant) -> Texture2D:
	if not value is Resource or not Engine.is_editor_hint():
		return null
	var base := EditorInterface.get_base_control()
	if base == null:
		return null
	var icon_name := StringName((value as Resource).get_class())
	if not base.has_theme_icon(icon_name, &"EditorIcons"):
		icon_name = &"Resource"
	return (
			base.get_theme_icon(icon_name, &"EditorIcons")
			if base.has_theme_icon(icon_name, &"EditorIcons")
			else null
	)


func _column_tooltip(column: GDSQLColumnDefinition, assignable: bool) -> String:
	if not assignable:
		return "This column is assigned by the runtime or cannot be updated."
	return "Include this column in the mutation."
