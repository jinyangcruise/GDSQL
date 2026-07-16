class_name GDSQLFunctionExpression
extends GDSQLQueryExpression

var name: StringName
var arguments: Array[GDSQLQueryExpression] = []
var aggregate: bool = false


func accept(visitor: GDSQLExpressionVisitor) -> Variant:
	return visitor.visit_function(self)
