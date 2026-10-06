@abstract
class_name GDSQLContentPackageFingerprintProvider
extends RefCounted
## Boundary for fingerprinting one immutable package source.

@abstract
func fingerprint(source: GDSQLContentPackageSource) -> GDSQLOperationResult


func _tr(message: String) -> String:
	return TranslationServer.get_or_add_domain(&"GDSQL").translate(message)
