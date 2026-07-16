class_name GDSQLInsertRow
extends RefCounted

var values: Array[Variant] = []


func _init(p_values: Array[Variant] = []) -> void:
	values = p_values.duplicate()
