class_name GDSQLProjectionPlan
extends GDSQLPlanNode

var input: GDSQLPlanNode
var projections: Array[GDSQLSelectProjection] = []


func accept(visitor: GDSQLPlanNodeVisitor) -> Variant:
	return visitor.visit_projection(self)
