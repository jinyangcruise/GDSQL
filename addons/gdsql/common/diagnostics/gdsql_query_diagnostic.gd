class_name GDSQLQueryDiagnostic
extends RefCounted

enum Severity { INFO, WARNING, ERROR }

var code: StringName
var severity: Severity = Severity.ERROR
var message: String = ""
var source_span: GDSQLSourceSpan
var related_object: Variant


func _init(
		_code: StringName = &"",
		_message: String = "",
		_severity: Severity = Severity.ERROR,
		_source_span: GDSQLSourceSpan = null,
		_related_object: Variant = null,
) -> void:
	code = _code
	message = _message
	severity = _severity
	source_span = _source_span
	related_object = _related_object
