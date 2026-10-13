@abstract
class_name GDSQLResourceResolver
extends RefCounted
## Materializes storage-neutral Resource references through an injected policy.


@abstract
func resolve(reference: GDSQLResourceReference) -> GDSQLOperationResult


## Starts a non-blocking load when the resolver supports one. Implementations
## that only support synchronous resolution retain this structured default.
func request_threaded(
		_reference: GDSQLResourceReference,
) -> GDSQLOperationResult:
	return _threaded_unsupported()


## Returns GDSQLResourceLoadProgress for a previously requested reference.
func poll_threaded(
		_reference: GDSQLResourceReference,
) -> GDSQLOperationResult:
	return _threaded_unsupported()


func _threaded_unsupported() -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.add_diagnostic(
		GDSQLQueryDiagnostic.new(
			&"GDSQL_RESOURCE_THREADED_UNSUPPORTED",
			"This Resource resolver does not support threaded loading.",
		),
	)
	return result
