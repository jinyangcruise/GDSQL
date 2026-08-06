@tool
class_name GDSQLQueryGraphEditor
extends Control
## Presentation frontend for a query graph document.
##
## This first slice presents one SELECT operation. It consumes lightweight
## workbench inspection metadata and does not access rows or storage.

const SELECT_NODE_SCENE := preload(
	"res://addons/gdsql/editor/workspace/query_graph/nodes/select/select_operation_node.tscn"
)
const TABLE_RESULT_NODE_SCENE := preload(
	"res://addons/gdsql/editor/workspace/query_graph/nodes/table_result/table_result_node.tscn"
)
const UNAVAILABLE_ACTIONS: Array[StringName] = [
	GDSQLEditorActionIds.OPEN_QUERY_GRAPH_FOLDER,
	GDSQLEditorActionIds.SAVE_QUERY_GRAPH,
	GDSQLEditorActionIds.ADD_LEFT_JOIN_QUERY_NODE,
	GDSQLEditorActionIds.ADD_INSERT_QUERY_NODE,
	GDSQLEditorActionIds.ADD_UPDATE_QUERY_NODE,
	GDSQLEditorActionIds.ADD_DELETE_QUERY_NODE,
]

signal source_changed(
		registration_name: StringName,
		database_name: StringName,
		table_name: StringName,
)
signal query_requested(
		registration_name: StringName,
		query: GDSQLQuerySpec,
)
signal row_insert_requested(
		registration_name: StringName,
		table_name: StringName,
		values: Dictionary,
)
signal row_update_requested(
		registration_name: StringName,
		table_name: StringName,
		original_primary_key: Variant,
		values: Dictionary,
)
signal row_delete_requested(
		registration_name: StringName,
		table_name: StringName,
		primary_key: Variant,
)

var _inspections: Array[GDSQLDatabaseInspection] = []
var _action_hub: GDSQLEditorActionHub
var _action_context: GDSQLContextActionHub
var _action_context_id: StringName
var _active_select_operation: GraphNode
var _table_result: GDSQLQueryTableResultNode
var _result_source: GraphNode

@onready var _graph: GraphEdit = %Graph
@onready var _select_operation: GraphNode = %SelectOperation
@onready var _open_graph_folder: GDSQLEditorActionButton = %LoadGraphFolder
@onready var _save_graph: GDSQLEditorActionButton = %SaveGraph
@onready var _add_select: GDSQLEditorActionButton = %AddSelectNode
@onready var _add_left_join: GDSQLEditorActionButton = %AddLeftJoinNode
@onready var _add_insert: GDSQLEditorActionButton = %AddInsertNode
@onready var _add_update: GDSQLEditorActionButton = %AddUpdateNode
@onready var _add_delete: GDSQLEditorActionButton = %AddDeleteNode


func _ready() -> void:
	_active_select_operation = _select_operation
	_connect_select_node(_select_operation)
	_graph.node_selected.connect(_on_graph_node_selected)


func configure_actions(
		action_hub: GDSQLEditorActionHub,
		context_id: StringName,
) -> void:
	if _action_hub == action_hub and _action_context_id == context_id:
		return
	release_actions()
	_action_hub = action_hub
	_action_context_id = context_id
	_action_context = GDSQLContextActionHub.new(context_id)
	_register_action(
		GDSQLEditorActionIds.OPEN_QUERY_GRAPH_FOLDER,
		"Open Graphs Folder",
		"Open the project query-graph folder.",
		&"file",
		0,
		_unavailable_action.bind("Opening the query-graph folder"),
	)
	_register_action(
		GDSQLEditorActionIds.SAVE_QUERY_GRAPH,
		"Save Graph",
		"Save this query graph and its node layout.",
		&"file",
		1,
		_unavailable_action.bind("Saving query graphs"),
	)
	_register_action(
		GDSQLEditorActionIds.ADD_SELECT_QUERY_NODE,
		"SELECT",
		"Add a SELECT operation node.",
		&"read",
		10,
		_add_select_node,
	)
	_register_action(
		GDSQLEditorActionIds.ADD_LEFT_JOIN_QUERY_NODE,
		"LEFT JOIN",
		"Add a LEFT JOIN operation node.",
		&"read",
		11,
		_unavailable_action.bind("LEFT JOIN nodes"),
	)
	_register_action(
		GDSQLEditorActionIds.ADD_INSERT_QUERY_NODE,
		"INSERT",
		"Add an INSERT operation node.",
		&"mutation",
		20,
		_unavailable_action.bind("INSERT nodes"),
	)
	_register_action(
		GDSQLEditorActionIds.ADD_UPDATE_QUERY_NODE,
		"UPDATE",
		"Add an UPDATE operation node.",
		&"mutation",
		21,
		_unavailable_action.bind("UPDATE nodes"),
	)
	_register_action(
		GDSQLEditorActionIds.ADD_DELETE_QUERY_NODE,
		"DELETE",
		"Add a DELETE operation node.",
		&"mutation",
		22,
		_unavailable_action.bind("DELETE nodes"),
	)
	_register_action(
		GDSQLEditorActionIds.RUN_QUERY_GRAPH,
		"Query",
		"Compile and execute the selected query operation.",
		&"execute",
		100,
		request_query,
	)
	_register_action(
		GDSQLEditorActionIds.ADD_QUERY_RESULT_ROW,
		"Add Row",
		"Add a row when the query result contains every table column.",
		&"result",
		110,
		_add_result_row,
	)
	_register_action(
		GDSQLEditorActionIds.REMOVE_QUERY_GRAPH_NODE,
		"Remove Node",
		"Remove the selected query operation node.",
		&"node",
		120,
		_remove_active_select_node,
	)
	for action_id in UNAVAILABLE_ACTIONS:
		_action_context.set_action_enabled(action_id, false)
	_action_context.set_action_enabled(
		GDSQLEditorActionIds.ADD_QUERY_RESULT_ROW,
		false,
	)
	var registered := _action_hub.register_context(_action_context)
	if not registered.is_successful():
		return
	_configure_action_buttons()
	_configure_select_query_buttons()
	_refresh_action_availability()


func release_actions() -> void:
	if _action_hub != null and _action_context_id != &"":
		_action_hub.unregister_context(_action_context_id)
	_action_context = null
	_action_context_id = &""
	_action_hub = null


func get_action_context_id() -> StringName:
	return _action_context_id


func configure(
		inspections: Array[GDSQLDatabaseInspection],
		selected_registration: StringName,
		selected_table: StringName,
) -> void:
	_inspections = inspections.duplicate()
	var target := _active_select_operation
	if not is_instance_valid(target):
		target = _first_select_node()
	if target == null:
		return
	target.call(
		"configure",
		inspections,
		selected_registration,
		selected_table,
	)


func get_selected_registration() -> StringName:
	return _selected_source_value("get_selected_registration")


func get_selected_database() -> StringName:
	return _selected_source_value("get_selected_database")


func get_selected_table() -> StringName:
	return _selected_source_value("get_selected_table")


func request_query() -> GDSQLOperationResult:
	var graph := GDSQLQueryGraph.new()
	if not is_instance_valid(_active_select_operation):
		return GDSQLGraphQueryCompiler.new().compile(graph)
	var select_node := GDSQLQueryGraphSelectNode.new(
		get_selected_database(),
		get_selected_table(),
	)
	select_node.projections = _active_select_operation.call(
		"get_selected_columns",
	)
	select_node.include_all_columns = bool(
		_active_select_operation.call("are_all_columns_selected"),
	)
	var predicate_result := _active_select_operation.call(
		"build_predicate",
	) as GDSQLOperationResult
	if not predicate_result.is_successful():
		var failed := GDSQLQueryCompilationResult.new()
		failed.diagnostics.merge(predicate_result.diagnostics)
		return failed
	select_node.predicate = predicate_result.get_value() as GDSQLQueryExpression
	graph.add_node(select_node)
	var compilation := GDSQLGraphQueryCompiler.new().compile(graph)
	if compilation.is_successful():
		query_requested.emit(
			get_selected_registration(),
			compilation.query,
		)
	return compilation


func present_query_result(
		registration_name: StringName,
		table: GDSQLTableDefinition,
		result: GDSQLQueryResult,
) -> void:
	if _table_result == null:
		_table_result = TABLE_RESULT_NODE_SCENE.instantiate() \
				as GDSQLQueryTableResultNode
		_table_result.name = &"TableResult"
		_graph.add_child(_table_result)
		_table_result.row_insert_requested.connect(row_insert_requested.emit)
		_table_result.row_update_requested.connect(row_update_requested.emit)
		_table_result.row_delete_requested.connect(row_delete_requested.emit)
		_table_result.capabilities_changed.connect(_on_result_capabilities_changed)
		if _action_hub != null and _action_context != null:
			_table_result.configure_action(
				_action_hub,
				_action_context.get_action(
					GDSQLEditorActionIds.ADD_QUERY_RESULT_ROW,
				),
			)
	_place_and_connect_result()
	_table_result.present(registration_name, table, result)


func _register_action(
		action_id: StringName,
		label: String,
		tooltip: String,
		group: StringName,
		order: int,
		handler: Callable,
) -> void:
	_action_context.add_action(
		GDSQLEditorActionDefinition.new(
			action_id,
			label,
			tooltip,
			&"",
			group,
			order,
		),
		handler,
	)


func _configure_action_buttons() -> void:
	var buttons: Dictionary[StringName, GDSQLEditorActionButton] = {
		GDSQLEditorActionIds.OPEN_QUERY_GRAPH_FOLDER: _open_graph_folder,
		GDSQLEditorActionIds.SAVE_QUERY_GRAPH: _save_graph,
		GDSQLEditorActionIds.ADD_SELECT_QUERY_NODE: _add_select,
		GDSQLEditorActionIds.ADD_LEFT_JOIN_QUERY_NODE: _add_left_join,
		GDSQLEditorActionIds.ADD_INSERT_QUERY_NODE: _add_insert,
		GDSQLEditorActionIds.ADD_UPDATE_QUERY_NODE: _add_update,
		GDSQLEditorActionIds.ADD_DELETE_QUERY_NODE: _add_delete,
	}
	for action_id in buttons:
		buttons[action_id].configure(
			_action_hub,
			_action_context.get_action(action_id),
		)


func _add_select_node() -> GDSQLOperationResult:
	var selected_registration := get_selected_registration()
	var selected_table := get_selected_table()
	var node := SELECT_NODE_SCENE.instantiate() as GraphNode
	node.name = _next_select_node_name()
	_graph.add_child(node)
	_active_select_operation = node
	node.position_offset = Vector2(96, 96) + Vector2(36, 36) * _select_node_count()
	_connect_select_node(node)
	if _action_hub != null and _action_context != null:
		node.call(
			"configure_query_action",
			_action_hub,
			_action_context.get_action(GDSQLEditorActionIds.RUN_QUERY_GRAPH),
		)
	node.call(
		"configure",
		_inspections,
		selected_registration,
		selected_table,
	)
	_graph.set_selected(node)
	var result := GDSQLOperationResult.new()
	result.value = node
	return result


func _next_select_node_name() -> StringName:
	var suffix := 2
	while _graph.has_node("SelectOperation%d" % suffix):
		suffix += 1
	return StringName("SelectOperation%d" % suffix)


func _select_node_count() -> int:
	var count := 0
	for child in _graph.get_children():
		if child is GraphNode and child.has_method("get_selected_table"):
			count += 1
	return count


func _unavailable_action(capability: String) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.add_diagnostic(
		GDSQLQueryDiagnostic.new(
			&"GDSQL_QUERY_GRAPH_ACTION_NOT_IMPLEMENTED",
			"%s is not implemented yet." % capability,
		),
	)
	return result


func _on_source_changed(
		registration_name: StringName,
		database_name: StringName,
		table_name: StringName,
		source_node: GraphNode,
) -> void:
	_active_select_operation = source_node
	source_changed.emit(registration_name, database_name, table_name)
	_refresh_action_availability()


func _on_query_changed(source_node: GraphNode) -> void:
	_active_select_operation = source_node
	_refresh_action_availability()


func _on_query_activated(source_node: GraphNode) -> void:
	_active_select_operation = source_node
	_graph.set_selected(source_node)
	_refresh_action_availability()


func _on_remove_requested(source_node: GraphNode) -> void:
	_on_query_activated(source_node)
	if _action_hub != null:
		_action_hub.invoke(GDSQLEditorActionIds.REMOVE_QUERY_GRAPH_NODE)


func _selected_source_value(method: StringName) -> StringName:
	if not is_instance_valid(_active_select_operation) \
			or not _active_select_operation.has_method(method):
		return &""
	return StringName(_active_select_operation.call(method))


func _on_graph_node_selected(node: Node) -> void:
	if node is GraphNode and node.has_method("get_selected_table"):
		_active_select_operation = node as GraphNode
		_refresh_action_availability()


func _refresh_action_availability() -> void:
	if _action_context == null:
		return
	_action_context.set_action_enabled(
		GDSQLEditorActionIds.RUN_QUERY_GRAPH,
		get_selected_registration() != &""
		and get_selected_database() != &""
		and get_selected_table() != &""
		and _selected_column_count() > 0
		and _active_predicate_is_valid(),
	)
	_action_context.set_action_enabled(
		GDSQLEditorActionIds.REMOVE_QUERY_GRAPH_NODE,
		is_instance_valid(_active_select_operation),
	)


func _add_result_row() -> GDSQLOperationResult:
	if _table_result == null:
		return _unavailable_action("Adding query-result rows")
	return _table_result.add_empty_row()


func _on_result_capabilities_changed(
		can_add_rows: bool,
		_has_dirty_rows: bool,
) -> void:
	if _action_context != null:
		_action_context.set_action_enabled(
			GDSQLEditorActionIds.ADD_QUERY_RESULT_ROW,
			can_add_rows,
		)


func _place_and_connect_result() -> void:
	if _active_select_operation == null or _table_result == null:
		return
	_table_result.position_offset = (
			_active_select_operation.position_offset + Vector2(420, 0)
	)
	for connection in _graph.get_connection_list():
		if StringName(connection["to_node"]) == _table_result.name:
			_graph.disconnect_node(
				StringName(connection["from_node"]),
				int(connection["from_port"]),
				StringName(connection["to_node"]),
				int(connection["to_port"]),
			)
	_graph.connect_node(_active_select_operation.name, 0, _table_result.name, 0)
	_result_source = _active_select_operation


func _connect_select_node(node: GraphNode) -> void:
	node.connect("source_changed", _on_source_changed.bind(node))
	node.connect("query_changed", _on_query_changed.bind(node))
	node.connect("query_activated", _on_query_activated.bind(node))
	node.connect("remove_requested", _on_remove_requested.bind(node))


func _configure_select_query_buttons() -> void:
	if _action_hub == null or _action_context == null:
		return
	for child in _graph.get_children():
		if child is GraphNode and child.has_method("configure_query_action"):
			child.call(
				"configure_query_action",
				_action_hub,
				_action_context.get_action(GDSQLEditorActionIds.RUN_QUERY_GRAPH),
			)


func _remove_active_select_node() -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	var node := _active_select_operation
	if not is_instance_valid(node):
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_QUERY_GRAPH_NODE_REQUIRED",
				"Select a query operation node to remove.",
			),
		)
		return result
	if _result_source == node:
		_remove_table_result()
	_disconnect_node(node)
	_graph.remove_child(node)
	node.queue_free()
	_active_select_operation = _first_select_node()
	if _active_select_operation != null:
		_graph.set_selected(_active_select_operation)
	result.value = node
	_refresh_action_availability()
	return result


func _remove_table_result() -> void:
	if not is_instance_valid(_table_result):
		return
	_disconnect_node(_table_result)
	_graph.remove_child(_table_result)
	_table_result.queue_free()
	_table_result = null
	_result_source = null
	if _action_context != null:
		_action_context.set_action_enabled(
			GDSQLEditorActionIds.ADD_QUERY_RESULT_ROW,
			false,
		)


func _disconnect_node(node: GraphNode) -> void:
	for connection in _graph.get_connection_list():
		if StringName(connection["from_node"]) == node.name \
				or StringName(connection["to_node"]) == node.name:
			_graph.disconnect_node(
				StringName(connection["from_node"]),
				int(connection["from_port"]),
				StringName(connection["to_node"]),
				int(connection["to_port"]),
			)


func _first_select_node() -> GraphNode:
	for child in _graph.get_children():
		if child is GraphNode and child.has_method("get_selected_table"):
			return child as GraphNode
	return null


func _selected_column_count() -> int:
	if not is_instance_valid(_active_select_operation) \
			or not _active_select_operation.has_method("get_selected_columns"):
		return 0
	var columns: Array[StringName] = _active_select_operation.call(
		"get_selected_columns",
	)
	return columns.size()


func _active_predicate_is_valid() -> bool:
	if not is_instance_valid(_active_select_operation) \
			or not _active_select_operation.has_method("build_predicate"):
		return false
	var result := _active_select_operation.call(
		"build_predicate",
	) as GDSQLOperationResult
	return result != null and result.is_successful()
