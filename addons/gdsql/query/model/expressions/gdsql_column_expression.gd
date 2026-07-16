class_name GDSQLColumnExpression
extends GDSQLQueryExpression

var table_alias: StringName
var column_name: StringName


func _init(p_column: StringName = &"", p_alias: StringName = &"") -> void:
	column_name = p_column
	table_alias = p_alias


func accept(visitor: GDSQLExpressionVisitor) -> Variant:
	return visitor.visit_column(self)
