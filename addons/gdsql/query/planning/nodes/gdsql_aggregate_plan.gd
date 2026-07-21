class_name GDSQLAggregatePlan
extends GDSQLPlanNode

var input: GDSQLPlanNode
var grouping: Array[GDSQLQueryExpression] = []
var aggregates: Array[GDSQLFunctionExpression] = []


func accept(visitor: GDSQLPlanNodeVisitor) -> Variant:
	return visitor.visit_aggregate(self)
