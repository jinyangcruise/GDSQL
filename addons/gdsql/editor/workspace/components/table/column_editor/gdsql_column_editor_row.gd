@tool
class_name GDSQLEditorColumnEditorRow
extends PanelContainer
## Scene-backed editor for one typed column draft.

signal changed
signal context_requested(column_draft: GDSQLEditorColumnDraft)
signal reorder_requested(
		source: GDSQLEditorColumnEditorRow,
		target: GDSQLEditorColumnEditorRow,
		insert_after: bool,
)

const KEY_ICON := preload("res://addons/gdsql/editor/workspace/icons/key.svg")
const FOREIGN_KEY_ICON := preload(
	"res://addons/gdsql/editor/workspace/icons/foreign_key.svg"
)
const COLUMN_ROW_DRAG_TYPE := &"gdsql_column_editor_row"
const VARIANT_TYPES := preload(
	"res://addons/gdsql/editor/workspace/components/gdsql_editor_variant_types.gd"
)
const RESOURCE_PICKER_SCRIPT := preload(
	"res://addons/gdsql/editor/workspace/components/resource/gdsql_editor_resource_picker.gd"
)

var draft: GDSQLEditorColumnDraft
var _configuring := false

@onready var _drag_handle: Button = %DragHandle
@onready var _name: LineEdit = %Name
@onready var _type: OptionButton = %Type
@onready var _resource_type: EditorResourcePicker = %ResourceType
@onready var _resource_type_name: Label = %ResourceTypeName
@onready var _resource_ownership: OptionButton = %ResourceOwnership
@onready var _nullable: CheckBox = %Nullable
@onready var _unique: CheckBox = %Unique
@onready var _auto_increment: CheckBox = %AutoIncrement
@onready var _has_default: CheckBox = %HasDefault
@onready var _default_value: GDSQLEditorVariantValueField = %DefaultValue
@onready var _generation: OptionButton = %Generation


func _ready() -> void:
	_drag_handle.set_drag_forwarding(
		_get_drag_data_from_handle,
		_can_drop_data_from_handle,
		_drop_data_from_handle,
	)
	_name.text_changed.connect(_on_name_changed)
	_type.item_selected.connect(_on_type_selected)
	_resource_type.resource_changed.connect(_on_resource_type_changed)
	_resource_type.resource_selected.connect(_on_resource_type_selected)
	_resource_ownership.item_selected.connect(_on_resource_ownership_selected)
	_nullable.toggled.connect(_on_nullable_toggled)
	_unique.toggled.connect(_on_unique_toggled)
	_auto_increment.toggled.connect(_on_auto_increment_toggled)
	_has_default.toggled.connect(_on_has_default_toggled)
	_default_value.changed.connect(_on_default_value_changed)
	_generation.item_selected.connect(_on_generation_selected)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or draft == null:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event == null \
			or mouse_event.button_index != MOUSE_BUTTON_RIGHT \
			or not mouse_event.pressed \
			or not get_global_rect().has_point(get_global_mouse_position()):
		return
	context_requested.emit(draft)
	get_viewport().set_input_as_handled()


func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	return _can_accept_reorder(data)


func _drop_data(position: Vector2, data: Variant) -> void:
	if not _can_accept_reorder(data):
		return
	var drag_data := data as Dictionary
	var source := drag_data.get(&"row") as GDSQLEditorColumnEditorRow
	reorder_requested.emit(source, self, position.y > size.y * 0.5)


func configure(column_draft: GDSQLEditorColumnDraft) -> void:
	_configuring = true
	draft = column_draft
	_name.text = draft.name
	_name.right_icon = (
			KEY_ICON if draft.is_primary
			else FOREIGN_KEY_ICON if draft.is_foreign
			else null
	)
	VARIANT_TYPES.select_type(_type, draft.data_type)
	_type.disabled = draft.original != null
	var shows_resource_type := draft.data_type == TYPE_OBJECT
	var shows_stored_type := shows_resource_type and draft.original != null
	_resource_type.visible = shows_resource_type and not shows_stored_type
	_resource_type_name.visible = shows_stored_type
	_resource_type_name.text = (
			draft.resource_type.display_name()
			if draft.resource_type != null
			else "Unspecified Resource"
	)
	_resource_type_name.tooltip_text = "Accepted Resource type: %s" % _resource_type_name.text
	_resource_type.set_edited_resource(draft.resource_prototype)
	_resource_type.editable = draft.original == null
	_resource_ownership.visible = shows_resource_type
	_resource_ownership.select(draft.resource_ownership)
	_resource_ownership.tooltip_text = (
		"Owned: store an independent Resource value in this database.\n"
		+ "Referenced: store a UID/path locator to an existing asset."
	)
	_nullable.set_pressed_no_signal(draft.nullable)
	_nullable.disabled = draft.is_primary
	_unique.set_pressed_no_signal(draft.unique)
	_unique.disabled = draft.is_primary
	_auto_increment.set_pressed_no_signal(draft.auto_increment)
	_auto_increment.disabled = not draft.is_primary or draft.data_type != TYPE_INT
	_has_default.set_pressed_no_signal(draft.has_default)
	_has_default.disabled = draft.generation != GDSQLColumnDefinition.Generation.NONE
	_configure_default_value()
	_generation.select(draft.generation)
	_generation.disabled = draft.data_type != TYPE_INT
	modulate = Color(0.72, 0.72, 0.72) if draft.remove else Color.WHITE
	_configuring = false


func set_removal_staged(enabled: bool) -> void:
	if draft == null or draft.is_primary:
		return
	draft.remove = enabled
	modulate = Color(0.72, 0.72, 0.72) if enabled else Color.WHITE


func sync_default_value() -> void:
	if draft == null or not draft.has_default:
		return
	var result := _default_value.get_value_result()
	draft.default_valid = bool(result.valid)
	if result.valid:
		draft.default_value = result.value
	draft.default_modified = draft.default_modified or _default_value.is_modified()


func focus_name() -> void:
	_name.grab_focus()
	_name.edit()


func _get_drag_data_from_handle(_position: Vector2) -> Variant:
	if draft == null:
		return null
	var preview := Label.new()
	preview.text = draft.name if not draft.name.is_empty() else "Unnamed column"
	_drag_handle.set_drag_preview(preview)
	return { &"type": COLUMN_ROW_DRAG_TYPE, &"row": self }


func _can_drop_data_from_handle(_position: Vector2, data: Variant) -> bool:
	return _can_accept_reorder(data)


func _drop_data_from_handle(position: Vector2, data: Variant) -> void:
	_drop_data(position, data)


func _can_accept_reorder(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	var drag_data := data as Dictionary
	if drag_data.get(&"type") != COLUMN_ROW_DRAG_TYPE:
		return false
	var source := drag_data.get(&"row") as GDSQLEditorColumnEditorRow
	return source != null and source != self and source.get_parent() == get_parent()


func _configure_default_value() -> void:
	_default_value.configure(
		draft.data_type,
		draft.default_value if draft.has_default else null,
		draft.nullable,
		draft.has_default and draft.generation == GDSQLColumnDefinition.Generation.NONE,
		draft.resource_type,
		draft.resource_ownership,
	)


func _on_name_changed(value: String) -> void:
	if _configuring:
		return
	draft.name = value
	changed.emit()


func _on_type_selected(_index: int) -> void:
	if _configuring:
		return
	draft.reset_for_type(VARIANT_TYPES.selected_type(_type))
	configure(draft)
	changed.emit()


func _on_resource_type_changed(resource: Resource) -> void:
	if _configuring:
		return
	if not RESOURCE_PICKER_SCRIPT.can_present(resource):
		_resource_type.set_edited_resource(null)
		return
	draft.resource_type = GDSQLResourceTypeConstraint.from_resource(resource)
	draft.resource_prototype = resource
	draft.resource_ownership = (
		GDSQLResourceOwnership.Mode.REFERENCED
		if not resource.resource_path.is_empty()
		else GDSQLResourceOwnership.Mode.OWNED
	)
	draft.default_valid = true
	if draft.has_default:
		draft.default_value = _resource_default_value()
		draft.default_modified = true
	_configure_default_value()
	if draft.default_value is Resource:
		EditorInterface.edit_resource(draft.default_value)
	changed.emit()


func _on_resource_ownership_selected(index: int) -> void:
	if _configuring:
		return
	draft.resource_ownership = index as GDSQLResourceOwnership.Mode
	if draft.has_default and draft.data_type == TYPE_OBJECT:
		draft.default_value = _resource_default_value()
		draft.default_modified = true
	_configure_default_value()
	changed.emit()


func _on_resource_type_selected(resource: Resource, _inspect: bool) -> void:
	if resource != null:
		EditorInterface.edit_resource(resource)


func _on_nullable_toggled(enabled: bool) -> void:
	if _configuring:
		return
	sync_default_value()
	draft.nullable = enabled
	_configure_default_value()
	changed.emit()


func _on_unique_toggled(enabled: bool) -> void:
	if not _configuring:
		draft.unique = enabled
		changed.emit()


func _on_auto_increment_toggled(enabled: bool) -> void:
	if not _configuring:
		draft.auto_increment = enabled
		changed.emit()


func _on_has_default_toggled(enabled: bool) -> void:
	if _configuring:
		return
	draft.has_default = enabled
	if enabled:
		if draft.data_type == TYPE_OBJECT:
			draft.default_value = _resource_default_value()
		elif draft.default_value == null and not draft.nullable:
			draft.default_value = _initial_value(draft.data_type)
		if draft.default_value is Resource:
			EditorInterface.edit_resource(draft.default_value)
	draft.default_modified = true
	_configure_default_value()
	changed.emit()


func _resource_default_value() -> Resource:
	if draft.resource_ownership == GDSQLResourceOwnership.Mode.REFERENCED:
		return draft.resource_prototype
	return draft.duplicate_resource_prototype()


func _on_default_value_changed() -> void:
	if _configuring:
		return
	sync_default_value()
	changed.emit()


func _on_generation_selected(index: int) -> void:
	if _configuring:
		return
	draft.generation = index as GDSQLColumnDefinition.Generation
	if draft.generation != GDSQLColumnDefinition.Generation.NONE:
		draft.has_default = false
	configure(draft)
	changed.emit()


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
