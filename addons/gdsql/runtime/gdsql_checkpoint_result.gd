class_name GDSQLCheckpointResult
extends GDSQLOperationResult
## Reports the outcome of transferring committed dirty state to durable storage.

var checkpointed_databases: Array[StringName] = []
var dirty_databases: Array[StringName] = []


## Records a database whose committed state reached durable storage.
func mark_checkpointed(registration_name: StringName) -> void:
	if not checkpointed_databases.has(registration_name):
		checkpointed_databases.append(registration_name)
	dirty_databases.erase(registration_name)


## Records a database that still contains committed dirty state.
func mark_dirty(registration_name: StringName) -> void:
	if not dirty_databases.has(registration_name):
		dirty_databases.append(registration_name)
	checkpointed_databases.erase(registration_name)
