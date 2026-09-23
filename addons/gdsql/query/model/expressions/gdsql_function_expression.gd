class_name GDSQLFunctionExpression
extends GDSQLQueryExpression

var name: StringName
var arguments: Array[GDSQLQueryExpression] = []
var aggregate: bool = false
var resolved_return_type: Variant.Type = TYPE_NIL


func _init(
		_name: StringName = &"",
		_arguments: Array[GDSQLQueryExpression] = [],
		_aggregate: bool = false,
		_return_type: Variant.Type = TYPE_NIL,
) -> void:
	name = _name
	for argument in _arguments:
		assert(argument is GDSQLQueryExpression, "Function arguments must be query expressions.")
		arguments.append(argument)
	aggregate = _aggregate
	resolved_return_type = _return_type


func accept(visitor: GDSQLExpressionVisitor) -> Variant:
	return visitor.visit_function(self)
