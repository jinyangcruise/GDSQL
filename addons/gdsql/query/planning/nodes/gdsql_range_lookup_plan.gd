class_name GDSQLRangeLookupPlan
extends GDSQLPlanNode

var table: GDSQLTableDefinition
var alias: StringName
var index: GDSQLIndexDefinition
var lower_bound: GDSQLQueryExpression
var upper_bound: GDSQLQueryExpression
var include_lower: bool = true
var include_upper: bool = true


func accept(visitor: GDSQLPlanNodeVisitor) -> Variant:
	return visitor.visit_range_lookup(self)
