class_name GDSQLPersistenceCoordinator
extends RefCounted
## Coordinates explicit and policy-driven checkpoints for registered databases.
##
## Transaction commits establish valid visible state. Checkpoints transfer that
## committed state through each registered [GDSQLCheckpointTarget].

var _targets: Dictionary[StringName, GDSQLCheckpointTarget] = { }
var _policies: Dictionary[StringName, GDSQLCheckpointPolicy] = { }


## Registers a checkpoint target and its persistence policy.
func register(
		registration_name: StringName,
		target: GDSQLCheckpointTarget,
		policy: GDSQLCheckpointPolicy = null,
) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if registration_name == &"":
		return _operation_failure(
			&"GDSQL_PERSISTENCE_REGISTRATION_NAME_REQUIRED",
			"A persistence registration name is required.",
		)
	if target == null:
		return _operation_failure(
			&"GDSQL_CHECKPOINT_TARGET_REQUIRED",
			"A checkpoint target is required.",
		)
	var selected_policy := policy if policy != null else GDSQLCheckpointPolicy.manual()
	if not selected_policy.is_valid():
		return _operation_failure(
			&"GDSQL_CHECKPOINT_POLICY_INVALID",
			"The checkpoint policy configuration is invalid.",
		)
	if _targets.has(registration_name):
		return _operation_failure(
			&"GDSQL_PERSISTENCE_ALREADY_REGISTERED",
			"Persistence registration '%s' already exists." % registration_name,
		)
	_targets[registration_name] = target
	_policies[registration_name] = selected_policy
	result.value = target
	return result


## Removes a checkpoint target and its policy.
func unregister(registration_name: StringName) -> GDSQLOperationResult:
	if not _targets.has(registration_name):
		return _operation_failure(
			&"GDSQL_PERSISTENCE_NOT_REGISTERED",
			"Persistence registration '%s' was not found." % registration_name,
		)
	var result := GDSQLOperationResult.new()
	result.value = _targets[registration_name]
	_targets.erase(registration_name)
	_policies.erase(registration_name)
	return result


## Checkpoints one registered database when it contains committed dirty state.
func checkpoint(registration_name: StringName) -> GDSQLCheckpointResult:
	if not _targets.has(registration_name):
		return _checkpoint_failure(
			&"GDSQL_PERSISTENCE_NOT_REGISTERED",
			"Persistence registration '%s' was not found." % registration_name,
		)
	var target := _targets[registration_name]
	if not target.is_dirty():
		var clean_result := GDSQLCheckpointResult.new()
		clean_result.value = false
		return clean_result
	var result := target.checkpoint()
	if result == null:
		return _checkpoint_failure(
			&"GDSQL_CHECKPOINT_RESULT_REQUIRED",
			"The checkpoint target must return a checkpoint result.",
		)
	if result.is_successful():
		result.mark_checkpointed(registration_name)
	else:
		result.mark_dirty(registration_name)
	result.value = result.is_successful()
	return result


## Checkpoints every registered database with committed dirty state.
func checkpoint_dirty() -> GDSQLCheckpointResult:
	var combined := GDSQLCheckpointResult.new()
	for registration_value in _targets:
		var registration_name := StringName(registration_value)
		if not _targets[registration_name].is_dirty():
			continue
		var result := checkpoint(registration_name)
		combined.diagnostics.merge(result.diagnostics)
		for checkpointed in result.checkpointed_databases:
			combined.mark_checkpointed(checkpointed)
		for dirty in result.dirty_databases:
			combined.mark_dirty(dirty)
	combined.value = combined.checkpointed_databases.size()
	return combined


## Applies the immediate policy after a successful transaction commit.
func transaction_committed(registration_name: StringName) -> GDSQLCheckpointResult:
	if not _targets.has(registration_name):
		return _checkpoint_failure(
			&"GDSQL_PERSISTENCE_NOT_REGISTERED",
			"Persistence registration '%s' was not found." % registration_name,
		)
	if _policies[registration_name].mode == GDSQLCheckpointPolicy.Mode.IMMEDIATE:
		return checkpoint(registration_name)
	var result := GDSQLCheckpointResult.new()
	result.value = false
	if _targets[registration_name].is_dirty():
		result.mark_dirty(registration_name)
	return result


## Returns the policy associated with a persistence registration.
func get_policy(registration_name: StringName) -> GDSQLCheckpointPolicy:
	return _policies.get(registration_name)


func _operation_failure(code: StringName, message: String) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result


func _checkpoint_failure(code: StringName, message: String) -> GDSQLCheckpointResult:
	var result := GDSQLCheckpointResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
