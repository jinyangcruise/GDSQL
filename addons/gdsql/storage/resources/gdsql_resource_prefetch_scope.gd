class_name GDSQLResourcePrefetchScope
extends RefCounted
## Caller-owned lifetime boundary for a bounded group of Resource handles.

signal status_changed(status: Status)
signal progress_changed(progress: GDSQLResourcePrefetchProgress)
signal completed(resources: Array[Resource])
signal failed(diagnostics: Array[GDSQLQueryDiagnostic])
signal released

enum Status { READY, LOADING, LOADED, FAILED }

var _handles: Array[GDSQLResourceHandle] = []
var _status := Status.READY
var _diagnostics := GDSQLDiagnostics.new()


static func from_handles(handles: Array[GDSQLResourceHandle]) -> GDSQLResourcePrefetchScope:
	var scope := GDSQLResourcePrefetchScope.new()
	for handle in handles:
		scope.add_handle(handle)
	return scope


func add_handle(handle: GDSQLResourceHandle) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if _status != Status.READY:
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_RESOURCE_PREFETCH_SCOPE_ACTIVE",
				"Release the active prefetch scope before changing its handles.",
			),
		)
		return result
	if handle == null:
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_RESOURCE_PREFETCH_HANDLE_REQUIRED",
				"A Resource handle is required for prefetching.",
			),
		)
		return result
	if not _handles.has(handle):
		_handles.append(handle)
	result.value = self
	return result


func get_handles() -> Array[GDSQLResourceHandle]:
	return _handles.duplicate()


func get_resources() -> Array[Resource]:
	var resources: Array[Resource] = []
	for handle in _handles:
		if handle.is_loaded():
			resources.append(handle.get_resource())
	return resources


func get_status() -> Status:
	return _status


func get_progress() -> GDSQLResourcePrefetchProgress:
	var snapshot := GDSQLResourcePrefetchProgress.new()
	snapshot.total_count = _handles.size()
	var progress_total := 0.0
	for handle in _handles:
		match handle.get_status():
			GDSQLResourceHandle.Status.LOADED:
				snapshot.loaded_count += 1
				progress_total += 1.0
			GDSQLResourceHandle.Status.FAILED:
				snapshot.failed_count += 1
				progress_total += 1.0
			GDSQLResourceHandle.Status.LOADING:
				progress_total += handle.get_progress()
	snapshot.progress = (
		1.0 if snapshot.total_count == 0 else progress_total / snapshot.total_count
	)
	if snapshot.is_complete():
		snapshot.status = (
			GDSQLResourcePrefetchProgress.Status.FAILED
			if snapshot.failed_count > 0
			else GDSQLResourcePrefetchProgress.Status.LOADED
		)
	return snapshot


func get_diagnostics() -> Array[GDSQLQueryDiagnostic]:
	return _diagnostics.entries.duplicate()


func request_load() -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if _status == Status.LOADING or _status == Status.LOADED:
		result.value = get_progress()
		return result
	_diagnostics = GDSQLDiagnostics.new()
	for handle in _handles:
		if handle.is_loaded():
			continue
		var requested := handle.request_load()
		result.diagnostics.merge(requested.diagnostics)
		_diagnostics.merge(requested.diagnostics)
	_refresh_status()
	result.value = get_progress()
	return result


func poll_load() -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if _status == Status.READY:
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_RESOURCE_PREFETCH_NOT_REQUESTED",
				"Request the prefetch scope before polling it.",
			),
		)
		return result
	if _status == Status.LOADED or _status == Status.FAILED:
		result.diagnostics.merge(_diagnostics)
		result.value = get_progress()
		return result
	for handle in _handles:
		if handle.get_status() != GDSQLResourceHandle.Status.LOADING:
			continue
		var polled := handle.poll_load()
		result.diagnostics.merge(polled.diagnostics)
		_diagnostics.merge(polled.diagnostics)
	_refresh_status()
	result.diagnostics = GDSQLDiagnostics.new()
	result.diagnostics.merge(_diagnostics)
	result.value = get_progress()
	return result


## Releases every handle-owned strong reference. Native threaded requests may
## still finish in Godot's cache, and external scene or Resource references are
## unaffected.
func release() -> void:
	for handle in _handles:
		handle.release()
	_diagnostics = GDSQLDiagnostics.new()
	_set_status(Status.READY)
	progress_changed.emit(get_progress())
	released.emit()


func _refresh_status() -> void:
	var snapshot := get_progress()
	var next_status := Status.LOADING
	if snapshot.is_complete():
		next_status = Status.FAILED if snapshot.failed_count > 0 else Status.LOADED
	_set_status(next_status)
	progress_changed.emit(snapshot)
	if next_status == Status.LOADED:
		completed.emit(get_resources())
	elif next_status == Status.FAILED:
		failed.emit(get_diagnostics())


func _set_status(value: Status) -> void:
	if _status == value:
		return
	_status = value
	status_changed.emit(_status)
