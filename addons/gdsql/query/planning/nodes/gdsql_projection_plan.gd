class_name GDSQLProjectionPlan
extends GDSQLPlanNode

var input: GDSQLPlanNode
var projections: Array[GDSQLQueryExpression] = []


func accept(visitor: GDSQLPlanNodeVisitor) -> Variant:
	return visitor.visit_projection(self)
