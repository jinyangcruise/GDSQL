class_name GDSQLStorageSession
extends RefCounted

var dirty: bool = false
var operations: Array[Dictionary] = []
var table_metadata: Dictionary = { }


func clear() -> void:
	operations.clear()
	table_metadata.clear()
	dirty = false
