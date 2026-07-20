## Canonical base for values, references, predicates, and calculated expressions.
##
## Fluent methods create a new canonical node. Variant operands form the
## literal-coercion boundary: expressions remain expression operands, while
## other values become [GDSQLLiteralExpression] instances.
@abstract
class_name GDSQLQueryExpression
extends RefCounted


## Creates an equality comparison with a literal or expression operand.
func equals(value: Variant) -> GDSQLComparisonExpression:
	return _compare(GDSQLComparisonExpression.ComparisonOperator.EQUAL, value)


## Creates an inequality comparison with a literal or expression operand.
func not_equals(value: Variant) -> GDSQLComparisonExpression:
	return _compare(GDSQLComparisonExpression.ComparisonOperator.NOT_EQUAL, value)


## Creates a greater-than comparison with a literal or expression operand.
func greater_than(value: Variant) -> GDSQLComparisonExpression:
	return _compare(GDSQLComparisonExpression.ComparisonOperator.GREATER_THAN, value)


## Creates a less-than comparison with a literal or expression operand.
func less_than(value: Variant) -> GDSQLComparisonExpression:
	return _compare(GDSQLComparisonExpression.ComparisonOperator.LESS_THAN, value)


## Creates an inclusive greater-than comparison.
func greater_than_or_equal(value: Variant) -> GDSQLComparisonExpression:
	return _compare(
		GDSQLComparisonExpression.ComparisonOperator.GREATER_THAN_OR_EQUAL,
		value,
	)


## Creates an inclusive less-than comparison.
func less_than_or_equal(value: Variant) -> GDSQLComparisonExpression:
	return _compare(
		GDSQLComparisonExpression.ComparisonOperator.LESS_THAN_OR_EQUAL,
		value,
	)


## Creates an addition expression with a literal or expression operand.
func add(value: Variant) -> GDSQLArithmeticExpression:
	return _arithmetic(GDSQLArithmeticExpression.ArithmeticOperator.ADD, value)


## Creates a subtraction expression with a literal or expression operand.
func subtract(value: Variant) -> GDSQLArithmeticExpression:
	return _arithmetic(GDSQLArithmeticExpression.ArithmeticOperator.SUBTRACT, value)


## Creates a multiplication expression with a literal or expression operand.
func multiply(value: Variant) -> GDSQLArithmeticExpression:
	return _arithmetic(GDSQLArithmeticExpression.ArithmeticOperator.MULTIPLY, value)


## Creates a division expression with a literal or expression operand.
func divide(value: Variant) -> GDSQLArithmeticExpression:
	return _arithmetic(GDSQLArithmeticExpression.ArithmeticOperator.DIVIDE, value)


## Creates a modulo expression with a literal or expression operand.
func modulo(value: Variant) -> GDSQLArithmeticExpression:
	return _arithmetic(GDSQLArithmeticExpression.ArithmeticOperator.MODULO, value)


## Creates a logical conjunction with a literal or expression operand.
func and_(value: Variant) -> GDSQLLogicalExpression:
	return GDSQLLogicalExpression.new(
		self,
		GDSQLLogicalExpression.LogicalOperator.AND,
		_coerce_operand(value),
	)


## Creates a logical disjunction with a literal or expression operand.
func or_(value: Variant) -> GDSQLLogicalExpression:
	return GDSQLLogicalExpression.new(
		self,
		GDSQLLogicalExpression.LogicalOperator.OR,
		_coerce_operand(value),
	)


## Creates the logical inversion of this expression.
func not_() -> GDSQLLogicalExpression:
	return GDSQLLogicalExpression.new(
		self,
		GDSQLLogicalExpression.LogicalOperator.NOT,
	)


## Creates a null check for this expression.
func is_null() -> GDSQLNullCheckExpression:
	return GDSQLNullCheckExpression.new(
		self,
		GDSQLNullCheckExpression.NullCheckOperator.IS_NULL,
	)


## Creates a non-null check for this expression.
func is_not_null() -> GDSQLNullCheckExpression:
	return GDSQLNullCheckExpression.new(
		self,
		GDSQLNullCheckExpression.NullCheckOperator.IS_NOT_NULL,
	)


@abstract
func accept(visitor: GDSQLExpressionVisitor) -> Variant


func _compare(operator: GDSQLComparisonExpression.ComparisonOperator, value: Variant) \
-> GDSQLComparisonExpression:
	return GDSQLComparisonExpression.new(self, operator, _coerce_operand(value))


func _arithmetic(operator: GDSQLArithmeticExpression.ArithmeticOperator, value: Variant) \
-> GDSQLArithmeticExpression:
	return GDSQLArithmeticExpression.new(self, operator, _coerce_operand(value))


func _coerce_operand(value: Variant) -> GDSQLQueryExpression:
	if value is GDSQLQueryExpression:
		return value
	return GDSQLLiteralExpression.new(value)
