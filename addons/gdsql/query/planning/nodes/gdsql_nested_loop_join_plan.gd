class_name GDSQLNestedLoopJoinPlan
extends GDSQLPlanNode

var left: GDSQLPlanNode
var right: GDSQLPlanNode
var type: GDSQLJoinSpec.JoinType
var condition: GDSQLQueryExpression
var right_source: GDSQLBoundTableSource


func accept(visitor: GDSQLPlanNodeVisitor) -> Variant:
	return visitor.visit_nested_loop_join(self)
