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
const OPEN_QUERY_GRAPH_FOLDER := &"query_graph.open_folder"
const SAVE_QUERY_GRAPH := &"query_graph.save"
const ADD_SELECT_QUERY_NODE := &"query_graph.add_select"
const ADD_LEFT_JOIN_QUERY_NODE := &"query_graph.add_left_join"
const ADD_INSERT_QUERY_NODE := &"query_graph.add_insert"
const ADD_UPDATE_QUERY_NODE := &"query_graph.add_update"
const ADD_DELETE_QUERY_NODE := &"query_graph.add_delete"
const RUN_QUERY_GRAPH := &"query_graph.run"
const ADD_QUERY_RESULT_ROW := &"query_graph.result.add_row"


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
		OPEN_QUERY_GRAPH_FOLDER,
		SAVE_QUERY_GRAPH,
		ADD_SELECT_QUERY_NODE,
		ADD_LEFT_JOIN_QUERY_NODE,
		ADD_INSERT_QUERY_NODE,
		ADD_UPDATE_QUERY_NODE,
		ADD_DELETE_QUERY_NODE,
		RUN_QUERY_GRAPH,
		ADD_QUERY_RESULT_ROW,
	]


static func is_valid(action_id: StringName) -> bool:
	return action_id in get_all()
