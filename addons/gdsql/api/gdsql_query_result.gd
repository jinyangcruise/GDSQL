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
