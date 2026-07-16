class_name GDSQLDeletePlan
extends GDSQLPlanNode

var target: GDSQLTableDefinition
var predicate: GDSQLQueryExpression


func accept(visitor: GDSQLPlanNodeVisitor) -> Variant:
	return visitor.visit_delete(self)
