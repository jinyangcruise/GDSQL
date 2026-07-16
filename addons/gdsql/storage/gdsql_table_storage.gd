@abstract
class_name GDSQLTableStorage
extends RefCounted

func read_table(table: GDSQLTableDefinition, session: GDSQLStorageSession) -> GDSQLTableSnapshot:
	return null


func find_by_primary_key(table: GDSQLTableDefinition, key: Variant, session: GDSQLStorageSession) -> GDSQLRowRecord:
	return null


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
