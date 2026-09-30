extends RefCounted
## Internal deterministic codec for canonical expressions stored in migrations.

const COLUMN := &"column"
const LITERAL := &"literal"
const ARITHMETIC := &"arithmetic"
const COMPARISON := &"comparison"
const LOGICAL := &"logical"
const NULL_CHECK := &"null_check"
const FUNCTION := &"function"
const CanonicalValue = preload(
	"res://addons/gdsql/migration/gdsql_migration_canonical_value.gd"
)


static func encode(expression: GDSQLQueryExpression) -> Dictionary:
	if expression is GDSQLColumnExpression:
		var column := expression as GDSQLColumnExpression
		if column.column_name == &"" or column.table_alias != &"":
			return { }
		return {"kind": COLUMN, "column": String(column.column_name)}
	if expression is GDSQLLiteralExpression:
		var literal := expression as GDSQLLiteralExpression
		if not _is_supported_literal(literal.value):
			return { }
		return {"kind": LITERAL, "value": literal.value}
	if expression is GDSQLArithmeticExpression:
		var arithmetic := expression as GDSQLArithmeticExpression
		return _binary(
			ARITHMETIC,
			arithmetic.operator,
			arithmetic.left,
			arithmetic.right,
		)
	if expression is GDSQLComparisonExpression:
		var comparison := expression as GDSQLComparisonExpression
		return _binary(
			COMPARISON,
			comparison.operator,
			comparison.left,
			comparison.right,
		)
	if expression is GDSQLLogicalExpression:
		var logical := expression as GDSQLLogicalExpression
		var left := encode(logical.left)
		if left.is_empty():
			return { }
		if logical.operator == GDSQLLogicalExpression.LogicalOperator.NOT:
			if logical.right != null:
				return { }
			return {"kind": LOGICAL, "operator": logical.operator, "left": left}
		return _binary(LOGICAL, logical.operator, logical.left, logical.right)
	if expression is GDSQLNullCheckExpression:
		var null_check := expression as GDSQLNullCheckExpression
		var operand := encode(null_check.operand)
		if operand.is_empty():
			return { }
		return {
			"kind": NULL_CHECK,
			"operator": null_check.operator,
			"operand": operand,
		}
	if expression is GDSQLFunctionExpression:
		var function := expression as GDSQLFunctionExpression
		if function.aggregate or function.name == &"":
			return { }
		var arguments: Array[Dictionary] = []
		for argument in function.arguments:
			var encoded := encode(argument)
			if encoded.is_empty():
				return { }
			arguments.append(encoded)
		return {
			"kind": FUNCTION,
			"name": String(function.name),
			"arguments": arguments,
		}
	return { }


static func decode(payload: Variant) -> GDSQLQueryExpression:
	if not payload is Dictionary:
		return null
	var data := payload as Dictionary
	var kind := StringName(data.get("kind", ""))
	match kind:
		COLUMN:
			var column := StringName(data.get("column", ""))
			return GDSQLColumnExpression.new(column) if column != &"" else null
		LITERAL:
			if not data.has("value"):
				return null
			var value: Variant = data.get("value")
			return GDSQLLiteralExpression.new(value) if _is_supported_literal(value) else null
		ARITHMETIC:
			return _decode_arithmetic(data)
		COMPARISON:
			return _decode_comparison(data)
		LOGICAL:
			return _decode_logical(data)
		NULL_CHECK:
			return _decode_null_check(data)
		FUNCTION:
			return _decode_function(data)
	return null


static func canonical(expression: GDSQLQueryExpression) -> Variant:
	var encoded := encode(expression)
	return CanonicalValue.serialize(encoded) if not encoded.is_empty() else null


static func _binary(
		kind: StringName,
		operator: int,
		left_expression: GDSQLQueryExpression,
		right_expression: GDSQLQueryExpression,
) -> Dictionary:
	var left := encode(left_expression)
	var right := encode(right_expression)
	if left.is_empty() or right.is_empty():
		return { }
	return {
		"kind": kind,
		"operator": operator,
		"left": left,
		"right": right,
	}


static func _decode_arithmetic(data: Dictionary) -> GDSQLQueryExpression:
	var operator := int(data.get("operator", -1))
	var left := decode(data.get("left"))
	var right := decode(data.get("right"))
	if operator < GDSQLArithmeticExpression.ArithmeticOperator.ADD \
			or operator > GDSQLArithmeticExpression.ArithmeticOperator.MODULO \
			or left == null or right == null:
		return null
	return GDSQLArithmeticExpression.new(left, operator, right)


static func _decode_comparison(data: Dictionary) -> GDSQLQueryExpression:
	var operator := int(data.get("operator", -1))
	var left := decode(data.get("left"))
	var right := decode(data.get("right"))
	if operator < GDSQLComparisonExpression.ComparisonOperator.EQUAL \
			or operator > GDSQLComparisonExpression.ComparisonOperator.LESS_THAN_OR_EQUAL \
			or left == null or right == null:
		return null
	return GDSQLComparisonExpression.new(left, operator, right)


static func _decode_logical(data: Dictionary) -> GDSQLQueryExpression:
	var operator := int(data.get("operator", -1))
	var left := decode(data.get("left"))
	if operator < GDSQLLogicalExpression.LogicalOperator.AND \
			or operator > GDSQLLogicalExpression.LogicalOperator.NOT \
			or left == null:
		return null
	if operator == GDSQLLogicalExpression.LogicalOperator.NOT:
		return GDSQLLogicalExpression.new(left, operator)
	var right := decode(data.get("right"))
	return GDSQLLogicalExpression.new(left, operator, right) if right != null else null


static func _decode_null_check(data: Dictionary) -> GDSQLQueryExpression:
	var operator := int(data.get("operator", -1))
	var operand := decode(data.get("operand"))
	if operator < GDSQLNullCheckExpression.NullCheckOperator.IS_NULL \
			or operator > GDSQLNullCheckExpression.NullCheckOperator.IS_NOT_NULL \
			or operand == null:
		return null
	return GDSQLNullCheckExpression.new(operand, operator)


static func _decode_function(data: Dictionary) -> GDSQLQueryExpression:
	var name := StringName(data.get("name", ""))
	var raw_arguments: Variant = data.get("arguments")
	if name == &"" or not raw_arguments is Array:
		return null
	var arguments: Array[GDSQLQueryExpression] = []
	for raw_argument in raw_arguments:
		var argument := decode(raw_argument)
		if argument == null:
			return null
		arguments.append(argument)
	return GDSQLFunctionExpression.new(name, arguments)


static func _is_supported_literal(value: Variant) -> bool:
	if value is Object or value is Callable or value is Signal or value is RID:
		return false
	if value is Array:
		for item in value:
			if not _is_supported_literal(item):
				return false
	if value is Dictionary:
		for key in value:
			if not _is_supported_literal(key) or not _is_supported_literal(value[key]):
				return false
	return true
