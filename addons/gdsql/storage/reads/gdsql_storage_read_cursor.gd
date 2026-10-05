class_name GDSQLStorageReadCursor
extends RefCounted
## Opaque continuation owned by one storage backend. Query execution may pass
## it back to that backend but must not inspect or construct its token.

var _backend_id: StringName
var _database_name: StringName
var _table_name: StringName
var _token: Variant


func _init(
	backend_id: StringName,
	database_name: StringName,
	table_name: StringName,
	token: Variant,
) -> void:
	_backend_id = backend_id
	_database_name = database_name
	_table_name = table_name
	_token = _duplicate_token(token)


func get_backend_id() -> StringName:
	return _backend_id


func get_token() -> Variant:
	return _duplicate_token(_token)


func is_for_backend(backend_id: StringName) -> bool:
	return _backend_id == backend_id


func is_for_source(database_name: StringName, table_name: StringName) -> bool:
	return _database_name == database_name and _table_name == table_name


func is_equivalent_to(other: GDSQLStorageReadCursor) -> bool:
	return other != null \
			and _backend_id == other._backend_id \
			and _database_name == other._database_name \
			and _table_name == other._table_name \
			and _token == other._token


func duplicate_cursor() -> GDSQLStorageReadCursor:
	return GDSQLStorageReadCursor.new(
		_backend_id,
		_database_name,
		_table_name,
		_token,
	)


func _duplicate_token(value: Variant) -> Variant:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	if value is Array:
		return (value as Array).duplicate(true)
	return value
