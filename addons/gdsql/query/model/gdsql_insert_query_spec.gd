class_name GDSQLInsertQuerySpec
extends GDSQLQuerySpec

var target: GDSQLTableReference
var columns: Array[StringName] = []
var rows: Array[GDSQLInsertRow] = []


func _init() -> void:
	operation = Operation.INSERT


func accept(visitor: GDSQLQuerySpecVisitor) -> Variant:
	return visitor.visit_insert(self)
