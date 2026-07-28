class_name GDSQLEditorActionIds
extends RefCounted
## Stable identifiers shared by editor action definitions and presentation.

const CREATE_DATABASE := &"database.create"
const DISCOVER_PROJECT := &"database.discover_project"
const REFRESH_DATABASES := &"database.refresh"
const OPEN_REGISTRATION := &"database.open_registration"
const SELECT_TABLE := &"database.select_table"
const SHOW_WELCOME := &"workspace.show_welcome"


static func get_all() -> Array[StringName]:
	return [
		CREATE_DATABASE,
		DISCOVER_PROJECT,
		REFRESH_DATABASES,
		OPEN_REGISTRATION,
		SELECT_TABLE,
		SHOW_WELCOME,
	]


static func is_valid(action_id: StringName) -> bool:
	return action_id in get_all()
