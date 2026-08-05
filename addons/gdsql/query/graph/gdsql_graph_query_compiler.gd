class_name GDSQLGraphQueryCompiler
extends RefCounted


func compile(graph: GDSQLQueryGraph) -> GDSQLQueryCompilationResult:
	var result := GDSQLQueryCompilationResult.new()
	if graph == null:
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_QUERY_GRAPH_REQUIRED",
				"A query graph is required for compilation.",
			),
		)
		return result
	var validation := graph.validate_structure()
	result.diagnostics.merge(validation.diagnostics)
	if not validation.is_successful():
		return result
	var select_node := graph.nodes[0] as GDSQLQueryGraphSelectNode
	var builder := GDSQLSelectQueryBuilder.new(
		select_node.database_name,
		select_node.table_name,
	)
	if not select_node.projections.is_empty():
		builder.columns(select_node.projections)
	if select_node.predicate != null:
		builder.where(select_node.predicate)
	result.query = builder.build()
	result.value = result.query
	return result
