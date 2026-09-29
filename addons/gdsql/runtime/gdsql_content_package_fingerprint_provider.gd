@abstract
class_name GDSQLContentPackageFingerprintProvider
extends RefCounted
## Boundary for fingerprinting one immutable package source.

@abstract
func fingerprint(source: GDSQLContentPackageSource) -> GDSQLOperationResult
