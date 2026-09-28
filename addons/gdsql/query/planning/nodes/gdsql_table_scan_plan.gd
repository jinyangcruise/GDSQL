class_name GDSQLTableScanPlan
extends GDSQLPlanNode

var table: GDSQLTableDefinition
var alias: StringName
var required_columns: Array[StringName] = []


func accept(visitor: GDSQLPlanNodeVisitor) -> Variant:
	return visitor.visit_table_scan(self)
