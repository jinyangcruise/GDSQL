class_name GDSQLDirectSetupReport
extends RefCounted
## Typed, ordered setup status shared by runtime startup and editor guidance.

var checks: Array[GDSQLDirectSetupCheck] = []
var diagnostics := GDSQLDiagnostics.new()


func add_check(check: GDSQLDirectSetupCheck) -> void:
	if check == null:
		return
	checks.append(check)
	if not check.complete:
		diagnostics.add(
			GDSQLQueryDiagnostic.new(
				StringName("GDSQL_DIRECT_SETUP_%s" % String(check.id).to_upper()),
				check.detail,
				GDSQLQueryDiagnostic.Severity.WARNING,
			),
		)


func is_ready() -> bool:
	return get_next_incomplete() == null


func get_next_incomplete() -> GDSQLDirectSetupCheck:
	for check in checks:
		if not check.complete:
			return check
	return null


func get_check(check_id: StringName) -> GDSQLDirectSetupCheck:
	for check in checks:
		if check.id == check_id:
			return check
	return null
