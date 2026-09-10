@tool
class_name GDSQLQueryTableResultTable
extends Tree
## Paginated result display with optional validated, batched cell editing.

signal inline_changes_changed(status: String)

const MINIMUM_COLUMN_WIDTH := 100
const MINIMUM_RESOURCE_COLUMN_WIDTH := 120
const MAXIMUM_COLUMN_WIDTH := 360
const COLUMN_HORIZONTAL_PADDING := 24
const TEXT_EDITOR_BUTTON_ID := 1
const SET_NULL_BUTTON_ID := 2
const EXPANDED_TEXT_EDITOR_SCRIPT := preload(
	"res://addons/gdsql/editor/workspace/components/text_editor/gdsql_editor_expanded_text_editor.gd"
)
const EXPAND_ICON := preload("res://addons/gdsql/editor/workspace/icons/pencil.svg")
const NULL_ICON := preload("res://addons/gdsql/editor/workspace/icons/eraser.svg")
const CELL_ACTION_WIDTH := 32.0
const RESOURCE_EDITOR_MINIMUM_ROW_HEIGHT := 44

@export var dirty_cell_color := Color(0.95, 0.68, 0.18, 0.24)
@export var invalid_cell_color := Color(0.95, 0.25, 0.25, 0.28)
@export var alternate_row_color := Color(1.0, 1.0, 1.0, 0.035)
@export_range(16, 64, 1) var resource_preview_size := 28

var _table: GDSQLTableDefinition
var _view_table: GDSQLTableDefinition
var _records: Array[GDSQLRowRecord] = []
var _can_edit_rows := false
var _safe_mode := true
var _insert_draft := false
var _rendering := false
var _updates: Dictionary[int, Dictionary] = { }
var _errors: Dictionary[Vector2i, String] = { }
var _resource_type_icons: Dictionary[StringName, Texture2D] = { }
var _resource_observers: Dictionary[Vector2i, Dictionary] = { }
var _preview_generation := 0
var _editor_inspector: EditorInspector
var _expanded_text_editor: GDSQLEditorExpandedTextEditor
var _expanded_text_cell := Vector2i(-1, -1)
var _resource_editor_host: Control
var _resource_picker: EditorResourcePicker
var _resource_editor_cell := Vector2i(-1, -1)
var _resource_picker_configuring := false
var _content_width := 0.0


func _ready() -> void:
	item_edited.connect(_on_item_edited)
	button_clicked.connect(_on_cell_button_clicked)
	item_mouse_selected.connect(_on_item_mouse_selected)
	_expanded_text_editor = EXPANDED_TEXT_EDITOR_SCRIPT.new() \
			as GDSQLEditorExpandedTextEditor
	add_child(_expanded_text_editor)
	_expanded_text_editor.value_applied.connect(_on_text_value_applied)
	_connect_editor_inspector()


func _exit_tree() -> void:
	_clear_resource_observers()
	_disconnect_editor_inspector()


func configure(
		table: GDSQLTableDefinition,
		view_table: GDSQLTableDefinition,
		records: Array[GDSQLRowRecord],
		can_edit_rows: bool,
) -> void:
	_close_resource_editor()
	_clear_resource_observers()
	_table = table
	_view_table = view_table
	_records = records
	_can_edit_rows = can_edit_rows
	_insert_draft = false
	clear_pending_changes()
	_resource_type_icons.clear()
	_content_width = 0.0


func configure_insert_draft(table: GDSQLTableDefinition, view_table: GDSQLTableDefinition) -> void:
	var insert_view := _build_insert_view_table(table, view_table)
	var values: Dictionary = { }
	if insert_view != null:
		for column in insert_view.columns:
			values[column.name] = _draft_initial_value(column)
	var records: Array[GDSQLRowRecord] = [GDSQLRowRecord.new(values)]
	configure(table, insert_view, records, true)
	_insert_draft = true
	set_safe_mode(false)
	render_page(0, 1, 0, 1)


func is_insert_draft() -> bool:
	return _insert_draft


func can_mutate() -> bool:
	return _can_edit_rows


func get_insert_values_result() -> Dictionary:
	if not _insert_draft or _table == null or _records.is_empty():
		return { "valid": false, "message": "No insert row is being edited.", "values": { } }
	var values: Dictionary = { }
	for column in _table.columns:
		if column.generation != GDSQLColumnDefinition.Generation.NONE or column.auto_increment:
			continue
		var value: Variant = _display_value(0, column.name, _records[0])
		if not column.accepts_value(value):
			var message := "%s expects %s." % [column.name, column.display_type_name()]
			_mark_insert_validation_error(column.name, message)
			return {
				"valid": false,
				"message": message,
				"values": { },
			}
		values[column.name] = value
	return { "valid": true, "message": "", "values": values }


func get_content_width() -> float:
	return _content_width


func estimate_height_for_rows(row_count: int) -> float:
	var font_height := get_theme_font(&"font").get_height(get_theme_font_size(&"font_size"))
	var row_height := maxf(
		float(resource_preview_size),
		font_height + float(get_theme_constant(&"v_separation")),
	)
	var title_height := get_theme_font(&"title_button_font").get_height(
		get_theme_font_size(&"title_button_font_size"),
	) + float(get_theme_constant(&"v_separation")) * 2.0
	return title_height + row_height * float(maxi(1, row_count)) + 120


func set_safe_mode(enabled: bool) -> void:
	_safe_mode = enabled
	if _safe_mode:
		_close_resource_editor()


func is_rendering() -> bool:
	return _rendering


func has_pending_changes() -> bool:
	return _insert_draft or not _updates.is_empty() or not _errors.is_empty()


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
				},
			)
	return pending


func get_selected_primary_keys() -> Array[Variant]:
	var primary_keys: Array[Variant] = []
	if _table == null:
		return primary_keys
	var item := get_next_selected(null)
	while item != null:
		var record_index := int(item.get_metadata(0))
		if record_index >= 0 and record_index < _records.size():
			primary_keys.append(_records[record_index].get_value(_table.primary_key))
		item = get_next_selected(item)
	return primary_keys


func restore_pending_updates(pending: Array[Dictionary]) -> void:
	if _table == null:
		return
	for update in pending:
		var record_index := _find_record_index(update.primary_key)
		if record_index >= 0:
			_updates[record_index] = (update.values as Dictionary).duplicate(true)


func render_page(
		first_index: int,
		end_index: int,
		selected_index: int,
		maximum_rows: int = -1,
) -> void:
	_rendering = true
	_preview_generation += 1
	_close_resource_editor()
	_clear_resource_observers()
	clear()
	if _view_table == null:
		_rendering = false
		return
	var bounded_first := clampi(first_index, 0, _records.size())
	var bounded_end := clampi(end_index, bounded_first, _records.size())
	if maximum_rows >= 0:
		bounded_end = mini(bounded_end, bounded_first + maximum_rows)
	columns = maxi(1, _view_table.columns.size())
	_content_width = 0.0
	for column_index in range(_view_table.columns.size()):
		var column := _view_table.columns[column_index]
		set_column_title(column_index, "%s" % [column.name])
		set_column_title_tooltip_text(
			column_index,
			"%s · %s" % [column.name, column.display_type_name()],
		)
		var preferred_width := _preferred_column_width(column, bounded_first, bounded_end)
		_content_width += preferred_width
		set_column_custom_minimum_width(column_index, preferred_width)
		set_column_expand(column_index, true)
		set_column_expand_ratio(column_index, preferred_width)
	var root := create_item()
	for record_index in range(bounded_first, bounded_end):
		var record := _records[record_index]
		var item := create_item(root)
		item.set_metadata(0, record_index)
		for column_index in range(_view_table.columns.size()):
			var column := _view_table.columns[column_index]
			var value: Variant = _display_value(record_index, column.name, record)
			_configure_cell(item, column_index, value, column.data_type == TYPE_OBJECT)
			_configure_cell_actions(item, column_index, column, value)
			item.set_editable(column_index, not _safe_mode and _cell_is_editable(column))
			if record_index % 2 == 1:
				item.set_custom_bg_color(column_index, alternate_row_color)
			var cell_key := Vector2i(record_index, column_index)
			if value is Resource:
				_queue_resource_preview(value, record_index, column_index)
				if not _safe_mode:
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
	var value: Variant = converted.value
	_apply_cell_value(record_index, column_index, column, value)


func _on_cell_button_clicked(
		item: TreeItem,
		column_index: int,
		button_id: int,
		_mouse_button_index: int,
) -> void:
	if item == null \
			or _view_table == null \
			or column_index < 0 \
			or column_index >= _view_table.columns.size():
		return
	var column := _view_table.columns[column_index]
	var record_index := int(item.get_metadata(0))
	if record_index < 0 or record_index >= _records.size():
		return
	match button_id:
		TEXT_EDITOR_BUTTON_ID:
			if column.data_type != TYPE_STRING:
				return
			_expanded_text_cell = Vector2i(record_index, column_index)
			_expanded_text_editor.edit_value(
				_display_value(record_index, column.name, _records[record_index]),
				column.nullable,
				not _safe_mode and _cell_is_editable(column),
				String(column.name),
			)
		SET_NULL_BUTTON_ID:
			if column.nullable and not _safe_mode and _cell_is_editable(column):
				_apply_cell_value(record_index, column_index, column, null)


func _on_text_value_applied(value: Variant) -> void:
	var record_index := _expanded_text_cell.x
	var column_index := _expanded_text_cell.y
	if _view_table == null \
			or record_index < 0 \
			or record_index >= _records.size() \
			or column_index < 0 \
			or column_index >= _view_table.columns.size():
		return
	var column := _view_table.columns[column_index]
	if column.data_type != TYPE_STRING \
			or not _cell_is_editable(column) \
			or (value == null and not column.nullable):
		return
	_apply_cell_value(record_index, column_index, column, value)


func _on_item_mouse_selected(mouse_position: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_LEFT:
		return
	if _safe_mode or _view_table == null:
		_close_resource_editor()
		return
	var item := get_item_at_position(mouse_position)
	var column_index := get_column_at_position(mouse_position)
	if item == null or column_index < 0 or column_index >= _view_table.columns.size():
		_close_resource_editor()
		return
	var column := _view_table.columns[column_index]
	if column.data_type != TYPE_OBJECT or not _cell_is_editable(column):
		_close_resource_editor()
		return
	var record_index := int(item.get_metadata(0))
	_open_resource_editor.call_deferred(record_index, column_index, column)


func _open_resource_editor(
		record_index: int,
		column_index: int,
		column: GDSQLColumnDefinition,
) -> void:
	if _safe_mode \
			or record_index < 0 \
			or record_index >= _records.size() \
			or not _cell_is_editable(column):
		return
	var cell_key := Vector2i(record_index, column_index)
	if _resource_editor_cell == cell_key and is_instance_valid(_resource_editor_host):
		return
	_close_resource_editor()
	var item := _visible_item(record_index)
	if item == null:
		return
	var value: Variant = _display_value(record_index, column.name, _records[record_index])
	_resource_editor_cell = cell_key
	_resource_editor_host = Control.new()
	_resource_editor_host.name = "ResourceCellEditor"
	_resource_editor_host.clip_contents = true
	_resource_editor_host.mouse_filter = Control.MOUSE_FILTER_STOP
	_resource_editor_host.z_index = 10
	add_child(_resource_editor_host)
	var background := Panel.new()
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.add_theme_stylebox_override(&"panel", get_theme_stylebox(&"panel", &"Tree"))
	_resource_editor_host.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_resource_picker = EditorResourcePicker.new()
	_resource_picker.editable = true
	_resource_picker.base_type = (
			column.resource_type.picker_base_type()
			if column.resource_type != null and column.resource_type.is_valid()
			else "Resource"
	)
	_resource_picker_configuring = true
	_resource_picker.set_edited_resource(value as Resource)
	_resource_picker_configuring = false
	_resource_picker.resource_changed.connect(_on_resource_picker_changed)
	_resource_picker.resource_selected.connect(_on_resource_picker_selected)
	_resource_picker.minimum_size_changed.connect(_on_resource_picker_minimum_size_changed)
	_resource_editor_host.add_child(_resource_picker)
	_update_resource_editor_row_height(item)
	_position_resource_editor(item, column, value)
	_hide_resource_cell_display(item, column_index)
	_resource_editor_host.move_to_front()
	_refresh_resource_editor_geometry.call_deferred(_resource_editor_cell)
	if value is Resource:
		_edit_resource_in_inspector.call_deferred(
			value,
			_resource_picker.get_instance_id(),
			_resource_editor_cell,
		)


func _position_resource_editor(
		item: TreeItem,
		column: GDSQLColumnDefinition,
		value: Variant,
) -> void:
	if not is_instance_valid(_resource_editor_host) or not is_instance_valid(_resource_picker):
		return
	var cell_rect := get_item_area_rect(item, _resource_editor_cell.y)
	var action_width := CELL_ACTION_WIDTH if column.nullable and value != null else 0.0
	_resource_editor_host.position = cell_rect.position
	_resource_editor_host.size = Vector2(
		maxf(1.0, cell_rect.size.x - action_width),
		cell_rect.size.y,
	)
	_resource_picker.position = Vector2.ZERO
	_resource_picker.size = _resource_editor_host.size


func _close_resource_editor() -> void:
	_restore_resource_cell_display()
	_resource_editor_cell = Vector2i(-1, -1)
	_resource_picker = null
	_resource_picker_configuring = false
	if is_instance_valid(_resource_editor_host):
		_resource_editor_host.hide()
		remove_child(_resource_editor_host)
		_resource_editor_host.queue_free()
	_resource_editor_host = null


func _hide_resource_cell_display(item: TreeItem, column_index: int) -> void:
	item.set_text(column_index, "")
	item.set_icon(column_index, null)
	item.set_custom_as_button(column_index, false)
	item.set_tooltip_text(column_index, "")
	item.set_editable(column_index, false)


func _restore_resource_cell_display() -> void:
	if _view_table == null:
		return
	var record_index := _resource_editor_cell.x
	var column_index := _resource_editor_cell.y
	if record_index < 0 \
			or record_index >= _records.size() \
			or column_index < 0 \
			or column_index >= _view_table.columns.size():
		return
	var item := _visible_item(record_index)
	if item == null:
		return
	item.set_custom_minimum_height(0)
	var column := _view_table.columns[column_index]
	var value: Variant = _display_value(record_index, column.name, _records[record_index])
	_configure_cell(item, column_index, value, true)
	_configure_cell_actions(item, column_index, column, value)
	item.set_editable(column_index, not _safe_mode and _cell_is_editable(column))


func _update_resource_editor_row_height(item: TreeItem) -> void:
	if not is_instance_valid(_resource_picker):
		return
	item.set_custom_minimum_height(
		maxi(
			RESOURCE_EDITOR_MINIMUM_ROW_HEIGHT,
			ceili(_resource_picker.get_combined_minimum_size().y),
		),
	)


func _on_resource_picker_minimum_size_changed() -> void:
	_refresh_resource_editor_geometry.call_deferred(_resource_editor_cell)


func _refresh_resource_editor_geometry(cell_key: Vector2i) -> void:
	if cell_key != _resource_editor_cell \
			or _view_table == null \
			or not is_instance_valid(_resource_picker):
		return
	var record_index := cell_key.x
	var column_index := cell_key.y
	if record_index < 0 \
			or record_index >= _records.size() \
			or column_index < 0 \
			or column_index >= _view_table.columns.size():
		return
	var item := _visible_item(record_index)
	if item == null:
		return
	var column := _view_table.columns[column_index]
	var value: Variant = _display_value(record_index, column.name, _records[record_index])
	_update_resource_editor_row_height(item)
	_position_resource_editor(item, column, value)


func _edit_resource_in_inspector(resource: Resource, picker_id: int, cell_key: Vector2i) -> void:
	if not is_instance_valid(_resource_picker) \
			or _resource_picker.get_instance_id() != picker_id \
			or _resource_editor_cell != cell_key:
		return
	EditorInterface.edit_resource(resource)
	inline_changes_changed.emit("Editing %s in the Inspector." % _resource_class_name(resource))


func _on_resource_picker_changed(resource: Resource) -> void:
	if _resource_picker_configuring or _view_table == null:
		return
	var record_index := _resource_editor_cell.x
	var column_index := _resource_editor_cell.y
	if record_index < 0 \
			or record_index >= _records.size() \
			or column_index < 0 \
			or column_index >= _view_table.columns.size():
		return
	var column := _view_table.columns[column_index]
	if (resource == null and not column.nullable) \
			or (resource != null and not column.accepts_value(resource)):
		var current := _display_value(record_index, column.name, _records[record_index]) \
				as Resource
		_resource_picker_configuring = true
		_resource_picker.set_edited_resource(current)
		_resource_picker_configuring = false
		inline_changes_changed.emit("%s expects %s." % [column.name, column.display_type_name()])
		return
	_apply_cell_value(record_index, column_index, column, resource)
	if resource != null:
		_edit_resource_in_inspector.call_deferred(
			resource,
			_resource_picker.get_instance_id(),
			_resource_editor_cell,
		)


func _on_resource_picker_selected(resource: Resource, _inspect: bool) -> void:
	if resource != null:
		_edit_resource_in_inspector(
			resource,
			_resource_picker.get_instance_id(),
			_resource_editor_cell,
		)


func _observe_resource(cell_key: Vector2i, column_name: StringName, resource: Resource) -> void:
	_unobserve_resource(cell_key)
	var callback := _on_observed_resource_changed.bind(
		cell_key.x,
		cell_key.y,
		column_name,
		resource,
	)
	if not resource.changed.is_connected(callback):
		resource.changed.connect(callback)
	var original: Variant = (
			_records[cell_key.x].get_value(column_name)
			if cell_key.x >= 0 and cell_key.x < _records.size()
			else null
	)
	var reference_changed := true
	if original is Resource:
		reference_changed = (original as Resource) != resource
	_resource_observers[cell_key] = {
		"resource": resource,
		"callback": callback,
		"fingerprint": _resource_fingerprint(resource),
		"reference_changed": reference_changed,
	}


func _unobserve_resource(cell_key: Vector2i) -> void:
	var observer: Dictionary = _resource_observers.get(cell_key, { })
	if observer.is_empty():
		return
	var resource := observer.get("resource") as Resource
	var callback := observer.get("callback") as Callable
	if resource != null and resource.changed.is_connected(callback):
		resource.changed.disconnect(callback)
	_resource_observers.erase(cell_key)


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
	var cell_key := Vector2i(record_index, column_index)
	var observer: Dictionary = _resource_observers.get(cell_key, { })
	if observer.is_empty() or observer.get("resource") != resource:
		return
	var resource_changed: bool = (
			bool(observer.get("reference_changed", false))
			or _resource_fingerprint(resource) != int(observer.get("fingerprint", 0))
	)
	if resource_changed:
		_set_update(record_index, column_name, resource)
	else:
		_remove_update(record_index, column_name)
	_errors.erase(cell_key)
	var item := _visible_item(record_index)
	if item != null:
		if resource_changed:
			item.set_custom_bg_color(column_index, dirty_cell_color)
		else:
			_restore_row_color(item, column_index, record_index)
	inline_changes_changed.emit(_dirty_status())


func _resource_fingerprint(resource: Resource) -> int:
	return hash(var_to_bytes_with_objects(resource))


func _connect_editor_inspector() -> void:
	if not Engine.is_editor_hint():
		return
	_editor_inspector = EditorInterface.get_inspector()
	if _editor_inspector != null \
			and not _editor_inspector.property_edited.is_connected(_on_inspector_property_edited):
		_editor_inspector.property_edited.connect(_on_inspector_property_edited)


func _disconnect_editor_inspector() -> void:
	if _editor_inspector != null \
			and _editor_inspector.property_edited.is_connected(_on_inspector_property_edited):
		_editor_inspector.property_edited.disconnect(_on_inspector_property_edited)
	_editor_inspector = null


func _on_inspector_property_edited(_property: String) -> void:
	if _editor_inspector == null:
		return
	var edited_resource := _editor_inspector.get_edited_object() as Resource
	if edited_resource == null:
		return
	for observer: Dictionary in _resource_observers.values():
		if observer.get("resource") == edited_resource:
			(observer.get("callback") as Callable).call()


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
	if _insert_draft:
		return _column_accepts_insert_value(table_column)
	return table_column != null \
			and table_column.generation == GDSQLColumnDefinition.Generation.NONE \
			and table_column.name != _table.primary_key


func _column_accepts_insert_value(column: GDSQLColumnDefinition) -> bool:
	return column != null \
			and column.generation == GDSQLColumnDefinition.Generation.NONE \
			and not column.auto_increment


func _build_insert_view_table(
		table: GDSQLTableDefinition,
		view_table: GDSQLTableDefinition,
) -> GDSQLTableDefinition:
	if table == null or view_table == null:
		return null
	var insert_view := GDSQLTableDefinition.new(view_table.name, view_table.primary_key)
	insert_view.database_name = view_table.database_name
	for column in view_table.columns:
		if _column_accepts_insert_value(table.get_column(column.name)):
			insert_view.add_column(column)
	return insert_view


func _mark_insert_validation_error(column_name: StringName, message: String) -> void:
	if _view_table == null:
		return
	for column_index in range(_view_table.columns.size()):
		if _view_table.columns[column_index].name != column_name:
			continue
		var cell_key := Vector2i(0, column_index)
		_errors[cell_key] = message
		var item := _visible_item(0)
		if item != null:
			item.set_custom_bg_color(column_index, invalid_cell_color)
			item.set_tooltip_text(column_index, message)
		return


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


func _apply_cell_value(
		record_index: int,
		column_index: int,
		column: GDSQLColumnDefinition,
		value: Variant,
) -> void:
	var cell_key := Vector2i(record_index, column_index)
	var original: Variant = _records[record_index].get_value(column.name)
	_errors.erase(cell_key)
	if value == original:
		_remove_update(record_index, column.name)
	else:
		_set_update(record_index, column.name, value)
	_unobserve_resource(cell_key)
	if value is Resource:
		_observe_resource(cell_key, column.name, value)
		_queue_resource_preview(value, record_index, column_index)
	var item := _visible_item(record_index)
	if item != null:
		_configure_cell(item, column_index, value, column.data_type == TYPE_OBJECT)
		_configure_cell_actions(item, column_index, column, value)
		_sync_resource_editor(cell_key, item, column, value)
		if value == original:
			_restore_row_color(item, column_index, record_index)
		else:
			item.set_custom_bg_color(column_index, dirty_cell_color)
	inline_changes_changed.emit(_dirty_status())


func _restore_row_color(item: TreeItem, column_index: int, record_index: int) -> void:
	if record_index % 2 == 1:
		item.set_custom_bg_color(column_index, alternate_row_color)
	else:
		item.clear_custom_bg_color(column_index)


func _dirty_status() -> String:
	if not _errors.is_empty():
		return "%d invalid field(s) must be corrected." % _errors.size()
	var field_count := 0
	for updates: Dictionary in _updates.values():
		field_count += updates.size()
	return "%d changed field(s) across %d row(s)." % [field_count, _updates.size()]


func _preferred_column_width(
		column: GDSQLColumnDefinition,
		first_index: int,
		end_index: int,
) -> int:
	var font := get_theme_font(&"font")
	var font_size := get_theme_font_size(&"font_size")
	var width := font.get_string_size(String(column.name), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var action_width := 0.0
	for record_index in range(first_index, end_index):
		var value: Variant = _display_value(record_index, column.name, _records[record_index])
		var value_width := font \
				.get_string_size(_value_text(value), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size) \
				.x
		if value is Resource:
			value_width += resource_preview_size + 6
		width = maxf(width, value_width)
		action_width = maxf(action_width, _cell_action_width(column, value))
	return clampi(
		ceili(width) + COLUMN_HORIZONTAL_PADDING,
		MINIMUM_RESOURCE_COLUMN_WIDTH if column.data_type == TYPE_OBJECT \
		else MINIMUM_COLUMN_WIDTH,
		MAXIMUM_COLUMN_WIDTH,
	) + ceili(action_width)


func _cell_action_width(column: GDSQLColumnDefinition, value: Variant) -> float:
	if _safe_mode:
		return 0.0
	var width := 0.0
	if column.data_type == TYPE_STRING:
		width += CELL_ACTION_WIDTH
	if column.nullable and value != null:
		width += CELL_ACTION_WIDTH
	return width


func _sync_resource_editor(
		cell_key: Vector2i,
		item: TreeItem,
		column: GDSQLColumnDefinition,
		value: Variant,
) -> void:
	if cell_key != _resource_editor_cell or not is_instance_valid(_resource_picker):
		return
	_resource_picker_configuring = true
	_resource_picker.set_edited_resource(value as Resource)
	_resource_picker_configuring = false
	_position_resource_editor(item, column, value)
	_hide_resource_cell_display(item, cell_key.y)


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


func _draft_initial_value(column: GDSQLColumnDefinition) -> Variant:
	if column.has_default():
		var value: Variant = column.get_default_value()
		return value.duplicate(true) if value is Resource else value
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
	item.set_icon(column_index, _resource_type_icon(value))
	item.set_icon_max_width(column_index, resource_preview_size)


func _configure_cell_actions(
		item: TreeItem,
		column_index: int,
		column: GDSQLColumnDefinition,
		value: Variant,
) -> void:
	for button_index in range(item.get_button_count(column_index) - 1, -1, -1):
		item.erase_button(column_index, button_index)
	if _safe_mode:
		return
	var editable := _cell_is_editable(column)
	if column.data_type == TYPE_STRING:
		item.add_button(
			column_index,
			EXPAND_ICON,
			TEXT_EDITOR_BUTTON_ID,
			not editable,
			"Open expanded text editor",
		)
	if column.nullable and value != null:
		item.add_button(
			column_index,
			NULL_ICON,
			SET_NULL_BUTTON_ID,
			not editable,
			"Set this value to NULL",
		)


func _value_text(value: Variant) -> String:
	if value == null:
		return "null"
	if value is Resource:
		var resource := value as Resource
		var script_class := _resource_script_class_name(resource)
		if not script_class.is_empty():
			return script_class
		return (
				resource.resource_path.get_file()
				if not resource.resource_path.is_empty()
				else resource.get_class()
		)
	if value is String or value is StringName or value is NodePath:
		return String(value)
	return var_to_str(value)


func _resource_tooltip(value: Variant, fallback: String) -> String:
	if not value is Resource:
		return fallback
	var resource := value as Resource
	var detail: String = (
			resource.resource_path if not resource.resource_path.is_empty() else fallback
	)
	return "%s · %s · Click to edit in the Inspector" % [_resource_class_name(resource), detail]


func _resource_class_name(resource: Resource) -> String:
	var script_class := _resource_script_class_name(resource)
	return script_class if not script_class.is_empty() else resource.get_class()


func _resource_script_class_name(resource: Resource) -> String:
	var script := resource.get_script() as Script
	if script == null:
		return ""
	var global_name := script.get_global_name()
	if global_name != &"":
		return String(global_name)
	return script.resource_path.get_file().get_basename()


func _resource_type_icon(value: Variant) -> Texture2D:
	if not value is Resource or not Engine.is_editor_hint():
		return null
	var resource := value as Resource
	var resource_class := StringName(_resource_class_name(resource))
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


func _queue_resource_preview(resource: Resource, record_index: int, column_index: int) -> void:
	if not Engine.is_editor_hint():
		return
	var previewer := EditorInterface.get_resource_previewer()
	if previewer == null:
		return
	previewer.queue_edited_resource_preview(
		resource,
		self,
		&"_on_resource_preview_ready",
		{
			"generation": _preview_generation,
			"record_index": record_index,
			"column_index": column_index,
			"resource_id": resource.get_instance_id(),
		},
	)


func _on_resource_preview_ready(
		_path: String,
		preview: Texture2D,
		thumbnail_preview: Texture2D,
		userdata: Variant,
) -> void:
	if not userdata is Dictionary:
		return
	var preview_data := userdata as Dictionary
	if int(preview_data.generation) != _preview_generation:
		return
	var record_index := int(preview_data.record_index)
	var column_index := int(preview_data.column_index)
	if (
			record_index < 0 or record_index >= _records.size() \
					or _view_table == null \
					or column_index < 0
			or column_index >= _view_table.columns.size()
	):
		return
	var column := _view_table.columns[column_index]
	var resource := _display_value(record_index, column.name, _records[record_index]) as Resource
	if resource == null or resource.get_instance_id() != int(preview_data.resource_id):
		return
	var resolved_preview := thumbnail_preview if thumbnail_preview != null else preview
	if resolved_preview == null:
		return
	var item := _visible_item(record_index)
	if item != null:
		item.set_icon(column_index, resolved_preview)
		item.set_icon_max_width(column_index, resource_preview_size)
