class_name GDSQLFilterPlan
extends GDSQLPlanNode

var input: GDSQLPlanNode
var predicate: GDSQLQueryExpression


func accept(visitor: GDSQLPlanNodeVisitor) -> Variant:
	return visitor.visit_filter(self)
