## Configured static entry point used by model class query and find helpers.
##
## Application composition installs one default [GDSQLModelContext]. Concrete
## model classes forward themselves explicitly because GDScript does not expose
## the subclass that invoked an inherited static method.
class_name GDSQLModels
extends RefCounted

static var _context: GDSQLModelContext


## Installs the default model context used by static model helpers.
static func configure(context: GDSQLModelContext) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	if context == null or context.registry == null:
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_MODEL_CONTEXT_REQUIRED",
				"A configured model context with a registry is required.",
			),
		)
		return result
	_context = context
	result.value = context
	return result


## Clears the default context during runtime teardown or test isolation.
static func clear_context() -> void:
	_context = null


## Returns the configured default context.
static func get_context() -> GDSQLModelContext:
	return _context


## Starts a query for a concrete model script through the default context.
static func query(model_script: Script) -> GDSQLModelQuery:
	return GDSQLModelQuery.new(_context, model_script)


## Selects one concrete model by its declared primary key.
static func find(model_script: Script, identity: Variant) -> GDSQLQueryResult:
	return query(model_script).find(identity)
