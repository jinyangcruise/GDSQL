class_name GDSQLQueryResult
extends GDSQLOperationResult

var rows: Array[GDSQLRowRecord] = []
var statistics: Dictionary = { }
var schema: GDSQLResultSchema


func get_rows() -> Array[GDSQLRowRecord]:
	return rows


func get_diagnostics() -> Array[GDSQLQueryDiagnostic]:
	return diagnostics.entries


func get_schema() -> GDSQLResultSchema:
	return schema


func get_affected_rows() -> int:
	return int(statistics.get("affected_rows", 0))


func get_returned_rows() -> int:
	return int(statistics.get("returned_rows", rows.size()))


func materialize(
		materializer: GDSQLResultMaterializer,
		mapping: GDSQLResultMapping = null,
) -> GDSQLQueryResult:
	if materializer == null:
		var invalid_result := GDSQLQueryResult.new()
		invalid_result.diagnostics.merge(diagnostics)
		invalid_result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_MATERIALIZATION_STRATEGY_REQUIRED",
				"A result materializer is required.",
			),
		)
		return invalid_result
	var row_set := GDSQLRowSet.new()
	row_set.rows = rows.duplicate()
	row_set.schema = schema
	var result := materializer.materialize(row_set, mapping)
	result.diagnostics.merge(diagnostics)
	result.statistics = statistics.duplicate()
	return result
