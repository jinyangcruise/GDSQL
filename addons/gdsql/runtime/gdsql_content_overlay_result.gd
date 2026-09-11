class_name GDSQLContentOverlayResult
extends GDSQLOperationResult
## Carries one composed effective-content snapshot and overlay diagnostics.

var database: GDSQLContentDatabaseSnapshot


func set_database(snapshot: GDSQLContentDatabaseSnapshot) -> void:
	database = snapshot
	value = snapshot
