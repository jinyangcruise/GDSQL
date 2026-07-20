class_name GDSQLCheckpointPolicy
extends RefCounted
## Describes when committed dirty state should be checkpointed.

enum Mode {
	IMMEDIATE,
	PERIODIC,
	MANUAL,
	ON_EXIT,
}

var mode: Mode
var interval_seconds: float


## Creates a policy that checkpoints after a committed mutation.
static func immediate() -> GDSQLCheckpointPolicy:
	return GDSQLCheckpointPolicy.new(Mode.IMMEDIATE)


## Creates a policy that checkpoints on a runtime-managed interval.
static func periodic(seconds: float) -> GDSQLCheckpointPolicy:
	return GDSQLCheckpointPolicy.new(Mode.PERIODIC, seconds)


## Creates a policy driven by explicit checkpoint calls.
static func manual() -> GDSQLCheckpointPolicy:
	return GDSQLCheckpointPolicy.new(Mode.MANUAL)


## Creates a policy used during graceful application shutdown.
static func on_exit() -> GDSQLCheckpointPolicy:
	return GDSQLCheckpointPolicy.new(Mode.ON_EXIT)


func _init(
		policy_mode: Mode = Mode.MANUAL,
		periodic_interval_seconds: float = 0.0,
) -> void:
	mode = policy_mode
	interval_seconds = periodic_interval_seconds


## Reports whether this policy contains usable configuration.
func is_valid() -> bool:
	return mode != Mode.PERIODIC or interval_seconds > 0.0
