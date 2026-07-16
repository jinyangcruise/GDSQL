class_name GDSQLUpdatePlan
extends GDSQLPlanNode

var target: GDSQLTableDefinition
var assignments: Array[GDSQLColumnAssignment] = []
var predicate: GDSQLQueryExpression


func accept(visitor: GDSQLPlanNodeVisitor) -> Variant:
	return visitor.visit_update(self)
