@tool
class_name GDSQLDatabaseDock
extends VBoxContainer
## Persistent lightweight database navigation for the Godot editor.

var _workbench: GDSQLWorkbench
var _action_hub: GDSQLEditorActionHub

@onready var _action_strip: GDSQLEditorActionStrip = \
		$Toolbar/ToolbarMargin/ToolbarRow/ActionStrip
@onready var _filter: LineEdit = $FilterMargin/Filter
@onready var _tree: Tree = $Content/DatabaseTree
@onready var _empty_state: CenterContainer = $Content/EmptyState


func _ready() -> void:
	_tree.set_column_title(0, "Database")
	_tree.set_column_title(1, "Storage")
	_tree.item_selected.connect(_on_item_selected)
	_tree.item_activated.connect(_on_item_selected)
	_filter.text_changed.connect(_on_filter_changed)
	if _action_hub != null:
		_configure_actions()
		render()


func configure(workbench: GDSQLWorkbench, action_hub: GDSQLEditorActionHub) -> void:
	_workbench = workbench
	_action_hub = action_hub
	if is_node_ready():
		_configure_actions()
		render()


func render() -> void:
	if not is_node_ready():
		return
	_tree.clear()
	var root := _tree.create_item()
	var visible_registrations := 0
	if _workbench != null:
		var registrations := _workbench.get_registrations()
		registrations.sort_custom(
			func(left: GDSQLDatabaseRegistration, right: GDSQLDatabaseRegistration) -> bool:
				return String(left.name) < String(right.name),
		)
		for registration in registrations:
			if not _matches_filter(registration):
				continue
			_add_registration(root, registration)
			visible_registrations += 1
	_empty_state.visible = visible_registrations == 0
	_tree.visible = visible_registrations > 0


func get_database_tree() -> Tree:
	return _tree


func _configure_actions() -> void:
	if _action_hub == null:
		return
	_action_strip.configure(
		_action_hub,
		[GDSQLEditorActionIds.DISCOVER_PROJECT, GDSQLEditorActionIds.REFRESH_DATABASES],
	)


func _add_registration(root: TreeItem, registration: GDSQLDatabaseRegistration) -> void:
	var inspection := _workbench.get_inspection(registration.name)
	var item := _tree.create_item(root)
	item.set_text(0, String(registration.name))
	item.set_text(
		1,
		"Missing" if inspection == null or not inspection.catalog_exists \
		else GDSQLStorageBackendIds.get_display_name(registration.storage_backend_id),
	)
	item.set_metadata(0, { "kind": &"registration", "registration": registration.name })
	item.set_tooltip_text(0, "%s\n%s" % [registration.database_name, registration.data_root])
	item.collapsed = false
	if inspection == null:
		return
	var tables := inspection.tables.duplicate()
	tables.sort_custom(
		func(left: GDSQLTableInspection, right: GDSQLTableInspection) -> bool:
			return String(left.name) < String(right.name),
	)
	for table in tables:
		var table_item := _tree.create_item(item)
		table_item.set_text(0, String(table.name))
		table_item.set_text(1, "%d rows" % table.row_count)
		table_item.set_metadata(
			0,
			{ "kind": &"table", "registration": registration.name, "table": table.name },
		)
		table_item.set_tooltip_text(
			0,
			"%d columns · %d indexes" \
					% [table.column_count, table.index_count],
		)


func _matches_filter(registration: GDSQLDatabaseRegistration) -> bool:
	var query := _filter.text.strip_edges().to_lower()
	if query.is_empty():
		return true
	if String(registration.name).to_lower().contains(query) \
			or String(registration.database_name).to_lower().contains(query):
		return true
	var inspection := _workbench.get_inspection(registration.name)
	if inspection != null:
		for table in inspection.tables:
			if String(table.name).to_lower().contains(query):
				return true
	return false


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


func _on_filter_changed(_value: String) -> void:
	render()
