## Isolated entry point for model registration, role resolution, and queries.
class_name GDSQLModelContext
extends RefCounted

var registry: GDSQLModelRegistry


func _init(model_registry: GDSQLModelRegistry = null) -> void:
	registry = model_registry


## Registers a model script in this context.
func register_model(model_script: Script) -> GDSQLOperationResult:
	if registry == null:
		return _missing_registry()
	return registry.register(model_script)


## Starts a model-scoped SELECT query.
func query(model_script: Script) -> GDSQLModelQuery:
	return GDSQLModelQuery.new(self, model_script)


## Selects one model by its declared primary key.
func find(model_script: Script, identity: Variant) -> GDSQLQueryResult:
	return query(model_script).find(identity)


func resolve_model(model_script: Script) -> GDSQLOperationResult:
	if registry == null:
		return _missing_registry()
	return registry.resolve_model(model_script)


func resolve_database(model_script: Script) -> GDSQLDatabaseResult:
	if registry == null:
		var result := GDSQLDatabaseResult.new()
		result.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_MODEL_REGISTRY_REQUIRED",
				"A model registry is required.",
			),
		)
		return result
	return registry.resolve_role(model_script)


func _missing_registry() -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.add_diagnostic(
		GDSQLQueryDiagnostic.new(
			&"GDSQL_MODEL_REGISTRY_REQUIRED",
			"A model registry is required.",
		),
	)
	return result
