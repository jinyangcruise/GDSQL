class_name GDSQLBoundColumnExpression
extends GDSQLQueryExpression

var table_id: GDSQLTableId
var column_id: GDSQLColumnId
var data_type: Variant.Type = TYPE_NIL


func accept(visitor: GDSQLExpressionVisitor) -> Variant:
	return visitor.visit_bound_column(self)
