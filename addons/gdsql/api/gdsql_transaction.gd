class_name GDSQLTransaction
extends RefCounted

var diagnostics := GDSQLDiagnostics.new()

var _context: GDSQLDatabaseContext
var _session: GDSQLStorageSession
var _active: bool = true
var _failed: bool = false


func _init(
		context: GDSQLDatabaseContext = null,
		session: GDSQLStorageSession = null,
) -> void:
	_context = context
	_session = session


func execute(query_spec: GDSQLQuerySpec) -> GDSQLQueryResult:
	if not _active:
		return _invalid_execution_result(
			&"GDSQL_TRANSACTION_CLOSED",
			"A transaction cannot execute queries after its callback exits.",
		)
	if _failed:
		return _invalid_execution_result(
			&"GDSQL_TRANSACTION_ABORTED",
			"The transaction has already failed and cannot execute more queries.",
		)
	var result := _context.execute_in_session(query_spec, _session)
	diagnostics.merge(result.diagnostics)
	if not result.is_successful():
		_failed = true
	return result


func _has_failed() -> bool:
	return _failed


func _close() -> void:
	_active = false


func _invalid_execution_result(
		code: StringName,
		message: String,
) -> GDSQLQueryResult:
	var result := GDSQLQueryResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
