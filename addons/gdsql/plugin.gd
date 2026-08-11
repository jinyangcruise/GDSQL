@tool
extends EditorPlugin
## Godot lifecycle and native surface placement for the GDSQL editor.

const DATABASE_DOCK_SCENE := preload(
	"res://addons/gdsql/editor/database_dock/gdsql_database_dock.tscn"
)
const WORKSPACE_SCENE := preload("res://addons/gdsql/editor/workspace/gdsql_workspace.tscn")
const LOGS_SCENE := preload("res://addons/gdsql/editor/debug/gdsql_logs_panel.tscn")
const DATABASE_DOCK_KEY := "GDSQLDatabases"
const LOGS_DOCK_KEY := "GDSQLLogs"
const WORKSPACE_HOST_NAME := "GDSQLWorkspaceHost"
const DATABASE = preload("res://addons/gdsql/editor/workspace/icons/database.svg")

var _controller: GDSQLEditorController
var _workspace_host: MarginContainer
var _workspace: GDSQLWorkspace
var _database_dock: EditorDock
var _database_dock_content: GDSQLDatabaseDock
var _logs_dock: EditorDock
var _logs_panel: GDSQLLogsPanel


func _enter_tree() -> void:
	_create_workspace()
	_create_database_dock()
	_create_logs_dock()
	_controller = GDSQLEditorController.new(
		_workspace,
		_database_dock_content,
		_logs_panel,
		Callable(EditorInterface.get_resource_filesystem(), "scan"),
	)
	_controller.action_hub.main_screen_requested.connect(_show_main_screen)
	call_deferred("_load_workspace")


func _exit_tree() -> void:
	if _controller != null:
		_controller.shutdown()
		_controller = null
	if is_instance_valid(_database_dock):
		remove_dock(_database_dock)
		_database_dock.free()
	if is_instance_valid(_logs_dock):
		remove_dock(_logs_dock)
		_logs_dock.free()
	if is_instance_valid(_workspace_host):
		_workspace_host.free()
	_database_dock = null
	_database_dock_content = null
	_logs_dock = null
	_logs_panel = null
	_workspace_host = null
	_workspace = null


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if not is_instance_valid(_workspace_host):
		return
	_workspace_host.visible = visible
	if visible and _controller != null:
		_controller.ensure_workspace_loaded()


func _get_plugin_name() -> String:
	return "GDSQL"


func _get_plugin_icon() -> Texture2D:
	var theme := EditorInterface.get_editor_theme()
	theme.set_icon("Database", &"EditorIcons", DATABASE)
	if theme.has_icon(&"Database", &"EditorIcons"):
		return theme.get_icon(&"Database", &"EditorIcons")
	return theme.get_icon(&"Script", &"EditorIcons")


func _show_main_screen() -> void:
	EditorInterface.set_main_screen_editor(_get_plugin_name())


func _create_workspace() -> void:
	var main_screen := EditorInterface.get_editor_main_screen()
	var stale_host := main_screen.get_node_or_null(WORKSPACE_HOST_NAME)
	if stale_host != null:
		stale_host.free()
	_workspace_host = MarginContainer.new()
	_workspace_host.name = WORKSPACE_HOST_NAME
	_workspace_host.clip_contents = true
	_workspace_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_workspace_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_workspace_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_screen.add_child(_workspace_host)

	_workspace = WORKSPACE_SCENE.instantiate() as GDSQLWorkspace
	_workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_workspace_host.add_child(_workspace)
	_workspace_host.hide()


func _create_database_dock() -> void:
	_remove_existing_dock(DATABASE_DOCK_KEY)
	_database_dock_content = (DATABASE_DOCK_SCENE.instantiate() as GDSQLDatabaseDock)
	_database_dock = EditorDock.new()
	_database_dock.name = DATABASE_DOCK_KEY
	_database_dock.title = "GDSQL DBs"
	_database_dock.layout_key = DATABASE_DOCK_KEY
	_database_dock.default_slot = EditorDock.DOCK_SLOT_RIGHT_BL
	_database_dock.available_layouts = (
		EditorDock.DOCK_LAYOUT_VERTICAL | EditorDock.DOCK_LAYOUT_FLOATING
	)
	_database_dock.add_child(_database_dock_content)
	add_dock(_database_dock)


func _create_logs_dock() -> void:
	_remove_existing_dock(LOGS_DOCK_KEY)
	_logs_panel = LOGS_SCENE.instantiate() as GDSQLLogsPanel
	_logs_dock = EditorDock.new()
	_logs_dock.name = LOGS_DOCK_KEY
	_logs_dock.title = "GDSQL Logs"
	_logs_dock.layout_key = LOGS_DOCK_KEY
	_logs_dock.default_slot = EditorDock.DOCK_SLOT_BOTTOM
	_logs_dock.available_layouts = (
		EditorDock.DOCK_LAYOUT_HORIZONTAL | EditorDock.DOCK_LAYOUT_FLOATING
	)
	_logs_dock.add_child(_logs_panel)
	add_dock(_logs_dock)


func _load_workspace() -> void:
	if _controller != null:
		_controller.ensure_workspace_loaded()


func _remove_existing_dock(layout_key: String) -> void:
	var editor_root := EditorInterface.get_base_control()
	for node in editor_root.find_children("*", "EditorDock", true, false):
		var dock := node as EditorDock
		if dock == null or dock.layout_key != layout_key:
			continue
		remove_dock(dock)
		dock.free()
