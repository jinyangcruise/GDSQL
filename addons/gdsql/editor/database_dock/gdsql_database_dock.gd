@tool
class_name GDSQLDatabaseDock
extends VBoxContainer
## Persistent lightweight database navigation for the Godot editor.

var _workbench: GDSQLWorkbench
var _action_hub: GDSQLEditorActionHub
var _render_pending := false

@onready var _refresh: Button = $Toolbar/ToolbarMargin/ToolbarRow/Refresh
@onready var _tree: Tree = $Content/DatabaseTree
@onready var _empty_state: CenterContainer = $Content/EmptyState


func _ready() -> void:
	_tree.item_selected.connect(_on_item_selected)
	_tree.item_activated.connect(_on_item_selected)
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


func get_database_tree() -> Tree:
	return _tree


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


func _add_registration(root: TreeItem, registration: GDSQLDatabaseRegistration) -> void:
	var inspection := _workbench.get_inspection(registration.name)
	var item := _tree.create_item(root)
	if item == null:
		return
	item.set_text(
		0,
		"%s  [%s]"
		% [
			registration.database_name,
			GDSQLStorageBackendIds.get_display_name(registration.storage_backend_id),
		],
	)
	item.set_metadata(0, { "kind": &"registration", "registration": registration.name })
	item.set_tooltip_text(0, "%s\n%s" % [registration.data_root, registration.storage_backend_id])
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
		table_item.set_text(0, "%s  (%d rows)" % [table.name, table.row_count])
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
	var database := session.catalog_snapshot.get_database(registration.database_name)
	if database == null:
		return
	var definition := database.get_table(table_name)
	if definition == null:
		return
	for column in definition.columns:
		var column_item := _tree.create_item(parent)
		if column_item == null:
			continue
		column_item.set_text(0, "%s : %s" % [column.name, type_string(column.data_type)])
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
				true,
			)
		&"table":
			_action_hub.invoke(
				GDSQLEditorActionIds.SELECT_TABLE,
				[metadata.get("registration", &""), metadata.get("table", &"")],
				true,
			)


func _on_refresh() -> void:
	if _action_hub != null:
		_action_hub.invoke(GDSQLEditorActionIds.REFRESH_DATABASES)
