class_name GDSQLContentOverlayResult
extends GDSQLOperationResult
## Carries one composed effective-content snapshot and overlay diagnostics.

var database: GDSQLContentDatabaseSnapshot
var provenance: Array[GDSQLContentRowProvenance] = []
var conflicts: Array[GDSQLContentRowConflict] = []


func set_database(snapshot: GDSQLContentDatabaseSnapshot) -> void:
	database = snapshot
	value = snapshot


func add_provenance(origin: GDSQLContentRowProvenance) -> void:
	provenance.append(origin)


func add_conflict(conflict: GDSQLContentRowConflict) -> void:
	conflicts.append(conflict)


func get_row_history(
		table_name: StringName,
		identity: Variant,
) -> Array[GDSQLContentRowProvenance]:
	var history: Array[GDSQLContentRowProvenance] = []
	for origin in provenance:
		if origin.table_name == table_name and origin.identity == identity:
			history.append(origin)
	return history


func get_effective_origin(
		table_name: StringName,
		identity: Variant,
) -> GDSQLContentRowProvenance:
	var history := get_row_history(table_name, identity)
	if history.is_empty() or history[-1].is_removal():
		return null
	return history[-1]
