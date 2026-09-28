class_name GDSQLGodotResourceResolver
extends GDSQLResourceResolver
## Default Resource materializer using Godot UID/path resolution and cache.


func resolve(reference: GDSQLResourceReference) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if reference == null or not reference.is_valid():
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_RESOURCE_REFERENCE_INVALID",
				"Cannot resolve an invalid Resource reference.",
			),
		)
		return result
	var path := _resolve_path(reference)
	if path.is_empty() or not ResourceLoader.exists(path):
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_RESOURCE_REFERENCE_MISSING",
				"Referenced Resource is unavailable: %s" % reference.fallback_path,
				GDSQLQueryDiagnostic.Severity.ERROR,
				null,
				reference,
			),
		)
		return result
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


func _resolve_path(reference: GDSQLResourceReference) -> String:
	if not reference.uid.is_empty():
		var resource_uid := ResourceUID.text_to_id(reference.uid)
		if resource_uid != ResourceUID.INVALID_ID and ResourceUID.has_id(resource_uid):
			return ResourceUID.get_id_path(resource_uid)
	return reference.fallback_path
