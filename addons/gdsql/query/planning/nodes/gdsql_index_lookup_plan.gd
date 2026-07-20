class_name GDSQLIndexLookupPlan
extends GDSQLPlanNode

var table: GDSQLTableDefinition
var alias: StringName
var index: GDSQLIndexDefinition
var values: Array[GDSQLQueryExpression] = []


func accept(visitor: GDSQLPlanNodeVisitor) -> Variant:
	return visitor.visit_index_lookup(self)
