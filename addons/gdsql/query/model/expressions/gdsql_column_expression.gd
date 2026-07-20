class_name GDSQLColumnExpression
extends GDSQLQueryExpression

var table_alias: StringName
var column_name: StringName


func _init(column: StringName = &"", alias: StringName = &"") -> void:
	self.column_name = column
	self.table_alias = alias


func accept(visitor: GDSQLExpressionVisitor) -> Variant:
	return visitor.visit_column(self)
