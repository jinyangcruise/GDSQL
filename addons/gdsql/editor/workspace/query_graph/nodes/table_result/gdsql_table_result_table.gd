@tool
class_name GDSQLQueryTableResultTable
extends Tree
## Paginated result display with optional validated, batched cell editing.

signal inline_changes_changed(status: String)

@export var dirty_cell_color := Color(0.95, 0.68, 0.18, 0.24)
@export var invalid_cell_color := Color(0.95, 0.25, 0.25, 0.28)

@export_range(16, 64, 1) var resource_preview_size := 28

var _table: GDSQLTableDefinition
var _view_table: GDSQLTableDefinition
var _records: Array[GDSQLRowRecord] = []
var _can_edit_rows := false
var _safe_mode := true
var _rendering := false
var _updates: Dictionary[int, Dictionary] = { }
var _errors: Dictionary[Vector2i, String] = { }
var _texture_previews: Dictionary[int, Texture2D] = { }
var _resource_type_icons: Dictionary[StringName, Texture2D] = { }
var _resource_observers: Dictionary[Vector2i, Dictionary] = { }


func _ready() -> void:
	item_edited.connect(_on_item_edited)


func _exit_tree() -> void:
	_clear_resource_observers()


func configure(
	table: GDSQLTableDefinition,
	view_table: GDSQLTableDefinition,
	records: Array[GDSQLRowRecord],
	can_edit_rows: bool,
) -> void:
	_clear_resource_observers()
	_table = table
	_view_table = view_table
	_records = records
	_can_edit_rows = can_edit_rows
	clear_pending_changes()
	_texture_previews.clear()
	_resource_type_icons.clear()


func set_safe_mode(enabled: bool) -> void:
	_safe_mode = enabled


func is_rendering() -> bool:
	return _rendering


func has_pending_changes() -> bool:
	return not _updates.is_empty() or not _errors.is_empty()


func has_validation_errors() -> bool:
	return not _errors.is_empty()


func clear_pending_changes() -> void:
	_updates.clear()
	_errors.clear()


func get_pending_updates() -> Array[Dictionary]:
	var pending: Array[Dictionary] = []
	if _table == null:
		return pending
	for record_index: int in _updates:
		var values: Dictionary = _updates[record_index]
		if not values.is_empty():
			pending.append(
				{
					"primary_key": _records[record_index].get_value(_table.primary_key),
					"values": values.duplicate(true),
				}
			)
	return pending


func restore_pending_updates(pending: Array[Dictionary]) -> void:
	if _table == null:
		return
	for update in pending:
		var record_index := _find_record_index(update.primary_key)
		if record_index >= 0:
			_updates[record_index] = (update.values as Dictionary).duplicate(true)


func render_page(first_index: int, end_index: int, selected_index: int) -> void:
	_rendering = true
	_clear_resource_observers()
	clear()
	if _view_table == null:
		_rendering = false
		return
	columns = maxi(1, _view_table.columns.size())
	for column_index in range(_view_table.columns.size()):
		var column := _view_table.columns[column_index]
		set_column_title(column_index, "%s (%s)" % [column.name, column.display_type_name()])
		set_column_title_tooltip_text(
			column_index,
			"%s · %s" % [column.name, column.display_type_name()],
		)
		set_column_custom_minimum_width(column_index, 60)
		set_column_expand(column_index, true)
		set_column_expand_ratio(column_index, 1)
		set_column_clip_content(column_index, true)
	var root := create_item()
	for record_index in range(first_index, end_index):
		var record := _records[record_index]
		var item := create_item(root)
		item.set_metadata(0, record_index)
		for column_index in range(_view_table.columns.size()):
			var column := _view_table.columns[column_index]
			var value: Variant = _display_value(record_index, column.name, record)
			_configure_cell(item, column_index, value, column.data_type == TYPE_OBJECT)
			item.set_editable(column_index, not _safe_mode and _cell_is_editable(column))
			var cell_key := Vector2i(record_index, column_index)
			if not _safe_mode and value is Resource:
				_observe_resource(cell_key, column.name, value)
			if _errors.has(cell_key):
				item.set_custom_bg_color(column_index, invalid_cell_color)
				item.set_tooltip_text(column_index, _errors[cell_key])
			elif _cell_is_dirty(record_index, column.name):
				item.set_custom_bg_color(column_index, dirty_cell_color)
		if record_index == selected_index:
			item.select(0)
	_rendering = false


func _find_record_index(primary_key: Variant) -> int:
	for index in range(_records.size()):
		if _records[index].get_value(_table.primary_key) == primary_key:
			return index
	return -1


func _on_item_edited() -> void:
	if _rendering or _safe_mode or _view_table == null:
		return
	var item := get_edited()
	var column_index := get_edited_column()
	if item == null or column_index < 0 or column_index >= _view_table.columns.size():
		return
	var record_index := int(item.get_metadata(0))
	if record_index < 0 or record_index >= _records.size():
		return
	var column := _view_table.columns[column_index]
	if not _cell_is_editable(column):
		return
	if column.data_type == TYPE_OBJECT:
		_open_resource_editor(record_index, column_index, column)
		return
	var converted := _parse_value(item.get_text(column_index), column)
	var cell_key := Vector2i(record_index, column_index)
	if not bool(converted.valid):
		_remove_update(record_index, column.name)
		_errors[cell_key] = String(converted.message)
		item.set_custom_bg_color(column_index, invalid_cell_color)
		item.set_tooltip_text(column_index, String(converted.message))
		inline_changes_changed.emit(String(converted.message))
		return
	_errors.erase(cell_key)
	var value: Variant = converted.value
	var original: Variant = _records[record_index].get_value(column.name)
	if value == original:
		_remove_update(record_index, column.name)
		item.clear_custom_bg_color(column_index)
	else:
		_set_update(record_index, column.name, value)
		item.set_custom_bg_color(column_index, dirty_cell_color)
	_configure_cell(item, column_index, value, false)
	inline_changes_changed.emit(_dirty_status())


func _open_resource_editor(
	record_index: int,
	_column_index: int,
	column: GDSQLColumnDefinition,
) -> void:
	var resource := _display_value(record_index, column.name, _records[record_index]) as Resource
	if resource == null:
		inline_changes_changed.emit("No Resource is assigned. Enable Safe Mode to select one.")
		return
	EditorInterface.edit_resource(resource)
	inline_changes_changed.emit("Editing %s in the Inspector." % resource.get_class())


func _observe_resource(cell_key: Vector2i, column_name: StringName, resource: Resource) -> void:
	var callback := _on_observed_resource_changed.bind(
		cell_key.x,
		cell_key.y,
		column_name,
		resource,
	)
	if not resource.changed.is_connected(callback):
		resource.changed.connect(callback)
	_resource_observers[cell_key] = { "resource": resource, "callback": callback }


func _clear_resource_observers() -> void:
	for observer: Dictionary in _resource_observers.values():
		var resource := observer.resource as Resource
		var callback := observer.callback as Callable
		if resource != null and resource.changed.is_connected(callback):
			resource.changed.disconnect(callback)
	_resource_observers.clear()


func _on_observed_resource_changed(
	record_index: int,
	column_index: int,
	column_name: StringName,
	resource: Resource,
) -> void:
	if record_index < 0 or record_index >= _records.size():
		return
	_set_update(record_index, column_name, resource)
	_errors.erase(Vector2i(record_index, column_index))
	var item := _visible_item(record_index)
	if item != null:
		item.set_custom_bg_color(column_index, dirty_cell_color)
	inline_changes_changed.emit(_dirty_status())


func _visible_item(record_index: int) -> TreeItem:
	var root := get_root()
	var item := root.get_first_child() if root != null else null
	while item != null:
		if int(item.get_metadata(0)) == record_index:
			return item
		item = item.get_next()
	return null


func _cell_is_editable(column: GDSQLColumnDefinition) -> bool:
	if not _can_edit_rows or _table == null:
		return false
	var table_column := _table.get_column(column.name)
	return (
		table_column != null and table_column.name != _table.primary_key
		and table_column.generation == GDSQLColumnDefinition.Generation.NONE
	)


func _display_value(record_index: int, column_name: StringName, record: GDSQLRowRecord) -> Variant:
	var updates: Dictionary = _updates.get(record_index, { })
	return updates.get(column_name, record.get_value(column_name))


func _cell_is_dirty(record_index: int, column_name: StringName) -> bool:
	var updates: Dictionary = _updates.get(record_index, { })
	return updates.has(column_name)


func _set_update(record_index: int, column_name: StringName, value: Variant) -> void:
	var updates: Dictionary = _updates.get(record_index, { })
	updates[column_name] = value
	_updates[record_index] = updates


func _remove_update(record_index: int, column_name: StringName) -> void:
	if not _updates.has(record_index):
		return
	var updates: Dictionary = _updates[record_index]
	updates.erase(column_name)
	if updates.is_empty():
		_updates.erase(record_index)
	else:
		_updates[record_index] = updates


func _dirty_status() -> String:
	if not _errors.is_empty():
		return "%d invalid field(s) must be corrected." % _errors.size()
	var field_count := 0
	for updates: Dictionary in _updates.values():
		field_count += updates.size()
	return "%d changed field(s) across %d row(s)." % [field_count, _updates.size()]


func _parse_value(text: String, column: GDSQLColumnDefinition) -> Dictionary:
	var normalized := text.strip_edges()
	if normalized == "null" \
			and column.nullable \
			and column.data_type not in [TYPE_STRING, TYPE_STRING_NAME, TYPE_NODE_PATH]:
		return { "valid": true, "value": null, "message": "" }
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
				return _invalid_value(column)
			value = text.to_int()
		TYPE_FLOAT:
			if not text.is_valid_float():
				return _invalid_value(column)
			value = text.to_float()
		TYPE_BOOL:
			if normalized.to_lower() in ["true", "1"]:
				value = true
			elif normalized.to_lower() in ["false", "0"]:
				value = false
			else:
				return _invalid_value(column)
		_:
			value = str_to_var(text)
			if typeof(value) != column.data_type:
				return _invalid_value(column)
	return { "valid": true, "value": value, "message": "" }


func _invalid_value(column: GDSQLColumnDefinition) -> Dictionary:
	return {
		"valid": false,
		"value": null,
		"message": "%s expects %s." % [column.name, column.display_type_name()],
	}


func _configure_cell(
	item: TreeItem,
	column_index: int,
	value: Variant,
	resource_cell: bool,
) -> void:
	var text := _value_text(value)
	item.set_cell_mode(
		column_index,
		TreeItem.CELL_MODE_CUSTOM if resource_cell else TreeItem.CELL_MODE_STRING,
	)
	item.set_custom_as_button(column_index, resource_cell)
	item.set_text(column_index, text)
	item.set_tooltip_text(column_index, _resource_tooltip(value, text))
	item.set_icon(column_index, _resource_icon(value))
	item.set_icon_max_width(column_index, resource_preview_size)


func _value_text(value: Variant) -> String:
	if value == null:
		return "null"
	if value is Resource:
		return value.resource_path.get_file() if not value.resource_path.is_empty() else value.get_class()
	if value is String or value is StringName or value is NodePath:
		return String(value)
	return var_to_str(value)


func _resource_tooltip(value: Variant, fallback: String) -> String:
	if not value is Resource:
		return fallback
	var detail: String = value.resource_path if not value.resource_path.is_empty() else fallback
	return "%s · %s · Click to edit in the Inspector" % [value.get_class(), detail]


func _resource_icon(value: Variant) -> Texture2D:
	if value is Texture2D:
		var preview := _texture_preview(value)
		if preview != null:
			return preview
	if not value is Resource:
		return null
	var resource_class := StringName(value.get_class())
	if _resource_type_icons.has(resource_class):
		return _resource_type_icons[resource_class]
	var base_control := EditorInterface.get_base_control()
	if base_control == null:
		return null
	var icon_name := resource_class
	if not base_control.has_theme_icon(icon_name, &"EditorIcons"):
		icon_name = &"Resource"
	if not base_control.has_theme_icon(icon_name, &"EditorIcons"):
		return null
	var icon := base_control.get_theme_icon(icon_name, &"EditorIcons")
	_resource_type_icons[resource_class] = icon
	return icon


func _texture_preview(texture: Texture2D) -> Texture2D:
	var key := texture.get_instance_id()
	if _texture_previews.has(key):
		return _texture_previews[key]
	var image := texture.get_image()
	if image == null or image.is_empty():
		return null
	var longest_side := maxi(image.get_width(), image.get_height())
	if longest_side > resource_preview_size:
		var scale := float(resource_preview_size) / float(longest_side)
		image.resize(
			maxi(1, roundi(image.get_width() * scale)),
			maxi(1, roundi(image.get_height() * scale)),
		)
	var preview := ImageTexture.create_from_image(image)
	_texture_previews[key] = preview
	return preview
