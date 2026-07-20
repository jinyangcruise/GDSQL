class_name GDSQLInsertRow
extends RefCounted

var values: Array[Variant] = []


func _init(values: Array[Variant] = []) -> void:
	self.values = values.duplicate()
