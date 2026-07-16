class_name GDSQLSourceSpan
extends RefCounted

var start: int = 0
var end: int = 0


func _init(start: int = 0, end: int = 0) -> void:
	self.start = start
	self.end = end
