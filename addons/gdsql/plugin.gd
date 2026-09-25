@tool
extends EditorPlugin
## Godot lifecycle and native surface placement for the GDSQL editor.

const DATABASE_DOCK_SCENE := preload(
	"res://addons/gdsql/editor/database_dock/gdsql_database_dock.tscn"
)
const WORKSPACE_SCENE := preload("res://addons/gdsql/editor/workspace/gdsql_workspace.tscn")
const LOGS_SCENE := preload("res://addons/gdsql/editor/debug/gdsql_logs_panel.tscn")
const GODOT_AI_MCP_ADAPTER := preload(
	"res://addons/gdsql/editor/integrations/mcp/gdsql_godot_ai_mcp_adapter.gd"
)
const DATABASE_DOCK_KEY := "GDSQLDatabases"
const LOGS_DOCK_KEY := "GDSQLLogs"
const WORKSPACE_HOST_NAME := "GDSQLWorkspaceHost"
const SETTINGS_PATH := "res://.gdsql/settings.cfg"
const RUNTIME_AUTOLOAD_SETTING := "autoload/GDSQLRuntime"
const RUNTIME_NODE_PATH := "res://addons/gdsql/runtime/gdsql_runtime_node.tscn"
const DATABASE = preload("res://addons/gdsql/editor/workspace/icons/database.svg")
const LOG_STATUS_ICONS := {
	GDSQLLogsPanel.Indicator.SUCCESS: &"StatusSuccess",
	GDSQLLogsPanel.Indicator.WARNING: &"StatusWarning",
	GDSQLLogsPanel.Indicator.ERROR: &"StatusError",
}

var _controller: GDSQLEditorController
var _workspace_host: MarginContainer
var _workspace: GDSQLWorkspace
var _database_dock: EditorDock
var _database_dock_content: GDSQLDatabaseDock
var _logs_dock: EditorDock
var _logs_panel: GDSQLLogsPanel
var _command_palette: GDSQLEditorCommandPalette
var _mcp_adapter: Node


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
	_command_palette = GDSQLEditorCommandPalette.new(
		EditorInterface.get_command_palette(),
		_controller.workbench,
		_controller.action_hub,
	)
	_controller.navigation_catalog_changed.connect(_command_palette.refresh)
	_create_mcp_adapter()
	call_deferred("_load_workspace")


func _exit_tree() -> void:
	if is_instance_valid(_mcp_adapter):
		_mcp_adapter.call("shutdown")
		_mcp_adapter.free()
	_mcp_adapter = null
	if _command_palette != null:
		_command_palette.clear()
		_command_palette = null
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
	_logs_panel.indicator_changed.connect(_on_logs_indicator_changed)
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


func _on_logs_indicator_changed(indicator: GDSQLLogsPanel.Indicator) -> void:
	if not is_instance_valid(_logs_dock):
		return
	var icon_name := LOG_STATUS_ICONS.get(indicator, &"") as StringName
	var theme := EditorInterface.get_editor_theme()
	_logs_dock.force_show_icon = icon_name != &""
	_logs_dock.dock_icon = (
			theme.get_icon(icon_name, &"EditorIcons")
			if icon_name != &"" and theme.has_icon(icon_name, &"EditorIcons")
			else null
	)


func _load_workspace() -> void:
	if _controller != null:
		_controller.ensure_workspace_loaded()


func _create_mcp_adapter() -> void:
	var service := GDSQLMcpInspectionService.new(
		_controller.workbench,
		GDSQLConfigFileSetupProfileStore.new(),
		GDSQLConfigFileManagedContentConfigurationStore.new(),
		GDSQLConfigFileContentPackageManifestStore.new(),
		GDSQLConfigFileContentCacheStore.new(),
		GDSQLConfigFileDatabaseExplorer.new(),
		_mcp_model_count,
		_mcp_runtime_adapter_configured,
	)
	_mcp_adapter = GODOT_AI_MCP_ADAPTER.new(service)
	add_child(_mcp_adapter)


func _mcp_model_count() -> int:
	var root := GDSQLModelSourceGenerator.DEFAULT_ROOT
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		root = String(config.get_value("models", "root", root))
	var directory := DirAccess.open(root)
	if directory == null:
		return 0
	var count := 0
	for file_name in directory.get_files():
		if file_name.get_extension() == "gd":
			count += 1
	return count


func _mcp_runtime_adapter_configured() -> bool:
	var configured_path := String(ProjectSettings.get_setting(RUNTIME_AUTOLOAD_SETTING, ""))
	return configured_path.trim_prefix("*") == RUNTIME_NODE_PATH


func _remove_existing_dock(layout_key: String) -> void:
	var editor_root := EditorInterface.get_base_control()
	for node in editor_root.find_children("*", "EditorDock", true, false):
		var dock := node as EditorDock
		if dock == null or dock.layout_key != layout_key:
			continue
		remove_dock(dock)
		dock.free()
