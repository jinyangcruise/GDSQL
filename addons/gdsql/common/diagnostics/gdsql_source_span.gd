class_name GDSQLSourceSpan
extends RefCounted

var start: int = 0
var end: int = 0


func _init(_start: int = 0, _end: int = 0) -> void:
	start = _start
	end = _end
