class_name GDSQLDatabaseRegistry
extends RefCounted
## Registers open database handles and resolves active logical database roles.
##
## Registration names identify handles inside one application context. Role
## bindings provide stable names such as [constant CONTENT_ROLE],
## [constant SAVE_ROLE], and [constant SETTINGS_ROLE]. Binding a role again
## selects another registered handle for that role. Durable registration
## metadata is supplied through a database registry store.

const CONTENT_ROLE := &"content"
const SAVE_ROLE := &"save"
const SETTINGS_ROLE := &"settings"

var _databases: Dictionary[StringName, GDSQLDatabase] = { }
var _role_bindings: Dictionary[StringName, StringName] = { }
var _store: GDSQLDatabaseRegistryStore


func _init(store: GDSQLDatabaseRegistryStore = null) -> void:
	_store = store


## Loads durable registration metadata for runtime or editor composition.
func load_snapshot() -> GDSQLOperationResult:
	if _store == null:
		return _operation_failure(
			&"GDSQL_DATABASE_REGISTRY_STORE_REQUIRED",
			"A database registry store is required for durable metadata.",
		)
	return _store.load_snapshot()


## Persists complete registration metadata through the configured store.
func save_snapshot(snapshot: GDSQLDatabaseRegistrySnapshot) -> GDSQLOperationResult:
	if _store == null:
		return _operation_failure(
			&"GDSQL_DATABASE_REGISTRY_STORE_REQUIRED",
			"A database registry store is required for durable metadata.",
		)
	return _store.save_snapshot(snapshot)


## Registers an open database handle under an application-local name.
func register(
		registration_name: StringName,
		database: GDSQLDatabase,
) -> GDSQLDatabaseResult:
	if registration_name == &"":
		return _failure(
			&"GDSQL_REGISTRATION_NAME_REQUIRED",
			"A database registration name is required.",
		)
	if database == null or database.database_name == &"" or database.context == null:
		return _failure(
			&"GDSQL_DATABASE_HANDLE_REQUIRED",
			"An open database handle is required.",
		)
	if _databases.has(registration_name):
		return _failure(
			&"GDSQL_DATABASE_ALREADY_REGISTERED",
			"Database registration '%s' already exists." % registration_name,
		)
	_databases[registration_name] = database
	return _success(database)


## Removes a registered handle and each role binding that selects it.
func unregister(registration_name: StringName) -> GDSQLDatabaseResult:
	var resolved := resolve(registration_name)
	if not resolved.is_successful():
		return resolved
	_databases.erase(registration_name)
	var roles_to_unbind: Array[StringName] = []
	for role_value in _role_bindings:
		var role := StringName(role_value)
		if _role_bindings[role] == registration_name:
			roles_to_unbind.append(role)
	for role in roles_to_unbind:
		_role_bindings.erase(role)
	return resolved


## Resolves a registered database handle by its application-local name.
func resolve(registration_name: StringName) -> GDSQLDatabaseResult:
	if not _databases.has(registration_name):
		return _failure(
			&"GDSQL_DATABASE_NOT_REGISTERED",
			"Database registration '%s' was not found." % registration_name,
		)
	return _success(_databases[registration_name])


## Selects a registered database handle for a logical role.
func bind_role(
		role: StringName,
		registration_name: StringName,
) -> GDSQLDatabaseResult:
	if role == &"":
		return _failure(
			&"GDSQL_DATABASE_ROLE_REQUIRED",
			"A logical database role is required.",
		)
	var resolved := resolve(registration_name)
	if not resolved.is_successful():
		return resolved
	_role_bindings[role] = registration_name
	return resolved


## Resolves the database handle currently selected for a logical role.
func resolve_role(role: StringName) -> GDSQLDatabaseResult:
	if not _role_bindings.has(role):
		return _failure(
			&"GDSQL_DATABASE_ROLE_NOT_BOUND",
			"Database role '%s' has no active binding." % role,
		)
	return resolve(_role_bindings[role])


## Removes the active binding for a logical role.
func unbind_role(role: StringName) -> GDSQLDatabaseResult:
	var resolved := resolve_role(role)
	if not resolved.is_successful():
		return resolved
	_role_bindings.erase(role)
	return resolved


## Reports whether an application-local registration exists.
func is_registered(registration_name: StringName) -> bool:
	return _databases.has(registration_name)


## Reports whether a logical role has an active binding.
func is_role_bound(role: StringName) -> bool:
	return _role_bindings.has(role)


func _success(database: GDSQLDatabase) -> GDSQLDatabaseResult:
	var result := GDSQLDatabaseResult.new()
	result.value = database
	return result


func _failure(code: StringName, message: String) -> GDSQLDatabaseResult:
	var result := GDSQLDatabaseResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result


func _operation_failure(code: StringName, message: String) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
