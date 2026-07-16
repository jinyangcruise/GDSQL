class_name GDSQLTableScanPlan
extends GDSQLPlanNode

var table: GDSQLTableDefinition
var alias: StringName


func accept(visitor: GDSQLPlanNodeVisitor) -> Variant:
	return visitor.visit_table_scan(self)
