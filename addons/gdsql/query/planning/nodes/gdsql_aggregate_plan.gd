class_name GDSQLAggregatePlan
extends GDSQLPlanNode

var input: GDSQLPlanNode
var grouping: Array[GDSQLQueryExpression] = []
var projections: Array[GDSQLQueryExpression] = []


func accept(visitor: GDSQLPlanNodeVisitor) -> Variant:
	return visitor.visit_aggregate(self)
