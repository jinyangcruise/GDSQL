@abstract
class_name GDSQLResourceResolver
extends RefCounted
## Materializes storage-neutral Resource references through an injected policy.


@abstract
func resolve(reference: GDSQLResourceReference) -> GDSQLOperationResult
