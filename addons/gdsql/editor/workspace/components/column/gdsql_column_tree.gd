@tool
class_name GDSQLEditorColumnTree
extends Tree
## Inline table-schema editor backed by native Tree cell modes and persistent
## editor controls aligned with cells that need richer content.

signal changed

enum Column {
	NAME,
	TYPE,
	RESOURCE_TYPE,
	NULLABLE,
	UNIQUE,
	AUTO_INCREMENT,
	HAS_DEFAULT,
	DEFAULT_VALUE,
	GENERATION,
	REMOVE,
}

const VARIANT_TYPES := preload(
	"res://addons/gdsql/editor/workspace/components/gdsql_editor_variant_types.gd"
)
const VARIANT_FIELD := preload(
	"res://addons/gdsql/editor/workspace/components/gdsql_editor_variant_value_field.gd"
)

@export_group("Column layout")
@export var name_column_width := 180
@export var type_column_width := 120
@export var resource_column_width := 260
@export var default_value_column_width := 300
@export var flag_column_width := 90
@export var inline_row_height := 40
@export var resource_row_height := 50
@export var cell_inset := 2.0
@export var type_popup_max_height := 420

var _entries: Array[Dictionary] = []
var _rendering := false
var _items: Dictionary = { }
var _type_editors: Dictionary = { }
var _resource_type_editors: Dictionary = { }
var _default_editors: Dictionary = { }
var _cell_hosts: Dictionary = { }
var _last_layout_signature := -1

@onready var _inline_editors: Control = %InlineEditors


func _ready() -> void:
	_configure_columns()
	item_edited.connect(_on_item_edited)
	resized.connect(_queue_inline_editor_layout)
	set_process(true)


func _process(_delta: float) -> void:
	if _items.is_empty():
		return
	var layout_values: Array[Variant] = [size, get_scroll()]
	for column_index in columns:
		layout_values.append(get_column_width(column_index))
	var signature := hash(layout_values)
	if signature == _last_layout_signature:
		return
	_last_layout_signature = signature
	_refresh_inline_editor_layout()


func configure_new_table() -> void:
	_entries.clear()
	_entries.append(_new_entry(true))
	_render()


func configure_existing(table: GDSQLTableDefinition) -> void:
	_entries.clear()
	for column in table.columns:
		_entries.append(_entry_from_column(column, column.name == table.primary_key))
	_render()


func add_draft_column() -> void:
	_entries.append(_new_entry(false))
	_render()
	changed.emit()


func build_definitions() -> Array[GDSQLColumnDefinition]:
	_sync_default_editors()
	var definitions: Array[GDSQLColumnDefinition] = []
	for entry in _entries:
		if not bool(entry.remove):
			definitions.append(_build_definition(entry))
	return definitions


func build_alterations() -> Array[GDSQLTableAlteration]:
	_sync_default_editors()
	var alterations: Array[GDSQLTableAlteration] = []
	for entry in _entries:
		var original := entry.original as GDSQLColumnDefinition
		if original == null:
			if not bool(entry.remove):
				alterations.append(GDSQLTableAlteration.add_column(_build_definition(entry)))
			continue
		if bool(entry.remove):
			alterations.append(GDSQLTableAlteration.drop_column(original.name))
			continue
		var requested_name := StringName(String(entry.name).strip_edges())
		if bool(entry.nullable) != original.nullable:
			alterations.append(
				GDSQLTableAlteration.set_column_nullable(original.name, bool(entry.nullable)),
			)
		if bool(entry.unique) != original.unique:
			alterations.append(
				GDSQLTableAlteration.set_column_unique(original.name, bool(entry.unique)),
			)
		if bool(entry.auto_increment) != original.auto_increment:
			alterations.append(
				GDSQLTableAlteration.set_column_auto_increment(
					original.name,
					bool(entry.auto_increment),
				),
			)
		if bool(entry.has_default):
			if not original.has_default() \
					or bool(entry.default_modified) \
					or entry.default_value != original.get_default_value():
				alterations.append(
					GDSQLTableAlteration.set_column_default(original.name, entry.default_value),
				)
		elif original.has_default():
			alterations.append(GDSQLTableAlteration.clear_column_default(original.name))
		if int(entry.generation) != original.generation:
			alterations.append(
				GDSQLTableAlteration.set_column_generation(
					original.name,
					int(entry.generation) as GDSQLColumnDefinition.Generation,
				),
			)
		if requested_name != original.name:
			alterations.append(GDSQLTableAlteration.rename_column(original.name, requested_name))
	return alterations


func get_validation_errors(primary_key: StringName) -> Array[String]:
	_sync_default_editors()
	var errors: Array[String] = []
	var names: Dictionary[StringName, bool] = { }
	var auto_increment_columns := 0
	for entry in _entries:
		if bool(entry.remove):
			continue
		var name := StringName(String(entry.name).strip_edges())
		if name == &"":
			errors.append("A column name is required.")
		elif not String(name).is_valid_identifier():
			errors.append("Column '%s' must be a valid identifier." % name)
		elif names.has(name):
			errors.append("Column '%s' is declared more than once." % name)
		names[name] = true
		var definition := _build_definition(entry)
		if not definition.has_valid_type_constraint():
			errors.append("Column '%s' requires a concrete Resource subtype." % name)
		if definition.auto_increment:
			auto_increment_columns += 1
			if definition.data_type != TYPE_INT:
				errors.append("Auto-increment column '%s' must use TYPE_INT." % name)
		if definition.generation != GDSQLColumnDefinition.Generation.NONE:
			if definition.data_type != TYPE_INT:
				errors.append("Generated column '%s' must use TYPE_INT." % name)
			if definition.auto_increment:
				errors.append("Column '%s' cannot be generated and auto-incremented." % name)
			if definition.has_default():
				errors.append("Generated column '%s' cannot declare a static default." % name)
		if definition.has_default():
			if not bool(entry.default_valid) or not definition.accepts_value(entry.default_value):
				errors.append(
					"Default for column '%s' must be a valid %s value."
					% [name, definition.expected_type_name()],
				)
	if names.is_empty():
		errors.append("A table requires at least one column.")
	if primary_key == &"" or not names.has(primary_key):
		errors.append("Primary key '%s' must reference a declared column." % primary_key)
	if auto_increment_columns > 1:
		errors.append("Only one auto-increment column is supported.")
	elif auto_increment_columns == 1:
		for entry in _entries:
			if not bool(entry.remove) and bool(entry.auto_increment) \
					and StringName(String(entry.name).strip_edges()) != primary_key:
				errors.append("Auto-increment is supported only on the primary key.")
	return errors


func has_column(column_name: StringName) -> bool:
	for entry in _entries:
		if not bool(entry.remove) \
				and StringName(String(entry.name).strip_edges()) == column_name:
			return true
	return false


func _configure_columns() -> void:
	var titles := [
		"Name",
		"Type",
		"Resource subtype",
		"Null",
		"Unique",
		"Auto",
		"Default",
		"Default value",
		"Generation",
		"Remove",
	]
	for column_index in columns:
		set_column_title(column_index, titles[column_index])
		set_column_clip_content(column_index, true)
		set_column_expand(column_index, column_index in [Column.NAME, Column.DEFAULT_VALUE])
		set_column_custom_minimum_width(
			column_index,
			_column_minimum_width(column_index),
		)


func _column_minimum_width(column_index: int) -> int:
	match column_index:
		Column.NAME:
			return name_column_width
		Column.TYPE:
			return type_column_width
		Column.RESOURCE_TYPE:
			return resource_column_width
		Column.DEFAULT_VALUE:
			return default_value_column_width
	return flag_column_width


func _render() -> void:
	_sync_default_editors()
	_clear_inline_editors()
	_rendering = true
	clear()
	var root := create_item()
	for entry_index in _entries.size():
		var item := create_item(root)
		item.set_metadata(Column.NAME, entry_index)
		item.custom_minimum_height = (
			resource_row_height
			if int(_entries[entry_index].data_type) == TYPE_OBJECT
			else inline_row_height
		)
		_items[entry_index] = item
		_render_entry(item, entry_index)
		_create_inline_editors(item, entry_index)
	_rendering = false
	_queue_inline_editor_layout()


func _render_entry(item: TreeItem, entry_index: int) -> void:
	var entry := _entries[entry_index]
	var is_primary := bool(entry.is_primary)

	item.set_text(Column.NAME, String(entry.name))
	item.set_editable(Column.NAME, true)

	item.set_cell_mode(Column.TYPE, TreeItem.CELL_MODE_CUSTOM)
	item.set_text(Column.TYPE, "")
	item.set_editable(Column.TYPE, false)

	if int(entry.data_type) == TYPE_OBJECT:
		item.set_cell_mode(Column.RESOURCE_TYPE, TreeItem.CELL_MODE_CUSTOM)
		item.set_text(Column.RESOURCE_TYPE, "")
		item.set_editable(Column.RESOURCE_TYPE, false)
	else:
		item.set_text(Column.RESOURCE_TYPE, "—")
		item.set_editable(Column.RESOURCE_TYPE, false)

	_set_check_cell(item, Column.NULLABLE, bool(entry.nullable), not is_primary)
	_set_check_cell(item, Column.UNIQUE, bool(entry.unique), not is_primary)
	_set_check_cell(
		item,
		Column.AUTO_INCREMENT,
		bool(entry.auto_increment),
		is_primary and int(entry.data_type) == TYPE_INT,
	)
	_set_check_cell(
		item,
		Column.HAS_DEFAULT,
		bool(entry.has_default),
		int(entry.generation) == GDSQLColumnDefinition.Generation.NONE,
	)

	item.set_cell_mode(Column.DEFAULT_VALUE, TreeItem.CELL_MODE_CUSTOM)
	item.set_text(Column.DEFAULT_VALUE, "" if entry.has_default else "—")
	item.set_editable(Column.DEFAULT_VALUE, false)

	item.set_cell_mode(Column.GENERATION, TreeItem.CELL_MODE_RANGE)
	item.set_text(Column.GENERATION, ",".join(GDSQLColumnDefinition.Generation.keys()))
	item.set_range(Column.GENERATION, int(entry.generation))
	item.set_editable(Column.GENERATION, int(entry.data_type) == TYPE_INT)

	_set_check_cell(item, Column.REMOVE, bool(entry.remove), not is_primary)
	if bool(entry.remove):
		for column_index in columns:
			item.set_custom_color(column_index, Color(0.72, 0.45, 0.45))


func _set_check_cell(item: TreeItem, column: int, value: bool, editable: bool) -> void:
	item.set_cell_mode(column, TreeItem.CELL_MODE_CHECK)
	item.set_checked(column, value)
	item.set_editable(column, editable)


func _on_item_edited() -> void:
	if _rendering:
		return
	var item := get_edited()
	var column := get_edited_column()
	if item == null:
		return
	var entry_index := int(item.get_metadata(Column.NAME))
	if entry_index < 0 or entry_index >= _entries.size():
		return
	var entry := _entries[entry_index]
	match column:
		Column.NAME:
			entry.name = item.get_text(column)
		Column.NULLABLE:
			entry.nullable = item.is_checked(column)
		Column.UNIQUE:
			entry.unique = item.is_checked(column)
		Column.AUTO_INCREMENT:
			entry.auto_increment = item.is_checked(column)
		Column.HAS_DEFAULT:
			_set_default_enabled(entry_index, item.is_checked(column))
			return
		Column.GENERATION:
			entry.generation = int(item.get_range(column))
			if int(entry.generation) != GDSQLColumnDefinition.Generation.NONE:
				entry.has_default = false
		Column.REMOVE:
			entry.remove = item.is_checked(column)
	_entries[entry_index] = entry
	_rebuild_entry(entry_index)
	changed.emit()


func _set_default_enabled(entry_index: int, enabled: bool) -> void:
	var entry := _entries[entry_index]
	entry.has_default = enabled
	if enabled:
		if int(entry.data_type) == TYPE_OBJECT:
			entry.default_value = _duplicate_prototype(entry)
		elif entry.default_value == null and not entry.nullable:
			entry.default_value = _initial_value(int(entry.data_type) as Variant.Type)
		if entry.default_value is Resource:
			EditorInterface.edit_resource(entry.default_value)
	entry.default_modified = true
	_entries[entry_index] = entry
	_rebuild_entry(entry_index)
	changed.emit()


func _rebuild_entry(entry_index: int) -> void:
	if not _items.has(entry_index):
		return
	_free_entry_inline_editors(entry_index)
	var item := _items[entry_index] as TreeItem
	_rendering = true
	item.custom_minimum_height = (
		resource_row_height
		if int(_entries[entry_index].data_type) == TYPE_OBJECT
		else inline_row_height
	)
	_render_entry(item, entry_index)
	_create_inline_editors(item, entry_index)
	_rendering = false
	_queue_inline_editor_layout()


func _create_inline_editors(item: TreeItem, entry_index: int) -> void:
	var entry := _entries[entry_index]
	var type_editor := OptionButton.new()
	type_editor.tooltip_text = "Column Variant type"
	type_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	VARIANT_TYPES.populate(type_editor)
	VARIANT_TYPES.select_type(type_editor, int(entry.data_type) as Variant.Type)
	type_editor.disabled = entry.original != null
	type_editor.item_selected.connect(_on_type_selected.bind(entry_index))
	_configure_type_popup(type_editor)
	_add_cell_editor(type_editor, entry_index, Column.TYPE)
	_type_editors[entry_index] = type_editor

	if int(entry.data_type) == TYPE_OBJECT:
		var resource_editor := GDSQLEditorResourceTypeField.new()
		resource_editor.tooltip_text = (
			"Select a Resource prototype to define the accepted subtype."
		)
		_add_cell_editor(resource_editor, entry_index, Column.RESOURCE_TYPE)
		resource_editor.configure(
			entry.resource_type as GDSQLResourceTypeConstraint,
			entry.resource_prototype as Resource,
			entry.original == null,
		)
		resource_editor.constraint_changed.connect(_on_resource_type_changed.bind(entry_index))
		_resource_type_editors[entry_index] = resource_editor

	if bool(entry.has_default):
		var default_editor: GDSQLEditorVariantValueField = VARIANT_FIELD.new()
		_add_cell_editor(default_editor, entry_index, Column.DEFAULT_VALUE)
		default_editor.configure(
			int(entry.data_type) as Variant.Type,
			entry.default_value,
			bool(entry.nullable),
			true,
			entry.resource_type as GDSQLResourceTypeConstraint,
		)
		default_editor.changed.connect(_on_default_changed.bind(entry_index))
		_default_editors[entry_index] = default_editor



func _add_cell_editor(editor: Control, entry_index: int, column: int) -> void:
	var host := Control.new()
	host.name = "Cell_%d_%d" % [entry_index, column]
	host.mouse_filter = Control.MOUSE_FILTER_PASS
	host.clip_contents = true
	_inline_editors.add_child(host)
	host.add_child(editor)
	editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cell_hosts[Vector2i(entry_index, column)] = host


func _on_type_selected(_selected_index: int, entry_index: int) -> void:
	if _rendering or not _type_editors.has(entry_index):
		return
	var type_editor := _type_editors[entry_index] as OptionButton
	var selected_type := VARIANT_TYPES.selected_type(type_editor)
	var entry := _entries[entry_index]
	if selected_type == (int(entry.data_type) as Variant.Type):
		return
	entry.data_type = selected_type
	entry.resource_type = null
	entry.resource_prototype = null
	entry.has_default = false
	entry.default_value = null
	entry.default_valid = true
	entry.generation = GDSQLColumnDefinition.Generation.NONE
	_entries[entry_index] = entry
	_rebuild_entry(entry_index)
	changed.emit()


func _on_resource_type_changed(constraint: GDSQLResourceTypeConstraint, entry_index: int) -> void:
	if not _resource_type_editors.has(entry_index):
		return
	var resource_editor := (_resource_type_editors[entry_index] as GDSQLEditorResourceTypeField)
	var entry := _entries[entry_index]
	entry.resource_type = constraint
	entry.resource_prototype = resource_editor.get_prototype()
	entry.default_valid = true
	entry.default_value = _duplicate_prototype(entry) if entry.has_default else null
	entry.default_modified = bool(entry.has_default)
	_entries[entry_index] = entry
	if _default_editors.has(entry_index):
		var default_editor := (_default_editors[entry_index] as GDSQLEditorVariantValueField)
		default_editor.configure(
			TYPE_OBJECT,
			entry.default_value,
			bool(entry.nullable),
			true,
			constraint,
		)
		if entry.default_value is Resource:
			EditorInterface.edit_resource(entry.default_value)
	_queue_inline_editor_layout()
	changed.emit()


func _on_default_changed(entry_index: int) -> void:
	_capture_default(entry_index, true)


func _capture_default(entry_index: int, emit_change: bool) -> void:
	if not _default_editors.has(entry_index):
		return
	var default_editor := (_default_editors[entry_index] as GDSQLEditorVariantValueField)
	var result := default_editor.get_value_result()
	var entry := _entries[entry_index]
	entry.default_valid = bool(result.valid)
	if result.valid:
		entry.default_value = result.value
	entry.default_modified = (bool(entry.default_modified) or default_editor.is_modified())
	_entries[entry_index] = entry
	if emit_change:
		changed.emit()


func _sync_default_editors() -> void:
	for entry_index: int in _default_editors.keys():
		if entry_index >= 0 and entry_index < _entries.size():
			_capture_default(entry_index, false)


func _clear_inline_editors() -> void:
	for host: Control in _cell_hosts.values():
		if is_instance_valid(host):
			_inline_editors.remove_child(host)
			host.queue_free()
	_cell_hosts.clear()
	_type_editors.clear()
	_resource_type_editors.clear()
	_default_editors.clear()
	_items.clear()
	_last_layout_signature = -1


func _free_entry_inline_editors(entry_index: int) -> void:
	for column in [Column.TYPE, Column.RESOURCE_TYPE, Column.DEFAULT_VALUE]:
		var key := Vector2i(entry_index, column)
		var host := _cell_hosts.get(key) as Control
		if host != null and is_instance_valid(host):
			_inline_editors.remove_child(host)
			host.queue_free()
		_cell_hosts.erase(key)
	_type_editors.erase(entry_index)
	_resource_type_editors.erase(entry_index)
	_default_editors.erase(entry_index)


func _queue_inline_editor_layout() -> void:
	_last_layout_signature = -1
	if is_inside_tree():
		call_deferred("_refresh_inline_editor_layout")


func _refresh_inline_editor_layout() -> void:
	if not is_inside_tree():
		return
	for entry_index: int in _items.keys():
		var item := _items[entry_index] as TreeItem
		if item == null:
			continue
		_layout_cell_host(entry_index, item, Column.TYPE)
		_layout_cell_editor(
			_cell_hosts.get(Vector2i(entry_index, Column.RESOURCE_TYPE)) as Control,
			item,
			Column.RESOURCE_TYPE,
		)
		_layout_cell_editor(
			_cell_hosts.get(Vector2i(entry_index, Column.DEFAULT_VALUE)) as Control,
			item,
			Column.DEFAULT_VALUE,
		)


func _layout_cell_host(entry_index: int, item: TreeItem, column: int) -> void:
	_layout_cell_editor(
		_cell_hosts.get(Vector2i(entry_index, column)) as Control,
		item,
		column,
	)


func _layout_cell_editor(editor: Control, item: TreeItem, column: int) -> void:
	if editor == null or not is_instance_valid(editor):
		return
	var cell_rect := get_item_area_rect(item, column)
	var visible_rect := Rect2(Vector2.ZERO, size)
	var probe := Vector2(cell_rect.position.x + 4.0, cell_rect.get_center().y)
	editor.visible = (
		cell_rect.size.x > cell_inset * 2.0 and cell_rect.size.y > cell_inset * 2.0
		and visible_rect.intersects(cell_rect) and get_item_at_position(probe) == item
	)
	if not editor.visible:
		return
	editor.position = cell_rect.position + Vector2(cell_inset, cell_inset)
	editor.size = Vector2(
		maxf(1.0, cell_rect.size.x - cell_inset * 2.0),
		maxf(1.0, cell_rect.size.y - cell_inset * 2.0),
	)


func _configure_type_popup(type_editor: OptionButton) -> void:
	var popup := type_editor.get_popup()
	popup.about_to_popup.connect(_constrain_type_popup.bind(popup))
	_constrain_type_popup(popup)


func _constrain_type_popup(popup: PopupMenu) -> void:
	var viewport_height := get_viewport_rect().size.y
	var maximum_height := mini(type_popup_max_height, maxi(180, int(viewport_height * 0.65)))
	popup.max_size = Vector2i(0, maximum_height)


func _new_entry(primary: bool) -> Dictionary:
	return {
		"original": null,
		"name": "id" if primary else "",
		"data_type": TYPE_INT,
		"resource_type": null,
		"resource_prototype": null,
		"nullable": not primary,
		"unique": primary,
		"auto_increment": primary,
		"has_default": false,
		"default_value": null,
		"default_valid": true,
		"default_modified": false,
		"generation": GDSQLColumnDefinition.Generation.NONE,
		"remove": false,
		"is_primary": primary,
	}


func _entry_from_column(column: GDSQLColumnDefinition, primary: bool) -> Dictionary:
	return {
		"original": column,
		"name": String(column.name),
		"data_type": column.data_type,
		"resource_type": column.resource_type,
		"resource_prototype": (
			column.resource_type.instantiate_prototype()
			if column.resource_type != null
			else null
		),
		"nullable": column.nullable,
		"unique": column.unique,
		"auto_increment": column.auto_increment,
		"has_default": column.has_default(),
		"default_value": column.get_default_value(),
		"default_valid": true,
		"default_modified": false,
		"generation": column.generation,
		"remove": false,
		"is_primary": primary,
	}


func _build_definition(entry: Dictionary) -> GDSQLColumnDefinition:
	var definition := GDSQLColumnDefinition.new(
		StringName(String(entry.name).strip_edges()),
		int(entry.data_type) as Variant.Type,
		bool(entry.nullable),
		bool(entry.unique),
		bool(entry.auto_increment),
	)
	definition.resource_type = entry.resource_type as GDSQLResourceTypeConstraint
	definition.generation = int(entry.generation) as GDSQLColumnDefinition.Generation
	if bool(entry.has_default):
		definition.set_default(entry.default_value)
	return definition


func _duplicate_prototype(entry: Dictionary) -> Resource:
	var prototype := entry.resource_prototype as Resource
	if prototype == null and entry.resource_type != null:
		prototype = (entry.resource_type as GDSQLResourceTypeConstraint).instantiate_prototype()
	return prototype.duplicate(true) as Resource if prototype != null else null


func _initial_value(data_type: Variant.Type) -> Variant:
	match data_type:
		TYPE_BOOL:
			return false
		TYPE_INT:
			return 0
		TYPE_FLOAT:
			return 0.0
		TYPE_STRING:
			return ""
		TYPE_STRING_NAME:
			return &""
		TYPE_NODE_PATH:
			return NodePath()
	return null
