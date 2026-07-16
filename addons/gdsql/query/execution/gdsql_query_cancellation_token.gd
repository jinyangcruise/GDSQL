class_name GDSQLQueryCancellationToken
extends RefCounted

var _cancelled: bool = false


func cancel() -> void:
	_cancelled = true


func is_cancelled() -> bool:
	return _cancelled
