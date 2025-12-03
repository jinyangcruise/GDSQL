@tool
extends MarginContainer

@onready var panel_container: PanelContainer = %PanelContainer
@onready var panel_container_2: PanelContainer = %PanelContainer2
@onready var tree_databases: Tree = %TreeDatabases
@onready var tab_container: TabContainer = %TabContainer
@onready var log_table: VBoxContainer = %LogTable

func _ready() -> void:
	if GDSQL.WorkbenchManager == null or not GDSQL.WorkbenchManager.run_in_plugin(self):
		return
		
	if not GDSQL.WorkbenchManager.add_log_history.is_connected(add_a_log):
		GDSQL.WorkbenchManager.add_log_history.connect(add_a_log)
		
	var sb: StyleBoxFlat = get_theme_stylebox(&"panel", &"TabContainer").duplicate()
	sb.corner_radius_top_left = 0
	sb.corner_radius_top_right = 5
	sb.corner_radius_bottom_left = 5
	sb.corner_radius_bottom_right = 5
	sb.content_margin_left = 0
	panel_container.add_theme_stylebox_override(&"panel", sb)
	
	var sb2: StyleBoxFlat = get_theme_stylebox(&"panel", &"TabContainer").duplicate()
	sb2.corner_radius_top_left = 5
	sb2.corner_radius_top_right = 0
	sb2.corner_radius_bottom_left = 5
	sb2.corner_radius_bottom_right = 5
	panel_container_2.add_theme_stylebox_override(&"panel", sb2)
	
	var sb3: StyleBoxFlat = get_theme_stylebox(&"panel", &"TabContainer").duplicate()
	sb3.corner_radius_top_left = 5
	sb3.corner_radius_top_right = 0
	sb3.corner_radius_bottom_left = 5
	sb3.corner_radius_bottom_right = 0
	tab_container.add_theme_stylebox_override(&"panel", sb3)
	
	log_table.ratios = [22.0, 30.0, 8.0, 1.5, 0.4, 1.0] as Array[float]
	log_table.columns = ["Status", "#", "Time", "Action", "Message", "Duration / Cost"] as Array[String]
	
func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		if panel_container:
			var sb: StyleBoxFlat = get_theme_stylebox(&"panel", &"TabContainer").duplicate()
			sb.corner_radius_top_left = 0
			sb.corner_radius_top_right = 5
			sb.corner_radius_bottom_left = 5
			sb.corner_radius_bottom_right = 5
			sb.content_margin_left = 0
			panel_container.add_theme_stylebox_override(&"panel", sb)
		if panel_container_2:
			var sb2: StyleBoxFlat = get_theme_stylebox(&"panel", &"TabContainer").duplicate()
			sb2.corner_radius_top_left = 5
			sb2.corner_radius_top_right = 0
			sb2.corner_radius_bottom_left = 5
			sb2.corner_radius_bottom_right = 5
			panel_container_2.add_theme_stylebox_override(&"panel", sb2)
		if tab_container:
			var sb3: StyleBoxFlat = get_theme_stylebox(&"panel", &"TabContainer").duplicate()
			sb3.corner_radius_top_left = 5
			sb3.corner_radius_top_right = 0
			sb3.corner_radius_bottom_left = 5
			sb3.corner_radius_bottom_right = 0
			tab_container.add_theme_stylebox_override(&"panel", sb3)
			
func _exit_tree():
	if GDSQL.WorkbenchManager == null or not GDSQL.WorkbenchManager.run_in_plugin(self):
		return
		
	if GDSQL.WorkbenchManager.add_log_history.is_connected(add_a_log):
		GDSQL.WorkbenchManager.add_log_history.disconnect(add_a_log)
		
func _on_button_refresh_pressed() -> void:
	tree_databases.refresh()
	
func add_a_log(status: String, begin_timestamp: float, action: String, message, cost: float = 0) -> void:
	var now = Time.get_unix_time_from_system()
	if message is Array:
		message = " ".join(message)
	var new_log = [
		status,
		log_table.datas.size() + 1,
		Time.get_datetime_string_from_system(false, true) if is_zero_approx(begin_timestamp) else (
			Time.get_datetime_string_from_unix_time(
				now + Time.get_time_zone_from_system().get("bias", 0) * 60, true
			)
		),
		action,
		message,
		"%.3f / %.3f sec" % [(0.0 if is_zero_approx(begin_timestamp) else (now - begin_timestamp)), cost]
	]
	log_table.append_data(new_log)
	log_table.scroll_to_bottom()
	if status != "OK":
		EditorInterface.get_editor_toaster().push_toast(message, EditorToaster.SEVERITY_ERROR)
		
func _on_button_clear_log_pressed():
	log_table.datas = []
