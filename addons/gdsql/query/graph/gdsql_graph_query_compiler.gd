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
	var node: Variant = graph.nodes[0]
	if node is GDSQLQueryGraphSelectNode:
		result.query = _compile_select(node as GDSQLQueryGraphSelectNode)
	elif node is GDSQLQueryGraphInsertNode:
		result.query = _compile_insert(node as GDSQLQueryGraphInsertNode)
	elif node is GDSQLQueryGraphUpdateNode:
		result.query = _compile_update(node as GDSQLQueryGraphUpdateNode)
	elif node is GDSQLQueryGraphDeleteNode:
		result.query = _compile_delete(node as GDSQLQueryGraphDeleteNode)
	result.value = result.query
	return result


func _compile_select(select_node: GDSQLQueryGraphSelectNode) -> GDSQLSelectQuerySpec:
	var builder := GDSQLSelectQueryBuilder.new(
		select_node.database_name,
		select_node.table_name,
	)
	if not select_node.include_all_columns:
		builder.columns(select_node.projections)
	if select_node.predicate != null:
		builder.where(select_node.predicate)
	return builder.build()


func _compile_insert(insert_node: GDSQLQueryGraphInsertNode) -> GDSQLInsertQuerySpec:
	var row: Dictionary = { }
	for index in range(insert_node.columns.size()):
		row[insert_node.columns[index]] = insert_node.values[index]
	return GDSQLInsertQueryBuilder.new(
		insert_node.database_name,
		insert_node.table_name,
	).values(row).build()


func _compile_update(update_node: GDSQLQueryGraphUpdateNode) -> GDSQLUpdateQuerySpec:
	var builder := GDSQLUpdateQueryBuilder.new(
		update_node.database_name,
		update_node.table_name,
	)
	for assignment in update_node.assignments:
		builder.set_expression(assignment.column, assignment.expression)
	if update_node.predicate != null:
		builder.where(update_node.predicate)
	return builder.build()


func _compile_delete(delete_node: GDSQLQueryGraphDeleteNode) -> GDSQLDeleteQuerySpec:
	var builder := GDSQLDeleteQueryBuilder.new(
		delete_node.database_name,
		delete_node.table_name,
	)
	if delete_node.predicate != null:
		builder.where(delete_node.predicate)
	return builder.build()
