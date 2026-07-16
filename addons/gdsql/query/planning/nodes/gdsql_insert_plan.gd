class_name GDSQLInsertPlan
extends GDSQLPlanNode

var target: GDSQLTableDefinition
var rows: Array[GDSQLRowRecord] = []


func accept(visitor: GDSQLPlanNodeVisitor) -> Variant:
	return visitor.visit_insert(self)
