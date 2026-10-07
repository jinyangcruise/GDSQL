@abstract
class_name GDSQLSaveContentManifestStore
extends RefCounted
## Persistence boundary for one save's expected content package set.

@abstract
func load_manifest() -> GDSQLOperationResult


@abstract
func save_manifest(manifest: GDSQLSaveContentManifest) -> GDSQLOperationResult


func _tr(message: String) -> String:
	return TranslationServer.get_or_add_domain(&"GDSQL").translate(message)
