class_name GDSQLQueryGraph
extends RefCounted

var nodes: Array[Variant] = []
var connections: Array[Variant] = []


func add_node(node: Variant) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if node == null:
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_QUERY_GRAPH_NODE_REQUIRED",
				"A query graph node is required.",
			),
		)
		return result
	nodes.append(node)
	result.value = node
	return result


func get_nodes() -> Array[Variant]:
	return nodes


func get_connections() -> Array[Variant]:
	return connections


func validate_structure() -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if nodes.is_empty():
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_QUERY_GRAPH_EMPTY",
				"The query graph has no operation to execute.",
			),
		)
		return result
	if nodes.size() != 1:
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_QUERY_GRAPH_SINGLE_ROOT_REQUIRED",
				"The current query graph compiler requires one selected root operation.",
			),
		)
		return result
	var node: Variant = nodes[0]
	if not (
			node is GDSQLQueryGraphSelectNode
			or node is GDSQLQueryGraphInsertNode
			or node is GDSQLQueryGraphUpdateNode
			or node is GDSQLQueryGraphDeleteNode
	):
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_QUERY_GRAPH_OPERATION_UNSUPPORTED",
				"The selected graph operation cannot be compiled.",
			),
		)
		return result
	var database_name: StringName = node.database_name
	var table_name: StringName = node.table_name
	if database_name == &"" or table_name == &"":
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_QUERY_GRAPH_SOURCE_REQUIRED",
				"The query operation requires a database and table.",
			),
		)
		return result
	if node is GDSQLQueryGraphSelectNode:
		return _validate_select(node as GDSQLQueryGraphSelectNode, result)
	if node is GDSQLQueryGraphInsertNode:
		return _validate_insert(node as GDSQLQueryGraphInsertNode, result)
	if node is GDSQLQueryGraphUpdateNode:
		return _validate_update(node as GDSQLQueryGraphUpdateNode, result)
	result.value = self
	return result


func _validate_select(
		node: GDSQLQueryGraphSelectNode,
		result: GDSQLOperationResult,
) -> GDSQLOperationResult:
	if not node.include_all_columns and node.projections.is_empty():
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_QUERY_GRAPH_SELECT_PROJECTION_REQUIRED",
				"Select at least one result column.",
			),
		)
		return result
	result.value = self
	return result


func _validate_insert(
		node: GDSQLQueryGraphInsertNode,
		result: GDSQLOperationResult,
) -> GDSQLOperationResult:
	if node.columns.is_empty() or node.columns.size() != node.values.size():
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_QUERY_GRAPH_INSERT_VALUES_REQUIRED",
				"INSERT requires at least one valid column value.",
			),
		)
		return result
	result.value = self
	return result


func _validate_update(
		node: GDSQLQueryGraphUpdateNode,
		result: GDSQLOperationResult,
) -> GDSQLOperationResult:
	if node.assignments.is_empty():
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_QUERY_GRAPH_UPDATE_ASSIGNMENT_REQUIRED",
				"UPDATE requires at least one valid assignment.",
			),
		)
		return result
	result.value = self
	return result
