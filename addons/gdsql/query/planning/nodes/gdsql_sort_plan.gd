class_name GDSQLSortPlan
extends GDSQLPlanNode

var input: GDSQLPlanNode
var ordering: Array[GDSQLOrderClause] = []


func accept(visitor: GDSQLPlanNodeVisitor) -> Variant:
	return visitor.visit_sort(self)
