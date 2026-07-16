class_name GDSQLUpdateQuerySpec
extends GDSQLQuerySpec

var target: GDSQLTableReference
var assignments: Array[GDSQLColumnAssignment] = []
var predicate: GDSQLQueryExpression


func _init() -> void:
	operation = Operation.UPDATE


func accept(visitor: GDSQLQuerySpecVisitor) -> Variant:
	return visitor.visit_update(self)
