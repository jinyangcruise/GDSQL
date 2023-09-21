@tool
extends MarginContainer

var mgr: GDSQLWorkbenchManagerClass = Engine.get_singleton("GDSQLWorkbenchManager")

@onready var tree_databases: Tree = $VBoxContainer/HSplitContainer/VBoxContainer/TreeDatabases
@onready var tab_container: TabContainer = $VBoxContainer/HSplitContainer/VSplitContainer/TabContainer
@onready var log_table: VBoxContainer = $VBoxContainer/HSplitContainer/VSplitContainer/Control/VBoxContainer/LogTable


func _ready() -> void:
	if not mgr.add_log_history.is_connected(add_a_log):
		mgr.add_log_history.connect(add_a_log)
	
func _exit_tree():
	if mgr.add_log_history.is_connected(add_a_log):
		mgr.add_log_history.disconnect(add_a_log)

func _on_button_refresh_pressed() -> void:
	tree_databases.refresh()
	
func add_a_log(status: String, begin_timestamp: float, action: String, message) -> void:
	if message is Array:
		message = " ".join(message)
	var datas: Array = log_table.datas
	var new_log = [
		status,
		datas.size() + 1,
		Time.get_datetime_string_from_system(false, true) if is_zero_approx(begin_timestamp) else (
			Time.get_datetime_string_from_unix_time(
				Time.get_unix_time_from_system() + Time.get_time_zone_from_system().get("bias", 0) * 60, true
			)
		),
		action,
		message,
		"%.3f sec" % (0.0 if is_zero_approx(begin_timestamp) else (Time.get_unix_time_from_system() - begin_timestamp))
	]
	datas.push_back(new_log)
	log_table.datas = datas
	log_table.scroll_to_bottom()
