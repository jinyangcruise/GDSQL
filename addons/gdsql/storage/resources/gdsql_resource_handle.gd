class_name GDSQLResourceHandle
extends RefCounted
## Explicit, caller-owned materialization state for one referenced Resource.

signal status_changed(status: Status)
signal load_completed(resource: Resource)
signal load_failed(diagnostics: Array[GDSQLQueryDiagnostic])

enum Status { UNLOADED, LOADING, LOADED, FAILED }

var _reference: GDSQLResourceReference
var _resolver: GDSQLResourceResolver
var _resource: Resource
var _status := Status.UNLOADED
var _progress: float
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


func get_progress() -> float:
	return _progress


func get_diagnostics() -> Array[GDSQLQueryDiagnostic]:
	return _diagnostics.entries.duplicate()


func is_loaded() -> bool:
	return _status == Status.LOADED and _resource != null


func load() -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if is_loaded():
		result.value = _resource
		return result
	if _status == Status.LOADING:
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_RESOURCE_HANDLE_LOADING",
				"Cannot synchronously load a Resource while its threaded request is active.",
			),
		)
		return result
	if not _validate(result):
		return result
	_set_status(Status.LOADING)
	var resolved := _resolver.resolve(_reference)
	result.diagnostics.merge(resolved.diagnostics)
	if not resolved.is_successful():
		_finish_failure(result)
		return result
	_complete_load(resolved.get_value() as Resource, result)
	return result


func request_load() -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if is_loaded() or _status == Status.LOADING:
		result.value = self
		return result
	if not _validate(result):
		return result
	var requested := _resolver.request_threaded(_reference)
	result.diagnostics.merge(requested.diagnostics)
	if not requested.is_successful():
		_finish_failure(result)
		return result
	_progress = 0.0
	_diagnostics = GDSQLDiagnostics.new()
	_set_status(Status.LOADING)
	result.value = self
	return result


func poll_load() -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if is_loaded():
		result.value = GDSQLResourceLoadProgress.loaded(_resource)
		return result
	if _status != Status.LOADING:
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_RESOURCE_HANDLE_NOT_LOADING",
				"Request threaded loading before polling this Resource handle.",
			),
		)
		return result
	var polled := _resolver.poll_threaded(_reference)
	result.diagnostics.merge(polled.diagnostics)
	if not polled.is_successful():
		_finish_failure(result)
		return result
	var snapshot := polled.get_value() as GDSQLResourceLoadProgress
	if snapshot == null:
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_RESOURCE_THREADED_PROGRESS_MISSING",
				"Resource resolver did not return threaded load progress.",
			),
		)
		_finish_failure(result)
		return result
	_progress = snapshot.progress
	if snapshot.is_complete():
		_complete_load(snapshot.resource, result)
	result.value = snapshot
	return result


## Releases only the handle's strong reference. Godot may retain the Resource
## while scenes, other handles, or its global cache still reference it.
func release() -> void:
	_resource = null
	_progress = 0.0
	_diagnostics = GDSQLDiagnostics.new()
	_set_status(Status.UNLOADED)


func _validate(result: GDSQLOperationResult) -> bool:
	if _reference != null and _reference.is_valid() and _resolver != null:
		return true
	result.add_diagnostic(
		GDSQLQueryDiagnostic.new(
			&"GDSQL_RESOURCE_HANDLE_INVALID",
			"Deferred Resource loading requires a valid reference and resolver.",
		),
	)
	_finish_failure(result)
	return false


func _complete_load(resource: Resource, result: GDSQLOperationResult) -> void:
	if resource == null or not _reference.accepts_resource(resource):
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
		return
	_resource = resource
	_progress = 1.0
	_diagnostics = GDSQLDiagnostics.new()
	_set_status(Status.LOADED)
	result.value = _resource
	load_completed.emit(_resource)


func _finish_failure(result: GDSQLOperationResult) -> void:
	_resource = null
	_progress = 0.0
	_diagnostics = GDSQLDiagnostics.new()
	_diagnostics.merge(result.diagnostics)
	_set_status(Status.FAILED)
	load_failed.emit(get_diagnostics())


func _set_status(value: Status) -> void:
	if _status == value:
		return
	_status = value
	status_changed.emit(_status)
