class_name GDSQLModelCompatibilityReport
extends RefCounted
## Read-only comparison between one user model and its authoritative table.

var definition: GDSQLModelDefinition
var diagnostics := GDSQLDiagnostics.new()
var relationship_summaries: Array[String] = []


func is_compatible() -> bool:
	return not diagnostics.has_errors()


func add_diagnostic(diagnostic: GDSQLQueryDiagnostic) -> void:
	diagnostics.add(diagnostic)
