@tool
extends MarginContainer

var mgr: GDSQLWorkbenchManagerClass = Engine.get_singleton("GDSQLWorkbenchManager")

@onready var tree_databases: Tree = $VBoxContainer/HSplitContainer/VBoxContainer/TreeDatabases
@onready var tab_container: TabContainer = $VBoxContainer/HSplitContainer/VSplitContainer/TabContainer
@onready var log_table: VBoxContainer = $VBoxContainer/HSplitContainer/VSplitContainer/Control/VBoxContainer/LogTable


func _ready() -> void:
	if mgr == null or not mgr.run_in_plugin(self):
		return
		
	if not mgr.add_log_history.is_connected(add_a_log):
		mgr.add_log_history.connect(add_a_log)
		
	log_table.ratios = [22.0, 30.0, 8.0, 1.5, 0.4, 1.0] as Array[float]
	log_table.columns = ["Status", "#", "Time", "Action", "Message", "Duration / Cost"] as Array[String]
	
func _exit_tree():
	if mgr == null or not mgr.run_in_plugin(self):
		return

	if mgr.add_log_history.is_connected(add_a_log):
		mgr.add_log_history.disconnect(add_a_log)
		
	mgr = null

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


func _on_button_clear_log_pressed():
	log_table.datas = []
