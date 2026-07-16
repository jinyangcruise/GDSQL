class_name GDSQLStorageSession
extends RefCounted

var dirty: bool = false
var operations: Array[Dictionary] = []


func clear() -> void:
	operations.clear()
	dirty = false
