class_name GDSQLFunctionExpression
extends GDSQLQueryExpression

var name: StringName
var arguments: Array[GDSQLQueryExpression] = []
var aggregate: bool = false


func _init(
		_name: StringName = &"",
		_arguments: Array[GDSQLQueryExpression] = [],
		_aggregate: bool = false,
) -> void:
	name = _name
	for argument in _arguments:
		assert(argument is GDSQLQueryExpression, "Function arguments must be query expressions.")
		arguments.append(argument)
	aggregate = _aggregate


func accept(visitor: GDSQLExpressionVisitor) -> Variant:
	return visitor.visit_function(self)
