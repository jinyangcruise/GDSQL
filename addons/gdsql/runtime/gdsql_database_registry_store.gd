@abstract
class_name GDSQLDatabaseRegistryStore
extends RefCounted
## Persistence boundary for durable database registrations and role bindings.
## Loads the current typed registry snapshot.

@abstract
func load_snapshot() -> GDSQLOperationResult


## Persists a complete typed registry snapshot.
@abstract
func save_snapshot(snapshot: GDSQLDatabaseRegistrySnapshot) -> GDSQLOperationResult


func _tr(message: StringName) -> StringName:
	return TranslationServer.get_or_add_domain(&"GDSQL").translate(message)
