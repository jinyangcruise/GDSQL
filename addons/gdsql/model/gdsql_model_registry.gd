class_name GDSQLModelRegistry
extends RefCounted
## Registers model scripts and resolves their logical database roles.

var _database_registry: GDSQLDatabaseRegistry
var _definitions: Dictionary[Script, GDSQLModelDefinition] = { }


func _init(database_registry: GDSQLDatabaseRegistry = null) -> void:
	_database_registry = database_registry


## Captures and validates metadata declared by a model script.
func register(model_script: Script) -> GDSQLOperationResult:
	if model_script == null or not model_script.can_instantiate():
		return _failure(
			&"GDSQL_MODEL_SCRIPT_REQUIRED",
			"A model script that can be instantiated is required.",
		)
	if _definitions.has(model_script):
		return _failure(
			&"GDSQL_MODEL_ALREADY_REGISTERED",
			"The model script is already registered.",
		)
	var candidate: Variant = model_script.new()
	if not candidate is GDSQLModel:
		return _failure(
			&"GDSQL_MODEL_TYPE_REQUIRED",
			"A registered model script must extend GDSQLModel.",
		)
	var model := candidate as GDSQLModel
	if model.database_role() == &"":
		return _failure(
			&"GDSQL_MODEL_DATABASE_ROLE_REQUIRED",
			"A model must declare a logical database role.",
		)
	if model.table_name() == &"":
		return _failure(
			&"GDSQL_MODEL_TABLE_REQUIRED",
			"A model must declare a table name.",
		)
	if model.primary_key() == &"":
		return _failure(
			&"GDSQL_MODEL_PRIMARY_KEY_REQUIRED",
			"A model must declare a primary key.",
		)
	var relationships := model.relationships()
	var relationship_names: Dictionary[StringName, bool] = { }
	for relationship in relationships:
		var validation := _validate_relationship(
			model,
			relationship,
			relationship_names,
		)
		if not validation.is_successful():
			return validation
		relationship_names[relationship.name] = true
	var definition := GDSQLModelDefinition.new(
		model_script,
		model.database_role(),
		model.table_name(),
		model.primary_key(),
		model.access_mode(),
		relationships,
	)
	_definitions[model_script] = definition
	var result := GDSQLOperationResult.new()
	result.value = definition
	return result


## Resolves the stable definition for a registered model script.
func resolve_model(model_script: Script) -> GDSQLOperationResult:
	if not _definitions.has(model_script):
		return _failure(
			&"GDSQL_MODEL_NOT_REGISTERED",
			"The model script is not registered.",
		)
	var result := GDSQLOperationResult.new()
	result.value = _definitions[model_script]
	return result


## Resolves the active database selected for a model's logical role.
func resolve_role(model_script: Script) -> GDSQLDatabaseResult:
	var definition_result := resolve_model(model_script)
	if not definition_result.is_successful():
		var failed := GDSQLDatabaseResult.new()
		failed.diagnostics.merge(definition_result.diagnostics)
		return failed
	if _database_registry == null:
		var failed := GDSQLDatabaseResult.new()
		failed.add_diagnostic(
			GDSQLQueryDiagnostic.new(
				&"GDSQL_DATABASE_REGISTRY_REQUIRED",
				"Model role resolution requires a database registry.",
			),
		)
		return failed
	var definition := definition_result.get_value() as GDSQLModelDefinition
	return _database_registry.resolve_role(definition.database_role)


func _failure(code: StringName, message: String) -> GDSQLOperationResult:
	var result := GDSQLOperationResult.new()
	result.add_diagnostic(GDSQLQueryDiagnostic.new(code, message))
	return result


func _validate_relationship(
		model: GDSQLModel,
		relationship: GDSQLRelationshipDefinition,
		names: Dictionary[StringName, bool],
) -> GDSQLOperationResult:
	if relationship == null:
		return _failure(
			&"GDSQL_MODEL_RELATIONSHIP_REQUIRED",
			"Relationship declarations must contain typed definitions.",
		)
	if relationship.name == &"":
		return _failure(
			&"GDSQL_MODEL_RELATIONSHIP_NAME_REQUIRED",
			"A model relationship must declare a name.",
		)
	if names.has(relationship.name):
		return _failure(
			&"GDSQL_MODEL_RELATIONSHIP_DUPLICATE",
			"Model relationship '%s' is declared more than once." % relationship.name,
		)
	if relationship.local_key == &"" or relationship.related_key == &"":
		return _failure(
			&"GDSQL_MODEL_RELATIONSHIP_KEY_REQUIRED",
			"Model relationship '%s' must declare both keys." % relationship.name,
		)
	if not _has_property(model, relationship.local_key):
		return _failure(
			&"GDSQL_MODEL_RELATIONSHIP_LOCAL_KEY_UNKNOWN",
			"Model relationship '%s' references unknown local key '%s'." % [
				relationship.name,
				relationship.local_key,
			],
		)
	var related_script := relationship.related_model_script
	if related_script == null or not related_script.can_instantiate():
		return _failure(
			&"GDSQL_MODEL_RELATIONSHIP_MODEL_REQUIRED",
			"Model relationship '%s' requires a concrete related model." % relationship.name,
		)
	var related_candidate: Variant = related_script.new()
	if not related_candidate is GDSQLModel:
		return _failure(
			&"GDSQL_MODEL_RELATIONSHIP_MODEL_REQUIRED",
			"The related script for '%s' must extend GDSQLModel." % relationship.name,
		)
	if not _has_property(related_candidate as GDSQLModel, relationship.related_key):
		return _failure(
			&"GDSQL_MODEL_RELATIONSHIP_RELATED_KEY_UNKNOWN",
			"Model relationship '%s' references unknown related key '%s'." % [
				relationship.name,
				relationship.related_key,
			],
		)
	return GDSQLOperationResult.new()


func _has_property(model: GDSQLModel, property_name: StringName) -> bool:
	for property in model.get_property_list():
		if StringName(property.get("name", "")) == property_name:
			return true
	return false
