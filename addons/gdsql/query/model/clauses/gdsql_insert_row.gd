class_name GDSQLInsertRow
extends RefCounted

var values: Array[Variant] = []


func _init(_values: Array[Variant] = []) -> void:
	values = _values.duplicate()
