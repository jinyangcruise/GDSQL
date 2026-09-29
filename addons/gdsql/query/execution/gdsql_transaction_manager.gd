class_name GDSQLTransactionManager
extends RefCounted

var _storage: GDSQLTableStorage
var _foreign_keys: GDSQLForeignKeyConstraintValidator


func _init(
		storage: GDSQLTableStorage = null,
		foreign_keys: GDSQLForeignKeyConstraintValidator = null,
) -> void:
	_storage = storage
	_foreign_keys = foreign_keys


func begin() -> GDSQLStorageSession:
	return GDSQLStorageSession.new()


func commit(session: GDSQLStorageSession) -> GDSQLStorageCommitResult:
	if _foreign_keys != null:
		var validation := _foreign_keys.validate(session)
		if not validation.is_successful():
			return validation
	return _storage.commit(session)


func rollback(session: GDSQLStorageSession) -> void:
	_storage.rollback(session)
