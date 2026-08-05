@tool
extends MarginContainer
## Workspace document for constructing one database creation request.

signal create_requested(
		database_name: StringName,
		data_root: String,
		storage_backend_id: StringName,
)
signal cancel_requested

@onready var _name: LineEdit = $Content/Form/DatabaseName
@onready var _data_root: LineEdit = $Content/Form/DataRoot
@onready var _backend: OptionButton = $Content/Form/StorageBackend
@onready var _hint: Label = $Content/Form/Hint
@onready var _create: Button = $Content/Form/Actions/Create


func _ready() -> void:
	_name.text_changed.connect(_validate.unbind(1))
	_data_root.text_changed.connect(_validate.unbind(1))
	_backend.item_selected.connect(_validate.unbind(1))
	_create.pressed.connect(_submit)
	$Content/Form/Actions/Cancel.pressed.connect(cancel_requested.emit)
	_validate()


func reset(default_root: String) -> void:
	_name.text = ""
	_data_root.text = default_root
	_backend.select(0)
	_validate()
	_name.grab_focus()


func _validate() -> void:
	var valid := not _name.text.strip_edges().is_empty() \
			and not _data_root.text.strip_edges().is_empty()
	_create.disabled = not valid
	if not valid:
		_hint.text = "A database name and data root are required."
	elif _selected_backend() == GDSQLStorageBackendIds.IN_MEMORY:
		_hint.text = (
				"Runtime rows use an in-memory working set. The ConfigFile "
				+ "catalog remains the hydration and checkpoint source."
		)
	else:
		_hint.text = "Catalog, schema, and rows use ConfigFile storage."


func _selected_backend() -> StringName:
	if _backend.selected == 1:
		return GDSQLStorageBackendIds.IN_MEMORY
	return GDSQLStorageBackendIds.CONFIG_FILE


func _submit() -> void:
	if _create.disabled:
		return
	create_requested.emit(
		StringName(_name.text.strip_edges()),
		_data_root.text.strip_edges(),
		_selected_backend(),
	)
