class_name GDSQLRuntimeNode
extends Node
## Optional scene-tree adapter for the UI-independent GDSQL runtime session.
##
## The node bootstraps editor-authored registrations, schedules periodic dirty
## checkpoints, and performs synchronous pause/exit checkpoints. Operation
## results remain authoritative; signals are notifications for game UI.

signal runtime_started(runtime: GDSQLRuntimeSession)
signal runtime_start_failed(result: GDSQLOperationResult)
signal checkpoint_finished(result: GDSQLCheckpointResult)
signal runtime_stopped(result: GDSQLCheckpointResult)

@export var auto_start := true
@export var registry_path := GDSQLConfigFileDatabaseRegistryStore.DEFAULT_PATH
@export_range(0.0, 3600.0, 0.1, "or_greater") var checkpoint_interval_seconds := 30.0
@export var checkpoint_on_application_pause := true
@export var checkpoint_on_exit := true

var _runtime: GDSQLRuntimeSession
var _start_result: GDSQLOperationResult
var _checkpoint_timer: Timer


func _ready() -> void:
	_checkpoint_timer = get_node_or_null("%CheckpointTimer") as Timer
	if _checkpoint_timer == null:
		_checkpoint_timer = Timer.new()
		_checkpoint_timer.name = "CheckpointTimer"
		add_child(_checkpoint_timer)
	_checkpoint_timer.one_shot = false
	if not _checkpoint_timer.timeout.is_connected(_on_checkpoint_timeout):
		_checkpoint_timer.timeout.connect(_on_checkpoint_timeout)
	if auto_start and _runtime == null:
		start()
	else:
		_configure_timer()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED \
			and checkpoint_on_application_pause \
			and _runtime != null:
		checkpoint_now()


func _exit_tree() -> void:
	if _runtime != null:
		stop(checkpoint_on_exit)


## Bootstraps the runtime once and starts periodic checkpoint scheduling.
func start() -> GDSQLOperationResult:
	if _runtime != null:
		return _start_result
	var started := GDSQLRuntimeFactory.bootstrap(
		registry_path,
		{ },
		_default_checkpoint_policy(),
	)
	_start_result = started
	if not started.is_successful():
		runtime_start_failed.emit(started)
		return started
	_runtime = started.get_value() as GDSQLRuntimeSession
	_configure_timer()
	runtime_started.emit(_runtime)
	return started


## Returns the bootstrapped service session, or null before a successful start.
func get_runtime() -> GDSQLRuntimeSession:
	return _runtime


## Returns the latest bootstrap result for startup diagnostics.
func get_start_result() -> GDSQLOperationResult:
	return _start_result


func is_started() -> bool:
	return _runtime != null


## Resolves a database through the session's logical role binding.
func database(role: StringName) -> GDSQLDatabaseResult:
	if _runtime == null:
		return _database_failure(
			&"GDSQL_RUNTIME_NOT_STARTED",
			"Start the GDSQL runtime before resolving a database.",
		)
	return _runtime.database(role)


## Registers a user-owned model in the active model context.
func register_model(model_script: Script) -> GDSQLOperationResult:
	if _runtime == null:
		return _operation_failure(
			&"GDSQL_RUNTIME_NOT_STARTED",
			"Start the GDSQL runtime before registering models.",
		)
	return _runtime.register_model(model_script)


## Selects a save slot through the session's checkpoint-safe role change.
func select_save_slot(registration_name: StringName) -> GDSQLDatabaseResult:
	if _runtime == null:
		return _database_failure(
			&"GDSQL_RUNTIME_NOT_STARTED",
			"Start the GDSQL runtime before selecting a save slot.",
		)
	return _runtime.select_save_slot(registration_name)


## Checkpoints every committed dirty in-memory registration immediately.
func checkpoint_now() -> GDSQLCheckpointResult:
	if _runtime == null:
		return _checkpoint_failure(
			&"GDSQL_RUNTIME_NOT_STARTED",
			"Start the GDSQL runtime before checkpointing.",
		)
	var result := _runtime.checkpoint_dirty()
	checkpoint_finished.emit(result)
	return result


## Stops scheduling, optionally checkpoints dirty data, and releases the model context.
func stop(checkpoint_before_stop: bool = true) -> GDSQLCheckpointResult:
	if _checkpoint_timer != null:
		_checkpoint_timer.stop()
	var result := GDSQLCheckpointResult.new()
	result.value = false
	if _runtime == null:
		return result
	if checkpoint_before_stop:
		result = checkpoint_now()
	_runtime.shutdown()
	_runtime = null
	runtime_stopped.emit(result)
	return result


func _configure_timer() -> void:
	if _checkpoint_timer == null:
		return
	_checkpoint_timer.stop()
	if _runtime == null or checkpoint_interval_seconds <= 0.0:
		return
	_checkpoint_timer.wait_time = checkpoint_interval_seconds
	_checkpoint_timer.start()


func _default_checkpoint_policy() -> GDSQLCheckpointPolicy:
	if checkpoint_interval_seconds > 0.0:
		return GDSQLCheckpointPolicy.periodic(checkpoint_interval_seconds)
	if checkpoint_on_exit:
		return GDSQLCheckpointPolicy.on_exit()
	return GDSQLCheckpointPolicy.manual()


func _on_checkpoint_timeout() -> void:
	checkpoint_now()


func _operation_failure(code: StringName, message: String) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result


func _database_failure(code: StringName, message: String) -> GDSQLDatabaseResult:
	var result := GDSQLDatabaseResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result


func _checkpoint_failure(code: StringName, message: String) -> GDSQLCheckpointResult:
	var result := GDSQLCheckpointResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result
