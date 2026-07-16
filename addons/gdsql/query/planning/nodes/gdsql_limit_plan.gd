class_name GDSQLLimitPlan
extends GDSQLPlanNode

var input: GDSQLPlanNode
var limit: int = -1
var offset: int = 0


func accept(visitor: GDSQLPlanNodeVisitor) -> Variant:
	return visitor.visit_limit(self)
