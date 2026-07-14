class_name GDSQLQueryResult
extends RefCounted

var rows: Array[GDSQLRowRecord] = []
var diagnostics: Array[GDSQLQueryDiagnostic] = []
var statistics: Dictionary = { }


func is_successful() -> bool:
	for diagnostic in diagnostics:
		if diagnostic.severity == GDSQLQueryDiagnostic.Severity.ERROR:
			return false
	return true


func get_rows() -> Array[GDSQLRowRecord]:
	return rows


func get_diagnostics() -> Array[GDSQLQueryDiagnostic]:
	return diagnostics


func get_affected_rows() -> int:
	return int(statistics.get("affected_rows", 0))


func get_returned_rows() -> int:
	return int(statistics.get("returned_rows", rows.size()))
