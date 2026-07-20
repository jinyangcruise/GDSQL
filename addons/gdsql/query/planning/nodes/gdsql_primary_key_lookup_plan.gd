class_name GDSQLPrimaryKeyLookupPlan
extends GDSQLPlanNode

var table: GDSQLTableDefinition
var alias: StringName
var key: GDSQLQueryExpression


func accept(visitor: GDSQLPlanNodeVisitor) -> Variant:
	return visitor.visit_primary_key_lookup(self)
