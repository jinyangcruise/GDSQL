@tool
extends MarginContainer
## Intent-first database creation request.

signal create_requested(
		database_name: StringName,
		data_root: String,
		storage_backend_id: StringName,
		database_role: StringName,
)
signal cancel_requested

enum Purpose {
	CONTENT,
	SAVE_SLOT,
	SETTINGS,
	CUSTOM,
}

var _content_root := "res://data"
var _applying_defaults := false

@onready var _purpose: OptionButton = %Purpose
@onready var _name: LineEdit = %DatabaseName
@onready var _data_root: LineEdit = %DataRoot
@onready var _backend: OptionButton = %StorageBackend
@onready var _advanced: CheckButton = %Advanced
@onready var _advanced_fields: VBoxContainer = %AdvancedFields
@onready var _purpose_description: Label = %PurposeDescription
@onready var _location_value: Label = %LocationValue
@onready var _storage_value: Label = %StorageValue
@onready var _role_value: Label = %RoleValue
@onready var _hint: Label = %Hint
@onready var _create: Button = %Create


func _ready() -> void:
	_purpose.item_selected.connect(_on_purpose_selected)
	_name.text_changed.connect(_on_name_changed)
	_data_root.text_changed.connect(_validate.unbind(1))
	_backend.item_selected.connect(_on_backend_selected)
	_advanced.toggled.connect(_advanced_fields.set_visible)
	_create.pressed.connect(_submit)
	%Cancel.pressed.connect(cancel_requested.emit)
	_advanced_fields.visible = _advanced.button_pressed
	if not _is_scene_preview():
		_apply_purpose_defaults()


func reset(default_root: String) -> void:
	_content_root = default_root
	_purpose.select(Purpose.CONTENT)
	_reset_form()


func reset_save_slot() -> void:
	_purpose.select(Purpose.SAVE_SLOT)
	_reset_form()


func _reset_form() -> void:
	_advanced.set_pressed_no_signal(false)
	_advanced_fields.hide()
	_apply_purpose_defaults()
	_name.grab_focus()
	_name.select_all()


func _on_purpose_selected(_index: int) -> void:
	_apply_purpose_defaults()


func _on_name_changed(_value: String) -> void:
	if not _applying_defaults and _selected_purpose() == Purpose.SAVE_SLOT:
		_applying_defaults = true
		_data_root.text = _save_root()
		_applying_defaults = false
	_refresh_summary()
	_validate()


func _on_backend_selected(_index: int) -> void:
	_refresh_summary()
	_validate()


func _apply_purpose_defaults() -> void:
	if not is_node_ready():
		return
	_applying_defaults = true
	match _selected_purpose():
		Purpose.CONTENT:
			_name.text = "content"
			_data_root.text = _content_root
			_backend.select(0)
		Purpose.SAVE_SLOT:
			_name.text = "save_1"
			_data_root.text = _save_root()
			_backend.select(1)
		Purpose.SETTINGS:
			_name.text = "settings"
			_data_root.text = "user://gdsql/settings"
			_backend.select(0)
		Purpose.CUSTOM:
			_name.text = ""
			_data_root.text = _content_root
			_backend.select(0)
	_applying_defaults = false
	_refresh_summary()
	_validate()


func _refresh_summary() -> void:
	if not is_node_ready():
		return
	match _selected_purpose():
		Purpose.CONTENT:
			_purpose_description.text = (
					"Authored game content shipped with the project. Runtime access is read-only."
			)
		Purpose.SAVE_SLOT:
			_purpose_description.text = (
					"Mutable player state for one save slot, hydrated into memory and checkpointed."
			)
		Purpose.SETTINGS:
			_purpose_description.text = (
					"Mutable settings shared independently from save slots."
			)
		Purpose.CUSTOM:
			_purpose_description.text = (
					"Explicit location and storage behavior without an automatic runtime role."
			)
	_location_value.text = _data_root.text.strip_edges()
	_storage_value.text = GDSQLStorageBackendIds.get_display_name(_selected_backend())
	var role := _selected_role()
	_role_value.text = "Not assigned" if role == &"" else String(role)


func _validate() -> void:
	if not is_node_ready():
		return
	_refresh_summary()
	var database_name := _name.text.strip_edges()
	var data_root := _data_root.text.strip_edges()
	var valid := not database_name.is_empty() and not data_root.is_empty()
	_create.disabled = not valid
	if database_name.is_empty():
		_hint.text = "Enter a database name."
	elif data_root.is_empty():
		_hint.text = "Choose a data root."
	elif _selected_backend() == GDSQLStorageBackendIds.IN_MEMORY:
		_hint.text = (
				"Rows load into memory. ConfigFile remains the hydration and checkpoint source."
		)
	else:
		_hint.text = "Catalog, schema, and rows use ConfigFile storage directly."


func _selected_purpose() -> Purpose:
	return _purpose.selected as Purpose


func _selected_backend() -> StringName:
	if _backend.selected == 1:
		return GDSQLStorageBackendIds.IN_MEMORY
	return GDSQLStorageBackendIds.CONFIG_FILE


func _selected_role() -> StringName:
	match _selected_purpose():
		Purpose.CONTENT:
			return GDSQLDatabaseRegistry.CONTENT_ROLE
		Purpose.SAVE_SLOT:
			return GDSQLDatabaseRegistry.SAVE_ROLE
		Purpose.SETTINGS:
			return GDSQLDatabaseRegistry.SETTINGS_ROLE
	return &""


func _save_root() -> String:
	var slot_name := _name.text.strip_edges()
	if slot_name.is_empty():
		slot_name = "save_1"
	return "user://gdsql/saves/%s" % slot_name


func _submit() -> void:
	if _create.disabled:
		return
	create_requested.emit(
		StringName(_name.text.strip_edges()),
		_data_root.text.strip_edges(),
		_selected_backend(),
		_selected_role(),
	)


func _is_scene_preview() -> bool:
	if not Engine.is_editor_hint():
		return false
	var edited_scene_root := EditorInterface.get_edited_scene_root()
	return edited_scene_root == self \
			or (edited_scene_root != null and edited_scene_root.is_ancestor_of(self))
