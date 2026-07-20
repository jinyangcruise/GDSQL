@abstract
class_name GDSQLResultMaterializer
extends RefCounted

@abstract
func materialize(rows: GDSQLRowSet, mapping: GDSQLResultMapping = null) -> GDSQLQueryResult


func _create_result(rows: GDSQLRowSet) -> GDSQLQueryResult:
	var result := GDSQLQueryResult.new()
	if rows == null:
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_MATERIALIZATION_ROWS_REQUIRED",
				"Materialization requires a row set.",
			),
		)
		return result
	result.rows = rows.rows.duplicate()
	result.schema = rows.schema
	result.statistics = { "returned_rows": rows.rows.size() }
	return result


func _source_columns(
		row: GDSQLRowRecord,
		mapping: GDSQLResultMapping,
) -> Array[StringName]:
	if mapping != null and mapping.has_explicit_columns():
		return mapping.get_source_columns()
	var columns: Array[StringName] = []
	for column: StringName in row.values:
		columns.append(column)
	return columns
