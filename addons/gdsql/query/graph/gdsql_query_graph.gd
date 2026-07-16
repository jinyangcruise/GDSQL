class_name GDSQLQueryGraph
extends RefCounted

var nodes: Array[Variant] = []
var connections: Array[Variant] = []


func get_nodes() -> Array[Variant]:
	return nodes


func get_connections() -> Array[Variant]:
	return connections


func validate_structure() -> GDSQLOperationResult:
	return null
