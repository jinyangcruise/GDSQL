class_name GDSQLTransactionManager
extends RefCounted

var _storage: GDSQLTableStorage


func _init(storage: GDSQLTableStorage = null) -> void:
	_storage = storage


func begin() -> GDSQLStorageSession:
	return GDSQLStorageSession.new()


func commit(session: GDSQLStorageSession) -> GDSQLStorageCommitResult:
	return _storage.commit(session)


func rollback(session: GDSQLStorageSession) -> void:
	_storage.rollback(session)
