@abstract
class_name GDSQLPlanNode
extends RefCounted

var output_schema: GDSQLResultSchema


@abstract
func accept(visitor: GDSQLPlanNodeVisitor) -> Variant
