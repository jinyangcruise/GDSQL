class_name GDSQLDirectSetupCheck
extends RefCounted
## One actionable condition in the supported direct-content setup profile.

const ACTION_NONE := &""
const ACTION_CREATE_DATABASE := &"create_database"
const ACTION_OPEN_CONTENT_DATABASE := &"open_content_database"
const ACTION_OPEN_CONTENT_TABLE := &"open_content_table"
const ACTION_MANAGE_SAVE_SLOTS := &"manage_save_slots"
const ACTION_INSTALL_RUNTIME := &"install_runtime"

var id: StringName
var label: String
var complete: bool
var detail: String
var next_action: StringName


func _init(
		check_id: StringName = &"",
		check_label: String = "",
		is_complete: bool = false,
		check_detail: String = "",
		action: StringName = ACTION_NONE,
) -> void:
	id = check_id
	label = check_label
	complete = is_complete
	detail = check_detail
	next_action = action
