@abstract
class_name GDSQLTableStorage
extends RefCounted

func get_capabilities() -> GDSQLStorageCapabilities:
	return GDSQLStorageCapabilities.new()


func read_table(table: GDSQLTableDefinition, session: GDSQLStorageSession) -> GDSQLTableSnapshot:
	return null


func find_by_primary_key(table: GDSQLTableDefinition, key: Variant, session: GDSQLStorageSession) -> GDSQLRowRecord:
	return null


func find_by_index(
		table: GDSQLTableDefinition,
		index: GDSQLIndexDefinition,
		values: Array[Variant],
		session: GDSQLStorageSession,
) -> Array[GDSQLRowRecord]:
	return []


func find_by_index_range(
		table: GDSQLTableDefinition,
		index: GDSQLIndexDefinition,
		lower_bound: Variant,
		upper_bound: Variant,
		include_lower: bool,
		include_upper: bool,
		session: GDSQLStorageSession,
) -> Array[GDSQLRowRecord]:
	return []


func stage_insert(table: GDSQLTableDefinition, row: GDSQLRowRecord, session: GDSQLStorageSession) -> GDSQLStorageOperationResult:
	return null


func stage_update(table: GDSQLTableDefinition, key: Variant, row: GDSQLRowRecord, session: GDSQLStorageSession) -> GDSQLStorageOperationResult:
	return null


func stage_delete(table: GDSQLTableDefinition, key: Variant, session: GDSQLStorageSession) -> GDSQLStorageOperationResult:
	return null


func commit(session: GDSQLStorageSession) -> GDSQLStorageCommitResult:
	return null


func rollback(session: GDSQLStorageSession) -> void:
	pass
