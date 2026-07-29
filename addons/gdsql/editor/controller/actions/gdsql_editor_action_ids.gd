class_name GDSQLEditorActionIds
extends RefCounted
## Stable identifiers shared by editor action definitions and presentation.

const CREATE_DATABASE := &"database.create"
const CREATE_TABLE := &"table.create"
const REMOVE_REGISTRATION := &"database.remove_registration"
const DROP_TABLE := &"table.drop"
const DISCOVER_PROJECT := &"database.discover_project"
const REFRESH_DATABASES := &"database.refresh"
const OPEN_REGISTRATION := &"database.open_registration"
const SELECT_TABLE := &"database.select_table"
const SHOW_WELCOME := &"workspace.show_welcome"
const SAVE_DATABASE_CHANGES := &"database_document.save"
const REFRESH_DATABASE_CHANGES := &"database_document.refresh"


static func get_all() -> Array[StringName]:
	return [
		CREATE_DATABASE,
		CREATE_TABLE,
		REMOVE_REGISTRATION,
		DROP_TABLE,
		DISCOVER_PROJECT,
		REFRESH_DATABASES,
		OPEN_REGISTRATION,
		SELECT_TABLE,
		SHOW_WELCOME,
		SAVE_DATABASE_CHANGES,
		REFRESH_DATABASE_CHANGES,
	]


static func is_valid(action_id: StringName) -> bool:
	return action_id in get_all()
