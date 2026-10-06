class_name GDSQLTableScanPlan
extends GDSQLPlanNode

var table: GDSQLTableDefinition
var alias: StringName
var required_columns: Array[StringName] = []
var pushed_offset := 0
var pushed_limit := -1


func has_pushed_window() -> bool:
	return pushed_offset > 0 or pushed_limit >= 0


func accept(visitor: GDSQLPlanNodeVisitor) -> Variant:
	return visitor.visit_table_scan(self)
