@tool
class_name GDSQLDatabaseDock
extends VBoxContainer
## Persistent lightweight database navigation for the Godot editor.

const CONTEXT_OPEN := 1
const CONTEXT_CREATE_TABLE := 2
const CONTEXT_REFRESH := 3
const CONTEXT_REMOVE_REGISTRATION := 4
const CONTEXT_DROP_TABLE := 6

var _workbench: GDSQLWorkbench
var _action_hub: GDSQLEditorActionHub
var _context_metadata: Dictionary = { }
var _pending_context_action := 0
var _render_pending := false

@onready var _refresh: Button = $Toolbar/ToolbarMargin/ToolbarRow/Refresh
@onready var _tree: Tree = $Content/DatabaseTree
@onready var _empty_state: CenterContainer = $Content/EmptyState
@onready var _context_menu: PopupMenu = $ContextMenu
@onready var _confirmation: ConfirmationDialog = $DestructiveConfirmation


func _ready() -> void:
	_tree.item_selected.connect(_on_item_selected)
	_tree.item_activated.connect(_on_item_selected)
	_tree.item_mouse_selected.connect(_on_item_mouse_selected)
	_context_menu.id_pressed.connect(_on_context_action)
	_confirmation.confirmed.connect(_on_destructive_action_confirmed)
	_refresh.pressed.connect(_on_refresh)
	render()


func configure(workbench: GDSQLWorkbench, action_hub: GDSQLEditorActionHub) -> void:
	_workbench = workbench
	_action_hub = action_hub
	if is_node_ready():
		render()


func render() -> void:
	if _render_pending:
		return
	_render_pending = true
	call_deferred("_render_now")


func _render_now() -> void:
	_render_pending = false
	if not is_node_ready():
		return
	_tree.clear()
	var root := _tree.create_item()
	if root == null:
		return
	var visible_registrations := 0
	if _workbench != null:
		var registrations := _workbench.get_registrations()
		registrations.sort_custom(
			func(left: GDSQLDatabaseRegistration, right: GDSQLDatabaseRegistration) -> bool:
				return String(left.name) < String(right.name),
		)
		for registration in registrations:
			_add_registration(root, registration)
			visible_registrations += 1
	_empty_state.visible = visible_registrations == 0
	_tree.visible = visible_registrations > 0


func get_database_tree() -> Tree:
	return _tree


func _add_registration(root: TreeItem, registration: GDSQLDatabaseRegistration) -> void:
	var inspection := _workbench.get_inspection(registration.name)
	var item := _tree.create_item(root)
	if item == null:
		return
	item.set_text(
		0,
		"%s  [%s]" % [
			registration.database_name,
			GDSQLStorageBackendIds.get_display_name(
				registration.storage_backend_id,
			),
		],
	)
	item.set_metadata(0, { "kind": &"registration", "registration": registration.name })
	item.set_tooltip_text(
		0,
		"%s\n%s" % [registration.data_root, registration.storage_backend_id],
	)
	item.collapsed = false
	if inspection == null:
		return
	var tables_group := _tree.create_item(item)
	if tables_group == null:
		return
	tables_group.set_text(0, "Tables")
	tables_group.set_selectable(0, false)
	tables_group.collapsed = false
	var tables := inspection.tables.duplicate()
	tables.sort_custom(
		func(left: GDSQLTableInspection, right: GDSQLTableInspection) -> bool:
			return String(left.name) < String(right.name),
	)
	for table in tables:
		var table_item := _tree.create_item(tables_group)
		if table_item == null:
			continue
		table_item.set_text(
			0,
			"%s  (%d rows)" % [table.name, table.row_count],
		)
		table_item.set_metadata(
			0,
			{ "kind": &"table", "registration": registration.name, "table": table.name },
		)
		table_item.set_tooltip_text(
			0,
			"%d columns · %d indexes" \
					% [table.column_count, table.index_count],
		)
		_add_columns(registration, table.name, table_item)


func _add_columns(
		registration: GDSQLDatabaseRegistration,
		table_name: StringName,
		parent: TreeItem,
) -> void:
	var session := _workbench.active_session
	if session == null or session.registration.name != registration.name \
			or session.catalog_snapshot == null:
		return
	var database := session.catalog_snapshot.get_database(
		registration.database_name,
	)
	if database == null:
		return
	var definition := database.get_table(table_name)
	if definition == null:
		return
	for column in definition.columns:
		var column_item := _tree.create_item(parent)
		if column_item == null:
			continue
		column_item.set_text(
			0,
			"%s : %s" % [
				column.name,
				type_string(column.data_type),
			],
		)
		column_item.set_selectable(0, false)


func _on_item_selected() -> void:
	if _action_hub == null:
		return
	var item := _tree.get_selected()
	if item == null:
		return
	var metadata: Dictionary = item.get_metadata(0)
	match metadata.get("kind", &""):
		&"registration":
			_action_hub.invoke(
				GDSQLEditorActionIds.OPEN_REGISTRATION,
				[metadata.get("registration", &"")],
			)
		&"table":
			_action_hub.invoke(
				GDSQLEditorActionIds.SELECT_TABLE,
				[metadata.get("registration", &""), metadata.get("table", &"")],
			)


func _on_item_mouse_selected(
		position: Vector2,
		mouse_button_index: int,
) -> void:
	if mouse_button_index != MOUSE_BUTTON_RIGHT:
		return
	var item := _tree.get_selected()
	if item == null:
		return
	var metadata_value: Variant = item.get_metadata(0)
	if not metadata_value is Dictionary:
		return
	_context_metadata = metadata_value
	_build_context_menu(StringName(_context_metadata.get("kind", &"")))
	_context_menu.position = Vector2i(_tree.get_screen_position() + position)
	_context_menu.popup()


func _build_context_menu(kind: StringName) -> void:
	var registration_context := kind == &"registration"
	_set_context_item_visible(CONTEXT_OPEN, true)
	_set_context_item_visible(CONTEXT_CREATE_TABLE, registration_context)
	_set_context_item_visible(CONTEXT_REFRESH, true)
	_set_context_item_visible(
		CONTEXT_REMOVE_REGISTRATION,
		registration_context,
	)
	_set_context_item_visible(CONTEXT_DROP_TABLE, not registration_context)


func _set_context_item_visible(id: int, visible: bool) -> void:
	var index := _context_menu.get_item_index(id)
	if index >= 0:
		_context_menu.set_item_hidden(index, not visible)


func _on_context_action(id: int) -> void:
	if _action_hub == null:
		return
	var registration_name := StringName(
		_context_metadata.get("registration", &""),
	)
	match id:
		CONTEXT_OPEN:
			if _context_metadata.get("kind", &"") == &"table":
				_action_hub.invoke(
					GDSQLEditorActionIds.SELECT_TABLE,
					[
						registration_name,
						_context_metadata.get("table", &""),
					],
				)
			else:
				_action_hub.invoke(
					GDSQLEditorActionIds.OPEN_REGISTRATION,
					[registration_name],
				)
		CONTEXT_CREATE_TABLE:
			var opened := _action_hub.invoke(
				GDSQLEditorActionIds.OPEN_REGISTRATION,
				[registration_name],
			)
			if opened.is_successful():
				_action_hub.invoke(GDSQLEditorActionIds.CREATE_TABLE)
		CONTEXT_REFRESH:
			_action_hub.invoke(GDSQLEditorActionIds.REFRESH_DATABASES)
		CONTEXT_REMOVE_REGISTRATION:
			_request_destructive_confirmation(id)
		CONTEXT_DROP_TABLE:
			_request_destructive_confirmation(id)


func _request_destructive_confirmation(action_id: int) -> void:
	_pending_context_action = action_id
	if action_id == CONTEXT_REMOVE_REGISTRATION:
		var registration := _workbench.get_registration(
			StringName(_context_metadata.get("registration", &"")),
		)
		_confirmation.title = "Remove Database"
		_confirmation.ok_button_text = "Remove"
		if registration != null:
			_confirmation.dialog_text = (
				(
					"Remove database '%s' from GDSQL?\n\n"
					+ "Files at '%s' will remain unchanged. Creating the same "
					+ "database later will load these files again."
				)
				% [
					registration.database_name,
					registration.data_root.path_join(
						String(registration.database_name),
					),
				]
			)
		else:
			_confirmation.dialog_text = (
				"Remove this database registration? Its files will remain unchanged."
			)
	else:
		_confirmation.title = "Delete Table"
		_confirmation.ok_button_text = "Delete"
		_confirmation.dialog_text = (
			"Delete table '%s' and all of its stored rows?"
			% _context_metadata.get("table", &"")
		)
	_confirmation.popup_centered(Vector2i(460, 170))


func _on_destructive_action_confirmed() -> void:
	var registration_name := StringName(
		_context_metadata.get("registration", &""),
	)
	match _pending_context_action:
		CONTEXT_REMOVE_REGISTRATION:
			_action_hub.invoke(
				GDSQLEditorActionIds.REMOVE_REGISTRATION,
				[registration_name],
			)
		CONTEXT_DROP_TABLE:
			_action_hub.invoke(
				GDSQLEditorActionIds.DROP_TABLE,
				[
					registration_name,
					_context_metadata.get("table", &""),
				],
			)
	_pending_context_action = 0


func _on_refresh() -> void:
	if _action_hub != null:
		_action_hub.invoke(GDSQLEditorActionIds.REFRESH_DATABASES)
