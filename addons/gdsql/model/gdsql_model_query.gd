## Model-scoped SELECT frontend that produces canonical query specifications.
class_name GDSQLModelQuery
extends RefCounted

var _context: GDSQLModelContext
var _model_script: Script
var _predicate: GDSQLQueryExpression
var _ordering: Array[GDSQLOrderClause] = []
var _limit := -1
var _offset := 0
var _distinct := false
var _built := false


func _init(context: GDSQLModelContext = null, model_script: Script = null) -> void:
	_context = context
	_model_script = model_script


func where(expression: GDSQLQueryExpression) -> GDSQLModelQuery:
	_ensure_mutable()
	_predicate = expression
	return self


func order_by(
		column_name: StringName,
		direction: GDSQLOrderClause.SortDirection = GDSQLOrderClause.SortDirection.ASCENDING,
) -> GDSQLModelQuery:
	_ensure_mutable()
	_ordering.append(
		GDSQLOrderClause.new(GDSQLColumnExpression.new(column_name), direction),
	)
	return self


func limit(value: int) -> GDSQLModelQuery:
	_ensure_mutable()
	_limit = value
	return self


func offset(value: int) -> GDSQLModelQuery:
	_ensure_mutable()
	_offset = value
	return self


func distinct() -> GDSQLModelQuery:
	_ensure_mutable()
	_distinct = true
	return self


## Builds the canonical SELECT description for this model.
func to_query_spec() -> GDSQLSelectQuerySpec:
	_ensure_mutable()
	if _context == null:
		return null
	var definition_result := _context.resolve_model(_model_script)
	if not definition_result.is_successful():
		return null
	var database_result := _context.resolve_database(_model_script)
	if not database_result.is_successful():
		return null
	var definition := definition_result.get_value() as GDSQLModelDefinition
	var builder := GDSQLSelectQueryBuilder.new(
		database_result.get_database().database_name,
		definition.table_name,
	)
	if _predicate != null:
		builder.where(_predicate)
	for clause in _ordering:
		builder.order_by(clause)
	if _limit >= 0:
		builder.limit(_limit)
	if _offset > 0:
		builder.offset(_offset)
	if _distinct:
		builder.distinct()
	_built = true
	return builder.build()


## Executes the model query and materializes every matching row.
func all() -> GDSQLQueryResult:
	if _context == null:
		return _query_failure(_missing_context())
	var definition_result := _context.resolve_model(_model_script)
	if not definition_result.is_successful():
		return _query_failure(definition_result)
	var database_result := _context.resolve_database(_model_script)
	if not database_result.is_successful():
		return _query_failure(database_result)
	var spec := to_query_spec()
	if spec == null:
		return _query_failure(definition_result)
	var query_result := database_result.get_database().execute(spec)
	if not query_result.is_successful():
		return query_result
	return query_result.materialize(
		GDSQLModelResultMaterializer.new(_context),
		GDSQLResultMapping.for_resource(_model_script),
	)


## Selects the first matching model.
func first() -> GDSQLQueryResult:
	limit(1)
	var result := all()
	if result.is_successful():
		var models: Array = result.get_value()
		result.value = null if models.is_empty() else models[0]
	return result


## Selects one model by its registered primary key.
func find(identity: Variant) -> GDSQLQueryResult:
	if _context == null:
		return _query_failure(_missing_context())
	var definition_result := _context.resolve_model(_model_script)
	if not definition_result.is_successful():
		return _query_failure(definition_result)
	var definition := definition_result.get_value() as GDSQLModelDefinition
	where(GDSQLExpr.column(definition.primary_key).equals(identity))
	return first()


func _query_failure(source: GDSQLOperationResult) -> GDSQLQueryResult:
	var result := GDSQLQueryResult.new()
	result.diagnostics.merge(source.diagnostics)
	return result


func _missing_context() -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.add_diagnostic(
		GDSQLQueryDiagnostic.new(
			&"GDSQL_MODEL_CONTEXT_REQUIRED",
			"Configure GDSQLModels with a model context before querying models.",
		),
	)
	return result


func _ensure_mutable() -> void:
	assert(not _built, "Model query cannot be modified after to_query_spec().")
