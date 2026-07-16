class_name GDSQLOperationResult
extends RefCounted

var value: Variant
var diagnostics := GDSQLDiagnostics.new()


func is_successful() -> bool:
	return diagnostics.is_successful()


func add_diagnostic(diagnostic: GDSQLQueryDiagnostic) -> void:
	diagnostics.add(diagnostic)
