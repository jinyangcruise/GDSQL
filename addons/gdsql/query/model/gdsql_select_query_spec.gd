class_name GDSQLSelectQuerySpec
extends GDSQLQuerySpec

var source: GDSQLQuerySource
var projections: Array[GDSQLSelectProjection] = []
var joins: Array[GDSQLJoinSpec] = []
var predicate: GDSQLQueryExpression
var grouping: Array[GDSQLQueryExpression] = []
var having: GDSQLQueryExpression
var ordering: Array[GDSQLOrderClause] = []
var limit: int = -1
var offset: int = 0
var distinct: bool = false


func _init() -> void:
	operation = Operation.SELECT


func accept(visitor: GDSQLQuerySpecVisitor) -> Variant:
	return visitor.visit_select(self)
