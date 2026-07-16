class_name GDSQLDiagnostics
extends RefCounted

var entries: Array[GDSQLQueryDiagnostic] = []


func add(diagnostic: GDSQLQueryDiagnostic) -> void:
	if diagnostic != null:
		entries.append(diagnostic)


func merge(other: GDSQLDiagnostics) -> void:
	if other != null:
		entries.append_array(other.entries)


func has_errors() -> bool:
	for diagnostic in entries:
		if diagnostic.severity == GDSQLQueryDiagnostic.Severity.ERROR:
			return true
	return false


func is_successful() -> bool:
	return not has_errors()


func is_empty() -> bool:
	return entries.is_empty()


func size() -> int:
	return entries.size()


func print_to_debug(
		minimum_severity: GDSQLQueryDiagnostic.Severity = GDSQLQueryDiagnostic.Severity.ERROR,
) -> void:
	for diagnostic in entries:
		if diagnostic.severity >= minimum_severity:
			print_debug("[%s] %s" % [diagnostic.code, diagnostic.message])
