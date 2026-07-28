@tool
class_name GDSQLWorkspace
extends Control
## Central GDSQL editor workspace for welcome and database task pages.

signal database_create_submitted(database_name: StringName, data_root: String)

@onready var _toolbar_actions: GDSQLEditorActionStrip = \
		$Layout/Toolbar/ToolbarMargin/ToolbarRow/ActionStrip
@onready var _welcome_actions: GDSQLEditorActionStrip = \
		$Layout/Content/Welcome/WelcomePanel/WelcomeMargin/WelcomeContent/WelcomeActions
@onready var _welcome: CenterContainer = $Layout/Content/Welcome
@onready var _database_view: MarginContainer = \
		$Layout/Content/DatabaseOverview
@onready var _database_title: Label = \
		$Layout/Content/DatabaseOverview/OverviewMargin/Overview/DatabaseTitle
@onready var _database_details: Label = \
		$Layout/Content/DatabaseOverview/OverviewMargin/Overview/DatabaseDetails
@onready var _tables: Tree = \
		$Layout/Content/DatabaseOverview/OverviewMargin/Overview/Tables
@onready var _create_dialog: ConfirmationDialog = $CreateDatabaseDialog
@onready var _database_name: LineEdit = \
		$CreateDatabaseDialog/DialogMargin/DialogFields/DatabaseName
@onready var _data_root: LineEdit = \
		$CreateDatabaseDialog/DialogMargin/DialogFields/DataRoot
@onready var _dialog_hint: Label = \
		$CreateDatabaseDialog/DialogMargin/DialogFields/DialogHint

var _action_hub: GDSQLEditorActionHub
var _active_registration: StringName


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tables.set_column_title(0, "Table")
	_tables.set_column_title(1, "Rows")
	_tables.set_column_title(2, "Columns")
	_tables.set_column_title(3, "Indexes")
	_create_dialog.confirmed.connect(_submit_database_creation)
	_database_name.text_changed.connect(_validate_database_form)
	_data_root.text_changed.connect(_validate_database_form)
	_tables.item_selected.connect(_on_table_selected)
	_tables.item_activated.connect(_on_table_selected)
	show_welcome()
	if _action_hub != null:
		configure(_action_hub)


func configure(action_hub: GDSQLEditorActionHub) -> void:
	_action_hub = action_hub
	if not is_node_ready():
		return
	var actions: Array[StringName] = [
		GDSQLEditorActionIds.CREATE_DATABASE,
		GDSQLEditorActionIds.DISCOVER_PROJECT,
		GDSQLEditorActionIds.REFRESH_DATABASES,
	]
	_toolbar_actions.configure(_action_hub, actions)
	_welcome_actions.configure(
		_action_hub,
		[
			GDSQLEditorActionIds.CREATE_DATABASE,
			GDSQLEditorActionIds.DISCOVER_PROJECT,
		],
	)


func show_welcome() -> void:
	if not is_node_ready():
		return
	_active_registration = &""
	_welcome.visible = true
	_database_view.visible = false


func show_database(
		inspection: GDSQLDatabaseInspection,
		session: GDSQLWorkbenchSession,
) -> void:
	if not is_node_ready() or inspection == null or session == null:
		return
	_active_registration = inspection.registration.name
	_welcome.visible = false
	_database_view.visible = true
	_database_title.text = String(inspection.registration.name)
	_database_details.text = (
			"%s  ·  %s  ·  %s"
			% [
				inspection.registration.database_name,
				GDSQLStorageBackendIds.get_display_name(
					inspection.registration.storage_backend_id,
				),
				inspection.registration.data_root,
			]
	)
	_render_tables(inspection, session)


func open_create_database_dialog(default_root: String = "res://data") -> void:
	_database_name.text = ""
	_data_root.text = default_root
	_dialog_hint.text = ""
	_validate_database_form("")
	_create_dialog.popup_centered(Vector2i(480, 250))
	_database_name.grab_focus()


func get_active_registration() -> StringName:
	return _active_registration


func _render_tables(
		inspection: GDSQLDatabaseInspection,
		session: GDSQLWorkbenchSession,
) -> void:
	_tables.clear()
	var root := _tables.create_item()
	for table in inspection.tables:
		var item := _tables.create_item(root)
		item.set_text(0, String(table.name))
		item.set_text(1, str(table.row_count))
		item.set_text(2, str(table.column_count))
		item.set_text(3, str(table.index_count))
		item.set_metadata(0, table.name)
		if session.selected_table != null \
				and session.selected_table.name == table.name:
			item.select(0)


func _validate_database_form(_value: String) -> void:
	var database_valid := not _database_name.text.strip_edges().is_empty()
	var root_valid := not _data_root.text.strip_edges().is_empty()
	_create_dialog.get_ok_button().disabled = not database_valid or not root_valid
	if not database_valid:
		_dialog_hint.text = "Enter a database name."
	elif not root_valid:
		_dialog_hint.text = "Choose a data root."
	else:
		_dialog_hint.text = (
				"The catalog and database folders will be created under this root."
		)


func _submit_database_creation() -> void:
	database_create_submitted.emit(
		StringName(_database_name.text.strip_edges()),
		_data_root.text.strip_edges(),
	)


func _on_table_selected() -> void:
	if _action_hub == null or _active_registration == &"":
		return
	var item := _tables.get_selected()
	if item == null:
		return
	_action_hub.invoke(
		GDSQLEditorActionIds.SELECT_TABLE,
		[_active_registration, item.get_metadata(0)],
	)
