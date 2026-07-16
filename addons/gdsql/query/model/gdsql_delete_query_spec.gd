class_name GDSQLDeleteQuerySpec
extends GDSQLQuerySpec

var target: GDSQLTableReference
var predicate: GDSQLQueryExpression


func _init() -> void:
	operation = Operation.DELETE


func accept(visitor: GDSQLQuerySpecVisitor) -> Variant:
	return visitor.visit_delete(self)
