class_name GDSQLRuntimeSession
extends RefCounted
## Ready-to-use database, model, and persistence services for one game runtime.

var _databases: GDSQLDatabaseRegistry
var _models: GDSQLModelContext
var _persistence: GDSQLPersistenceCoordinator


func _init(
		database_registry: GDSQLDatabaseRegistry,
		model_context: GDSQLModelContext,
		persistence_coordinator: GDSQLPersistenceCoordinator,
) -> void:
	assert(database_registry != null)
	assert(model_context != null)
	assert(persistence_coordinator != null)
	_databases = database_registry
	_models = model_context
	_persistence = persistence_coordinator


func get_database_registry() -> GDSQLDatabaseRegistry:
	return _databases


func get_model_context() -> GDSQLModelContext:
	return _models


func get_persistence_coordinator() -> GDSQLPersistenceCoordinator:
	return _persistence


## Resolves the active database selected for a logical role.
func database(role: StringName) -> GDSQLDatabaseResult:
	return _databases.resolve_role(role)


## Registers a model in the session's default model context.
func register_model(model_script: Script) -> GDSQLOperationResult:
	return _models.register_model(model_script)


## Selects another open registration for a logical role.
func select_role(role: StringName, registration_name: StringName) -> GDSQLDatabaseResult:
	if role == GDSQLDatabaseRegistry.SAVE_ROLE:
		return select_save_slot(registration_name)
	return _databases.bind_role(role, registration_name)


## Returns the registration currently selected as the active save slot.
func get_active_save_slot() -> StringName:
	return _databases.get_role_registration(GDSQLDatabaseRegistry.SAVE_ROLE)


## Selects an open save slot after checkpointing the previous slot.
##
## The target is resolved before checkpointing, so an invalid selection cannot
## disturb the current save. A failed checkpoint also leaves the current role
## binding unchanged.
func select_save_slot(registration_name: StringName) -> GDSQLDatabaseResult:
	var target := _databases.resolve(registration_name)
	if not target.is_successful():
		return target
	var current := get_active_save_slot()
	if current == registration_name:
		return target
	if current != &"":
		var checkpoint := checkpoint_save()
		if not checkpoint.is_successful():
			var failed := GDSQLDatabaseResult.new()
			failed.diagnostics.merge(checkpoint.diagnostics)
			return failed
	return _databases.bind_role(GDSQLDatabaseRegistry.SAVE_ROLE, registration_name)


## Checkpoints the database selected for a logical role when required.
## ConfigFile registrations are already durable after commit and return a
## successful result whose value is false.
func checkpoint_role(role: StringName) -> GDSQLCheckpointResult:
	var registration_name := _databases.get_role_registration(role)
	if registration_name == &"":
		return _checkpoint_failure(
			&"GDSQL_DATABASE_ROLE_NOT_BOUND",
			"Database role '%s' has no active binding." % role,
		)
	if not _persistence.is_registered(registration_name):
		var durable_result := GDSQLCheckpointResult.new()
		durable_result.value = false
		return durable_result
	return _persistence.checkpoint(registration_name)


func checkpoint_save() -> GDSQLCheckpointResult:
	return checkpoint_role(GDSQLDatabaseRegistry.SAVE_ROLE)


func checkpoint_dirty() -> GDSQLCheckpointResult:
	return _persistence.checkpoint_dirty()


## Clears the static model context only when this session owns it.
func shutdown() -> void:
	if GDSQLModels.get_context() == _models:
		GDSQLModels.clear_context()


func _checkpoint_failure(code: StringName, message: String) -> GDSQLCheckpointResult:
	var result := GDSQLCheckpointResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
