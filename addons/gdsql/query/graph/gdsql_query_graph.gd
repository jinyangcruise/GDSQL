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
	if not node is GDSQLQueryGraphSelectNode:
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_QUERY_GRAPH_OPERATION_UNSUPPORTED",
				"Only SELECT graph operations can be compiled currently.",
			),
		)
		return result
	var select_node := node as GDSQLQueryGraphSelectNode
	if select_node.database_name == &"" or select_node.table_name == &"":
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_QUERY_GRAPH_SELECT_SOURCE_REQUIRED",
				"The SELECT operation requires a database and table.",
			),
		)
		return result
	if not select_node.include_all_columns and select_node.projections.is_empty():
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_QUERY_GRAPH_SELECT_PROJECTION_REQUIRED",
				"Select at least one result column.",
			),
		)
		return result
	result.value = self
	return result
