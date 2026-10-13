class_name GDSQLGodotResourceResolver
extends GDSQLResourceResolver
## Default Resource materializer using Godot UID/path resolution and cache.


func resolve(reference: GDSQLResourceReference) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	var validated := _validated_path(reference)
	result.diagnostics.merge(validated.diagnostics)
	if not validated.is_successful():
		return result
	var path := String(validated.get_value())
	var resource := ResourceLoader.load(path)
	if resource == null:
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_RESOURCE_REFERENCE_LOAD_FAILED",
				"Could not load referenced Resource: %s" % path,
				GDSQLQueryDiagnostic.Severity.ERROR,
				null,
				reference,
			),
		)
		return result
	result.value = resource
	return result


func request_threaded(
		reference: GDSQLResourceReference,
) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	var validated := _validated_path(reference)
	result.diagnostics.merge(validated.diagnostics)
	if not validated.is_successful():
		return result
	var path := String(validated.get_value())
	var existing_status := ResourceLoader.load_threaded_get_status(path)
	if existing_status in [
		ResourceLoader.THREAD_LOAD_IN_PROGRESS,
		ResourceLoader.THREAD_LOAD_LOADED,
	]:
		result.value = true
		return result
	var request_error := ResourceLoader.load_threaded_request(path)
	if request_error != OK:
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_RESOURCE_THREADED_REQUEST_FAILED",
				"Could not request threaded Resource loading for '%s' (error %d)." \
						% [path, request_error],
				GDSQLQueryDiagnostic.Severity.ERROR,
				null,
				reference,
			),
		)
		return result
	result.value = true
	return result


func poll_threaded(
		reference: GDSQLResourceReference,
) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	var validated := _validated_path(reference)
	result.diagnostics.merge(validated.diagnostics)
	if not validated.is_successful():
		return result
	var path := String(validated.get_value())
	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(path, progress)
	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			result.value = GDSQLResourceLoadProgress.in_progress(
				float(progress[0]) if not progress.is_empty() else 0.0,
			)
		ResourceLoader.THREAD_LOAD_LOADED:
			var resource := ResourceLoader.load_threaded_get(path)
			if resource == null:
				return _load_error(
					result,
					reference,
					&"GDSQL_RESOURCE_REFERENCE_LOAD_FAILED",
					"Threaded Resource loading completed without a Resource: %s" % path,
				)
			result.value = GDSQLResourceLoadProgress.loaded(resource)
		ResourceLoader.THREAD_LOAD_FAILED:
			return _load_error(
				result,
				reference,
				&"GDSQL_RESOURCE_THREADED_LOAD_FAILED",
				"Threaded Resource loading failed: %s" % path,
			)
		_:
			return _load_error(
				result,
				reference,
				&"GDSQL_RESOURCE_THREADED_NOT_REQUESTED",
				"No threaded Resource load is active for '%s'." % path,
			)
	return result


func _resolve_path(reference: GDSQLResourceReference) -> String:
	if not reference.uid.is_empty():
		var resource_uid := ResourceUID.text_to_id(reference.uid)
		if resource_uid != ResourceUID.INVALID_ID and ResourceUID.has_id(resource_uid):
			return ResourceUID.get_id_path(resource_uid)
	return reference.fallback_path


func _validated_path(reference: GDSQLResourceReference) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if reference == null or not reference.is_valid():
		return _load_error(
			result,
			reference,
			&"GDSQL_RESOURCE_REFERENCE_INVALID",
			"Cannot resolve an invalid Resource reference.",
		)
	var path := _resolve_path(reference)
	if path.is_empty() or not ResourceLoader.exists(path):
		return _load_error(
			result,
			reference,
			&"GDSQL_RESOURCE_REFERENCE_MISSING",
			"Referenced Resource is unavailable: %s" % reference.fallback_path,
		)
	result.value = path
	return result


func _load_error(
		result: GDSQLOperationResult,
		reference: GDSQLResourceReference,
		code: StringName,
		message: String,
) -> GDSQLOperationResult:
	result.add_diagnostic(
		GDSQLQueryDiagnostic.new(
			code,
			message,
			GDSQLQueryDiagnostic.Severity.ERROR,
			null,
			reference,
		),
	)
	return result
