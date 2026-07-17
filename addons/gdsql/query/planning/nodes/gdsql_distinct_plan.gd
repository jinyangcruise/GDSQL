class_name GDSQLDistinctPlan
extends GDSQLPlanNode

var input: GDSQLPlanNode


func accept(visitor: GDSQLPlanNodeVisitor) -> Variant:
	return visitor.visit_distinct(self)
