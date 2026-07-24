@abstract
class_name GDSQLDatabaseExplorer
extends RefCounted
## Discovers logical databases and lightweight table metadata from a known root.

@abstract
func inspect_root(
		data_root: String,
		registration_prefix: StringName = &"",
) -> GDSQLOperationResult
