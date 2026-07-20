class_name GDSQLFunctionExpression
extends GDSQLQueryExpression

var name: StringName
var arguments: Array[GDSQLQueryExpression] = []
var aggregate: bool = false


func _init(
		name: StringName = &"",
		arguments: Array[GDSQLQueryExpression] = [],
		aggregate: bool = false,
) -> void:
	self.name = name
	for argument in arguments:
		assert(argument is GDSQLQueryExpression, "Function arguments must be query expressions.")
		self.arguments.append(argument)
	self.aggregate = aggregate


func accept(visitor: GDSQLExpressionVisitor) -> Variant:
	return visitor.visit_function(self)
