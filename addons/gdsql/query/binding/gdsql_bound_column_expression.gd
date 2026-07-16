class_name GDSQLBoundColumnExpression
extends GDSQLQueryExpression

var table_id: GDSQLTableId
var column_id: GDSQLColumnId
var source_qualifier: StringName
var data_type: Variant.Type = TYPE_NIL
var nullable: bool = true


func accept(visitor: GDSQLExpressionVisitor) -> Variant:
	return visitor.visit_bound_column(self)
