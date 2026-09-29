class_name GDSQLSetupReport
extends RefCounted
## Typed ordered status shared by setup-profile inspectors and frontends.

var checks: Array[GDSQLSetupCheck] = []
var diagnostics := GDSQLDiagnostics.new()
var _diagnostic_prefix: String


func _init(diagnostic_prefix: String = "GDSQL_SETUP") -> void:
	_diagnostic_prefix = diagnostic_prefix


func add_check(check: GDSQLSetupCheck) -> void:
	if check == null:
		return
	checks.append(check)
	if not check.complete:
		diagnostics.add(
			GDSQLQueryDiagnostic.new(
				StringName("%s_%s" % [_diagnostic_prefix, String(check.id).to_upper()]),
				check.detail,
				GDSQLQueryDiagnostic.Severity.WARNING,
			),
		)


func is_ready() -> bool:
	return get_next_incomplete() == null


func get_next_incomplete() -> GDSQLSetupCheck:
	for check in checks:
		if not check.complete:
			return check
	return null


func get_check(check_id: StringName) -> GDSQLSetupCheck:
	for check in checks:
		if check.id == check_id:
			return check
	return null
