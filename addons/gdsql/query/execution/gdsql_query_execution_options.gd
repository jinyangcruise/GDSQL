class_name GDSQLQueryExecutionOptions
extends RefCounted
## Presentation policy applied while executing one canonical query.
##
## This policy remains outside QuerySpec because it changes how runtime values
## are returned, not the meaning of the requested database operation.

enum ResourceMode { EAGER, DEFERRED }

var _resource_mode := ResourceMode.EAGER


static func eager() -> GDSQLQueryExecutionOptions:
	return GDSQLQueryExecutionOptions.new(ResourceMode.EAGER)


static func deferred_resources() -> GDSQLQueryExecutionOptions:
	return GDSQLQueryExecutionOptions.new(ResourceMode.DEFERRED)


func _init(resource_mode: ResourceMode = ResourceMode.EAGER) -> void:
	_resource_mode = resource_mode


func get_resource_mode() -> ResourceMode:
	return _resource_mode


func defers_resources() -> bool:
	return _resource_mode == ResourceMode.DEFERRED
