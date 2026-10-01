class_name GDSQLResourceHandle
extends RefCounted
## Explicit, caller-owned materialization state for one referenced Resource.

signal status_changed(status: Status)

enum Status { UNLOADED, LOADING, LOADED, FAILED }

var _reference: GDSQLResourceReference
var _resolver: GDSQLResourceResolver
var _resource: Resource
var _status := Status.UNLOADED
var _diagnostics := GDSQLDiagnostics.new()


func _init(
		reference: GDSQLResourceReference,
		resolver: GDSQLResourceResolver = null,
) -> void:
	_reference = reference.duplicate_reference() if reference != null else null
	_resolver = resolver if resolver != null else GDSQLGodotResourceResolver.new()


func get_reference() -> GDSQLResourceReference:
	return _reference.duplicate_reference() if _reference != null else null


func get_status() -> Status:
	return _status


func get_resource() -> Resource:
	return _resource


func get_diagnostics() -> Array[GDSQLQueryDiagnostic]:
	return _diagnostics.entries.duplicate()


func is_loaded() -> bool:
	return _status == Status.LOADED and _resource != null


func load() -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if is_loaded():
		result.value = _resource
		return result
	if _reference == null or not _reference.is_valid() or _resolver == null:
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_RESOURCE_HANDLE_INVALID",
				"Deferred Resource loading requires a valid reference and resolver.",
			),
		)
		_finish_failure(result)
		return result
	_set_status(Status.LOADING)
	var resolved := _resolver.resolve(_reference)
	result.diagnostics.merge(resolved.diagnostics)
	if not resolved.is_successful():
		_finish_failure(result)
		return result
	var loaded := resolved.get_value() as Resource
	if loaded == null or not _reference.accepts_resource(loaded):
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_RESOURCE_HANDLE_TYPE_MISMATCH",
				"Loaded Resource does not match deferred type '%s'." \
						% _reference.expected_type,
				GDSQLQueryDiagnostic.Severity.ERROR,
				null,
				_reference,
			),
		)
		_finish_failure(result)
		return result
	_resource = loaded
	_diagnostics = GDSQLDiagnostics.new()
	_set_status(Status.LOADED)
	result.value = _resource
	return result


## Releases only the handle's strong reference. Godot may retain the Resource
## while scenes, other handles, or its global cache still reference it.
func release() -> void:
	_resource = null
	_diagnostics = GDSQLDiagnostics.new()
	_set_status(Status.UNLOADED)


func _finish_failure(result: GDSQLOperationResult) -> void:
	_resource = null
	_diagnostics = GDSQLDiagnostics.new()
	_diagnostics.merge(result.diagnostics)
	_set_status(Status.FAILED)


func _set_status(value: Status) -> void:
	if _status == value:
		return
	_status = value
	status_changed.emit(_status)
