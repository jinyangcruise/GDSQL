class_name GDSQLQueryDiagnostic
extends RefCounted

enum Severity { INFO, WARNING, ERROR }

var code: StringName
var severity: Severity = Severity.ERROR
var message: String = ""
var source_span: GDSQLSourceSpan
var related_object: Variant


func _init(
		code: StringName = &"",
		message: String = "",
		severity: Severity = Severity.ERROR,
		source_span: GDSQLSourceSpan = null,
		related_object: Variant = null,
) -> void:
	self.code = code
	self.message = message
	self.severity = severity
	self.source_span = source_span
	self.related_object = related_object
