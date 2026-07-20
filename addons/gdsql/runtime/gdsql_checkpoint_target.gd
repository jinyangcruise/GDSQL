@abstract
class_name GDSQLCheckpointTarget
extends RefCounted
## Contract implemented by a database storage composition that supports durable
## checkpoints after transaction commits.
## Reports whether committed state is awaiting durable persistence.

@abstract
func is_dirty() -> bool


## Transfers committed dirty state to its durable backend.
@abstract
func checkpoint() -> GDSQLCheckpointResult
