@tool
class_name GDSQLEditorColumnEditorRow
extends PanelContainer
## Scene-backed editor for one typed column draft.

signal changed

const KEY_ICON := preload("res://addons/gdsql/editor/workspace/icons/key.svg")
const VARIANT_TYPES := preload(
	"res://addons/gdsql/editor/workspace/components/gdsql_editor_variant_types.gd"
)

var draft: GDSQLEditorColumnDraft
var _configuring := false

@onready var _name: LineEdit = %Name
@onready var _type: OptionButton = %Type
@onready var _resource_type: GDSQLEditorResourceTypeField = %ResourceType
@onready var _nullable: CheckBox = %Nullable
@onready var _unique: CheckBox = %Unique
@onready var _auto_increment: CheckBox = %AutoIncrement
@onready var _has_default: CheckBox = %HasDefault
@onready var _default_value: GDSQLEditorVariantValueField = %DefaultValue
@onready var _generation: OptionButton = %Generation
@onready var _remove: CheckBox = %Remove


func _ready() -> void:
	_name.text_changed.connect(_on_name_changed)
	_type.item_selected.connect(_on_type_selected)
	_resource_type.constraint_changed.connect(_on_resource_type_changed)
	_nullable.toggled.connect(_on_nullable_toggled)
	_unique.toggled.connect(_on_unique_toggled)
	_auto_increment.toggled.connect(_on_auto_increment_toggled)
	_has_default.toggled.connect(_on_has_default_toggled)
	_default_value.changed.connect(_on_default_value_changed)
	_generation.item_selected.connect(_on_generation_selected)
	_remove.toggled.connect(_on_remove_toggled)


func configure(column_draft: GDSQLEditorColumnDraft) -> void:
	_configuring = true
	draft = column_draft
	_name.text = draft.name
	_name.right_icon = KEY_ICON if draft.is_primary else null
	VARIANT_TYPES.select_type(_type, draft.data_type)
	_type.disabled = draft.original != null
	_resource_type.visible = draft.data_type == TYPE_OBJECT
	_resource_type.configure(
		draft.resource_type,
		draft.resource_prototype,
		draft.original == null,
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
	_remove.set_pressed_no_signal(draft.remove)
	_remove.disabled = draft.is_primary
	modulate = Color(0.72, 0.72, 0.72) if draft.remove else Color.WHITE
	_configuring = false


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


func _configure_default_value() -> void:
	_default_value.configure(
		draft.data_type,
		draft.default_value if draft.has_default else null,
		draft.nullable,
		draft.has_default and draft.generation == GDSQLColumnDefinition.Generation.NONE,
		draft.resource_type,
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


func _on_resource_type_changed(constraint: GDSQLResourceTypeConstraint) -> void:
	if _configuring:
		return
	draft.resource_type = constraint
	draft.resource_prototype = _resource_type.get_prototype()
	draft.default_valid = true
	if draft.has_default:
		draft.default_value = draft.duplicate_resource_prototype()
		draft.default_modified = true
	_configure_default_value()
	if draft.default_value is Resource:
		EditorInterface.edit_resource(draft.default_value)
	changed.emit()


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
			draft.default_value = draft.duplicate_resource_prototype()
		elif draft.default_value == null and not draft.nullable:
			draft.default_value = _initial_value(draft.data_type)
		if draft.default_value is Resource:
			EditorInterface.edit_resource(draft.default_value)
	draft.default_modified = true
	_configure_default_value()
	changed.emit()


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


func _on_remove_toggled(enabled: bool) -> void:
	if _configuring:
		return
	draft.remove = enabled
	modulate = Color(0.72, 0.72, 0.72) if enabled else Color.WHITE
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
