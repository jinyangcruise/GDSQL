@tool
class_name GDSQLActivityPanel
extends VBoxContainer
## Structured editor activity feed for GDSQL operations and diagnostics.

@onready var _activity: Tree = $Activity


func _ready() -> void:
	$Toolbar/Clear.pressed.connect(clear)
	_activity.set_column_title(0, "Time")
	_activity.set_column_title(1, "Status")
	_activity.set_column_title(2, "Action")
	_activity.set_column_title(3, "Message")


func append_result(
		action_label: String,
		result: GDSQLOperationResult,
) -> void:
	if result == null:
		append_message("Error", action_label, "The action returned no result.")
		return
	if result.diagnostics.is_empty():
		append_message("OK", action_label, "Completed.")
		return
	for diagnostic in result.diagnostics.entries:
		append_message(
			_severity_label(diagnostic.severity),
			action_label,
			diagnostic.message,
		)


func append_message(status: String, action_label: String, message: String) -> void:
	var root := _activity.get_root()
	if root == null:
		root = _activity.create_item()
	var item := _activity.create_item(root, 0)
	item.set_text(0, Time.get_time_string_from_system())
	item.set_text(1, status)
	item.set_text(2, action_label)
	item.set_text(3, message)


func clear() -> void:
	_activity.clear()


func _severity_label(severity: GDSQLQueryDiagnostic.Severity) -> String:
	match severity:
		GDSQLQueryDiagnostic.Severity.INFO:
			return "Info"
		GDSQLQueryDiagnostic.Severity.WARNING:
			return "Warning"
		_:
			return "Error"
