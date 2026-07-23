class_name GDSQLColumnExpression
extends GDSQLQueryExpression

var table_alias: StringName
var column_name: StringName


func _init(_column: StringName = &"", _alias: StringName = &"") -> void:
	column_name = _column
	table_alias = _alias


func accept(visitor: GDSQLExpressionVisitor) -> Variant:
	return visitor.visit_column(self)
